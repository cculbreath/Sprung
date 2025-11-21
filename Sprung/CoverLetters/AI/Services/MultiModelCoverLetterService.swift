//
//  MultiModelCoverLetterService.swift
//  Sprung
//
//  Created by Christopher Culbreath on 6/11/25.
//
import SwiftUI
import SwiftData
@Observable
@MainActor
class MultiModelCoverLetterService {

    // MARK: - Published Properties
    var isProcessing = false
    var voteTally: [UUID: Int] = [:]
    var scoreTally: [UUID: Int] = [:]
    var modelReasonings: [(model: String, response: BestCoverLetterResponse)] = []
    var errorMessage: String?
    var progress: Double = 0
    var totalOperations: Int = 0
    var completedOperations: Int = 0
    var reasoningSummary: String?
    var isGeneratingSummary = false
    var failedModels: [String: String] = [:]
    var isCompleted = false
    var pendingModels: Set<String> = []

    // MARK: - Private Properties
    private var currentTask: Task<Void, Never>?
    private let modelNameFormatter = CoverLetterModelNameFormatter()
    private let votingProcessor = CoverLetterVotingProcessor()
    private let summaryGenerator = CoverLetterCommitteeSummaryGenerator()

    // MARK: - Dependencies
    private weak var appState: AppState?
    private weak var jobAppStore: JobAppStore?
    private weak var coverLetterStore: CoverLetterStore?
    private weak var enabledLLMStore: EnabledLLMStore?
    private var llmFacade: LLMFacade?
    private var modelContext: ModelContext?
    private var exportCoordinator: ResumeExportCoordinator?
    private var applicantProfileStore: ApplicantProfileStore?

    // MARK: - Initialization
    init() {}

    func configure(
        appState: AppState,
        jobAppStore: JobAppStore,
        coverLetterStore: CoverLetterStore,
        enabledLLMStore: EnabledLLMStore,
        llmFacade: LLMFacade,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore
    ) {
        self.appState = appState
        self.jobAppStore = jobAppStore
        self.coverLetterStore = coverLetterStore
        self.enabledLLMStore = enabledLLMStore
        self.modelContext = coverLetterStore.modelContext
        self.llmFacade = llmFacade
        self.exportCoordinator = exportCoordinator
        self.applicantProfileStore = applicantProfileStore
        summaryGenerator.configure(llmFacade: llmFacade)
    }

    // MARK: - Public Methods
    func startMultiModelSelection(
        coverLetter: CoverLetter,
        selectedModels: Set<String>,
        selectedVotingScheme: VotingScheme
    ) {
        Logger.info("🎯 Starting multi-model selection with \(selectedModels.count) models")

        // Clear all previous votes, points, and committee analysis for all cover letters in the current job app
        if let jobApp = jobAppStore?.selectedApp {
            clearAllCoverLetterVotes(in: jobApp)
        }

        currentTask = Task {
            await performMultiModelSelection(
                coverLetter: coverLetter,
                selectedModels: selectedModels,
                selectedVotingScheme: selectedVotingScheme
            )
        }
    }

    func cancelSelection() {
        Logger.info("🚫 User requested cancellation of multi-model selection")
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        errorMessage = "Operation cancelled by user"
    }

    func cleanup() {
        currentTask?.cancel()
        currentTask = nil
    }

    func getWinningLetter(for votingScheme: VotingScheme) -> CoverLetter? {
        guard let jobApp = jobAppStore?.selectedApp else { return nil }
        return votingProcessor.getWinningLetter(
            from: jobApp.coverLetters,
            voteTally: voteTally,
            scoreTally: scoreTally,
            votingScheme: votingScheme
        )
    }

    func hasZeroVoteLetters(for votingScheme: VotingScheme) -> Bool {
        guard let jobApp = jobAppStore?.selectedApp else { return false }
        return votingProcessor.hasZeroVoteLetters(
            in: jobApp.coverLetters,
            voteTally: voteTally,
            scoreTally: scoreTally,
            votingScheme: votingScheme
        )
    }

    func deleteZeroVoteLetters(for votingScheme: VotingScheme) {
        guard let jobApp = jobAppStore?.selectedApp,
              let coverLetterStore = coverLetterStore else { return }

        let lettersToDelete = votingProcessor.getZeroVoteLetters(
            from: jobApp.coverLetters,
            voteTally: voteTally,
            scoreTally: scoreTally,
            votingScheme: votingScheme
        )

        for letter in lettersToDelete {
            coverLetterStore.deleteLetter(letter)
            voteTally.removeValue(forKey: letter.id)
            scoreTally.removeValue(forKey: letter.id)
        }

        if lettersToDelete.contains(where: { $0.id == jobApp.selectedCover?.id }) {
            jobApp.selectedCover = getWinningLetter(for: votingScheme)
        }
    }

    func getLetterName(for uuid: String) -> String? {
        guard let jobApp = jobAppStore?.selectedApp,
              let uuid = UUID(uuidString: uuid) else { return nil }
        return jobApp.coverLetters.first(where: { $0.id == uuid })?.sequencedName
    }

    func formatModelNames(_ modelIds: [String]) -> String {
        return modelNameFormatter.formatModelNames(modelIds)
    }

    // MARK: - Private Methods
    private func clearAllCoverLetterVotes(in jobApp: JobApp) {
        Logger.info("🧹 Clearing all previous votes, points, and committee analysis for job app")

        for letter in jobApp.coverLetters {
            // Clear vote and score counts
            letter.voteCount = 0
            letter.scoreCount = 0
            letter.hasBeenAssessed = false

            // Clear committee feedback
            letter.committeeFeedback = nil

            Logger.debug("🧹 Cleared votes and analysis for letter: \(letter.sequencedName)")
        }

        // Clear local tallies
        voteTally.removeAll()
        scoreTally.removeAll()
        modelReasonings.removeAll()
        reasoningSummary = nil
        failedModels.removeAll()

        Logger.info("✅ All cover letter votes and analysis cleared")
    }

    private func performMultiModelSelection(
        coverLetter: CoverLetter,
        selectedModels: Set<String>,
        selectedVotingScheme: VotingScheme
    ) async {
        Logger.info("🚀 Starting multi-model selection with \(selectedModels.count) models using \(selectedVotingScheme.rawValue)")

        await MainActor.run {
            isProcessing = true
            errorMessage = nil
            voteTally = [:]
            scoreTally = [:]
            modelReasonings = []
            failedModels = [:]
            totalOperations = selectedModels.count
            completedOperations = 0
            progress = 0
            pendingModels = selectedModels
        }

        guard let jobApp = jobAppStore?.selectedApp else {
            await MainActor.run {
                errorMessage = "No job application selected"
                isProcessing = false
            }
            return
        }

        _ = coverLetter.writingSamplesString

        guard let resume = jobApp.selectedRes else {
            await MainActor.run {
                errorMessage = "No resume selected for this job application"
                isProcessing = false
            }
            return
        }

        guard let exportCoordinator else {
            await MainActor.run {
                errorMessage = "Export coordinator unavailable"
                isProcessing = false
            }
            return
        }
        guard let applicantProfileStore else {
            await MainActor.run {
                errorMessage = "Applicant profile store unavailable"
                isProcessing = false
            }
            return
        }
        let query = CoverLetterQuery(
            coverLetter: coverLetter,
            resume: resume,
            jobApp: jobApp,
            exportCoordinator: exportCoordinator,
            applicantProfile: applicantProfileStore.currentProfile(),
            saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        )

        // Capture model capabilities and cover letters data before entering async context
        let modelCapabilities = Dictionary(uniqueKeysWithValues: selectedModels.map { modelId in
            let model = enabledLLMStore?.enabledModels.first(where: { $0.modelId == modelId })
            let supportsSchema = model?.supportsJSONSchema ?? false
            let shouldAvoidSchema = model?.shouldAvoidJSONSchema ?? false
            return (modelId, (supportsSchema: supportsSchema, shouldAvoidSchema: shouldAvoidSchema))
        })

        // Capture cover letters to avoid SwiftData concurrency issues
        let coverLetters = jobApp.coverLetters

        // Pre-generate all prompts to avoid capturing non-Sendable types in async closures
        let modelPrompts = Dictionary(uniqueKeysWithValues: selectedModels.map { modelId in
            let capabilities = modelCapabilities[modelId]!
            let includeJSONInstructions = !capabilities.supportsSchema || capabilities.shouldAvoidSchema
            let prompt = query.bestCoverLetterPrompt(
                coverLetters: coverLetters,
                votingScheme: selectedVotingScheme,
                includeJSONInstructions: includeJSONInstructions
            )
            return (modelId, prompt)
        })
        guard let llm = llmFacade else {
            await MainActor.run {
                errorMessage = "LLM service is not configured"
                isProcessing = false
            }
            return
        }
        // Execute models in parallel with real-time result processing
        do {
            try await withThrowingTaskGroup(of: (String, Result<BestCoverLetterResponse, Error>).self) { group in
                // Check for cancellation before starting
                try Task.checkCancellation()
                // Start all model tasks
                Logger.info("🚀 Starting all \(selectedModels.count) model tasks in parallel")
                for modelId in selectedModels {
                    let prompt = modelPrompts[modelId]!
                    group.addTask {
                        do {
                            // Check for cancellation before starting this model
                            try Task.checkCancellation()

                            let response = try await llm.executeFlexibleJSON(
                                prompt: prompt,
                                modelId: modelId,
                                as: BestCoverLetterResponse.self,
                                temperature: nil,
                                jsonSchema: CoverLetterQuery.getJSONSchema(for: selectedVotingScheme)
                            )
                            return (modelId, .success(response))
                        } catch {
                            return (modelId, .failure(error))
                        }
                    }
                }

                // Process results as they come in
                for try await (modelId, result) in group {
                    // Check for cancellation before processing each result
                    try Task.checkCancellation()

                    await MainActor.run {
                        completedOperations += 1
                        progress = Double(completedOperations) / Double(totalOperations)
                        pendingModels.remove(modelId)
                        Logger.debug("📊 Progress update: \(completedOperations)/\(totalOperations) (\(Int(progress * 100))%)")

                        switch result {
                        case .success(let response):
                            modelReasonings.append((model: modelId, response: response))

                            if selectedVotingScheme == .firstPastThePost {
                                if let bestUuid = response.bestLetterUuid,
                                   let uuid = UUID(uuidString: bestUuid) {
                                    voteTally[uuid, default: 0] += 1
                                    Logger.debug("🗳️ \(modelId) voted for \(getLetterName(for: bestUuid) ?? bestUuid)")
                                }
                            } else {
                                if let scoreAllocations = response.scoreAllocations {
                                    let totalAllocated = scoreAllocations.reduce(0) { $0 + $1.score }
                                    if totalAllocated != 20 {
                                        Logger.debug("⚠️ Model \(modelId) allocated \(totalAllocated) points instead of 20!")
                                    }

                                    for allocation in scoreAllocations {
                                        if let uuid = UUID(uuidString: allocation.letterUuid) {
                                            scoreTally[uuid, default: 0] += allocation.score
                                            Logger.debug("📊 Model \(modelId) allocated \(allocation.score) points to \(getLetterName(for: allocation.letterUuid) ?? allocation.letterUuid)")
                                        }
                                    }
                                }
                            }

                        case .failure(let error):
                            failedModels[modelId] = error.localizedDescription
                            Logger.debug("❌ Model \(modelId) failed: \(error.localizedDescription)")
                        }

                        // Update error message based on current results
                        let successCount = modelReasonings.count
                        let failureCount = failedModels.count
                        let totalCompleted = successCount + failureCount

                        // Log major progress milestones
                        if successCount == 1 && failureCount == 0 {
                            Logger.info("🎉 First model completed successfully")
                        }

                        if failureCount > 0 && successCount > 0 {
                            errorMessage = "\(failureCount) of \(totalCompleted) models failed"
                        } else if successCount == 0 && totalCompleted == selectedModels.count {
                            Logger.info("❌ All selected models failed to respond")
                            errorMessage = "All selected models failed to respond"
                            isProcessing = false
                            return
                        } else if failureCount == 0 && totalCompleted > 0 {
                            errorMessage = nil
                        }
                    }
                }
            }
        } catch is CancellationError {
            Logger.info("🚫 Multi-model selection was cancelled")
            await MainActor.run {
                errorMessage = "Operation cancelled by user"
                isProcessing = false
            }
            return
        } catch {
            Logger.error("💥 Multi-model task group failed: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "Multi-model selection failed: \(error.localizedDescription)"
                isProcessing = false
            }
            return
        }

        await MainActor.run {
            isProcessing = false
            Logger.info("✅ Multi-model selection completed. Processing results...")

            for letter in coverLetters {
                if selectedVotingScheme == .firstPastThePost {
                    letter.voteCount = voteTally[letter.id] ?? 0
                    letter.scoreCount = 0
                } else {
                    letter.scoreCount = scoreTally[letter.id] ?? 0
                    letter.voteCount = 0
                }
                letter.hasBeenAssessed = true
            }

            if selectedVotingScheme == .scoreVoting {
                Logger.info("📊 Final Score Tally:")
                for (letterId, score) in scoreTally {
                    if let letter = coverLetters.first(where: { $0.id == letterId }) {
                        Logger.debug("  - \(letter.sequencedName): \(score) points")
                    }
                }
                let totalPoints = scoreTally.values.reduce(0, +)
                Logger.info("  Total points allocated: \(totalPoints) (should be \(selectedModels.count * 20))")
            }

            if !modelReasonings.isEmpty {
                isGeneratingSummary = true
                Logger.info("📝 Starting analysis summary generation with \(modelReasonings.count) model responses")
            }
        }

        if !modelReasonings.isEmpty {
            isGeneratingSummary = true

            Task { @MainActor in
                await generateReasoningSummary(
                    coverLetters: coverLetters,
                    jobApp: jobApp,
                    selectedVotingScheme: selectedVotingScheme
                )
            }
        } else {
            Logger.info("⚠️ No model reasonings to summarize")
        }

        await MainActor.run {
            isCompleted = true
            Logger.info("🏁 MultiModel process completed. Summary state: \(reasoningSummary == nil ? "nil" : "has value")")
            if getWinningLetter(for: selectedVotingScheme) == nil {
                errorMessage = "No clear winner could be determined"
            }
        }
    }

    private func generateReasoningSummary(
        coverLetters: [CoverLetter],
        jobApp: JobApp,
        selectedVotingScheme: VotingScheme
    ) async {
        do {
            let summary = try await summaryGenerator.generateSummary(
                coverLetters: coverLetters,
                jobApp: jobApp,
                modelReasonings: modelReasonings,
                voteTally: voteTally,
                scoreTally: scoreTally,
                selectedVotingScheme: selectedVotingScheme,
                preferredModelId: modelReasonings.first?.model
            )

            self.reasoningSummary = summary
            self.isGeneratingSummary = false
            Logger.info("✅ Analysis summary generation completed")

            // Save changes to ensure committeeFeedback is persisted
            if let modelContext = modelContext {
                do {
                    try modelContext.save()
                    Logger.debug("💾 Successfully saved committee feedback to database")
                } catch {
                    Logger.error("❌ Failed to save committee feedback: \(error.localizedDescription)")
                }
            }

        } catch {
            Logger.error("❌ Analysis summary generation failed: \(error.localizedDescription)")

            // Update error message to include analysis failure
            let analysisError = "Analysis generation failed: \(error.localizedDescription)"
            if let existingError = errorMessage {
                errorMessage = "\(existingError); \(analysisError)"
            } else {
                errorMessage = analysisError
            }

            // Provide a fallback summary
            let fallbackSummary = summaryGenerator.createFallbackSummary(
                coverLetter: coverLetters.first!,
                coverLetters: coverLetters,
                modelReasonings: modelReasonings,
                voteTally: voteTally,
                scoreTally: scoreTally,
                selectedVotingScheme: selectedVotingScheme
            )

            self.reasoningSummary = fallbackSummary
            self.isGeneratingSummary = false
        }
    }
}
