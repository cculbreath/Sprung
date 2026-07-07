import Foundation
import SwiftUI

/// Errors surfaced by batch cover letter operations.
enum BatchCoverLetterError: LocalizedError {
    case operationsFailed(failureCount: Int, totalCount: Int, details: [String])

    var errorDescription: String? {
        switch self {
        case let .operationsFailed(failureCount, totalCount, details):
            let summary = "\(failureCount) of \(totalCount) cover letter operations failed."
            guard !details.isEmpty else { return summary }
            return summary + "\n" + details.joined(separator: "\n")
        }
    }
}

@MainActor
class BatchCoverLetterGenerator {
    private let coverLetterStore: CoverLetterStore
    private let llmFacade: LLMFacade
    private let exportCoordinator: ResumeExportCoordinator
    private let applicantProfileStore: ApplicantProfileStore
    private let coverRefStore: CoverRefStore
    init(
        coverLetterStore: CoverLetterStore,
        llmFacade: LLMFacade,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
        coverRefStore: CoverRefStore
    ) {
        self.coverLetterStore = coverLetterStore
        self.llmFacade = llmFacade
        self.exportCoordinator = exportCoordinator
        self.applicantProfileStore = applicantProfileStore
        self.coverRefStore = coverRefStore
    }
    /// Generates cover letters in batch for multiple models and revisions.
    /// Each operation is fully self-contained (no shared conversation state),
    /// so parallel tasks cannot race on each other's context.
    /// Throws when any operation fails; successfully generated letters are
    /// already persisted at that point.
    /// - Parameters:
    ///   - baseCoverLetter: The base cover letter to use as template
    ///   - resume: The resume to use for generation
    ///   - models: Array of model identifiers to use
    ///   - revisions: Array of revision types to apply
    ///   - revisionModel: Model to use for revisions (can be "SAME_AS_GENERATING")
    ///   - onProgress: Progress callback with (completed, total) operations
    func generateBatch(
        baseCoverLetter: CoverLetter,
        jobApp: JobApp,
        resume: Resume,
        models: [String],
        knowledgeCards: [KnowledgeCard],
        dossierContext: String?,
        revisions: [CoverLetterPrompts.EditorPrompts],
        revisionModel: String,
        onProgress: @escaping (Int, Int) async -> Void
    ) async throws {
        // Clean up any existing ungenerated drafts before starting
        cleanupUngeneratedDrafts()
        Logger.info("🚀 Starting batch generation with \(models.count) models and \(revisions.count) revisions", category: .ai)
        // Calculate total operations
        let baseGenerations = models.count
        let revisionOperations = models.count * revisions.count
        let totalOperations = baseGenerations + revisionOperations
        // Use actor for thread-safe progress tracking
        actor ProgressTracker {
            private var _completedOperations = 0
            func increment() -> Int {
                _completedOperations += 1
                return _completedOperations
            }
            func get() -> Int {
                return _completedOperations
            }
        }
        let progressTracker = ProgressTracker()
        // Store generated base letters for revision
        var generatedBaseLetters: [CoverLetter] = []
        // Accumulate failures so they surface to the caller instead of
        // silently presenting a partial batch as success.
        var failureDetails: [String] = []
        var firstModelConfigurationError: ModelConfigurationError?
        // Phase 1: Generate base cover letters in parallel
        await withTaskGroup(of: GenerationResult.self) { group in
            for model in models {
                group.addTask { @MainActor [weak self] in
                    guard let self = self else {
                        return GenerationResult(success: false, error: "Self was deallocated")
                    }
                    do {
                        let coverLetter = try await self.generateSingleCoverLetter(
                            baseCoverLetter: baseCoverLetter,
                            jobApp: jobApp,
                            resume: resume,
                            model: model,
                            knowledgeCards: knowledgeCards,
                            dossierContext: dossierContext,
                            revision: nil
                        )
                        return GenerationResult(success: true, model: model, generatedLetter: coverLetter)
                    } catch {
                        Logger.error("🚨 Failed to generate base cover letter for model \(model): \(error)", category: .ai)
                        return GenerationResult(
                            success: false,
                            model: model,
                            error: error.localizedDescription,
                            modelConfigurationError: error as? ModelConfigurationError
                        )
                    }
                }
            }
            // Collect base generation results
            for await result in group {
                let completed = await progressTracker.increment()
                await onProgress(completed, totalOperations)
                if result.success, let letter = result.generatedLetter {
                    generatedBaseLetters.append(letter)
                } else {
                    failureDetails.append("Generation (\(result.model ?? "unknown model")): \(result.error ?? "Unknown error")")
                    if firstModelConfigurationError == nil {
                        firstModelConfigurationError = result.modelConfigurationError
                    }
                }
            }
        }
        // Phase 2: Generate revisions in parallel (only if we have base letters and revisions are requested)
        if !revisions.isEmpty && !generatedBaseLetters.isEmpty {
            await withTaskGroup(of: GenerationResult.self) { group in
                for baseLetter in generatedBaseLetters {
                    for revision in revisions {
                        group.addTask { @MainActor [weak self] in
                            guard let self = self else {
                                return GenerationResult(success: false, error: "Self was deallocated")
                            }
                            do {
                                // Handle "same as generating model" option
                                let modelToUseForRevisions: String
                                if revisionModel == "SAME_AS_GENERATING" {
                                    guard let generationModel = baseLetter.generationModel, !generationModel.isEmpty else {
                                        throw ModelConfigurationError.modelNotConfigured(
                                            settingKey: "generationModel",
                                            operationName: "Batch Cover Letter Revision"
                                        )
                                    }
                                    modelToUseForRevisions = generationModel
                                } else {
                                    modelToUseForRevisions = revisionModel
                                }
                                // Validate we have a model
                                guard !modelToUseForRevisions.isEmpty else {
                                    throw ModelConfigurationError.modelNotConfigured(
                                        settingKey: "revisionModel",
                                        operationName: "Batch Cover Letter Revision"
                                    )
                                }
                                _ = try await self.generateSingleCoverLetter(
                                    baseCoverLetter: baseLetter,
                                    jobApp: jobApp,
                                    resume: resume,
                                    model: modelToUseForRevisions,
                                    knowledgeCards: knowledgeCards,
                                    dossierContext: dossierContext,
                                    revision: revision
                                )
                                return GenerationResult(success: true, model: modelToUseForRevisions)
                            } catch {
                                Logger.error("🚨 Failed to generate revision \(revision.operation.rawValue) for base letter \(baseLetter.name): \(error)", category: .ai)
                                return GenerationResult(
                                    success: false,
                                    model: revisionModel,
                                    error: "\(revision.operation.rawValue) revision of \(baseLetter.name): \(error.localizedDescription)",
                                    modelConfigurationError: error as? ModelConfigurationError
                                )
                            }
                        }
                    }
                }
                // Collect revision results
                for await result in group {
                    let completed = await progressTracker.increment()
                    await onProgress(completed, totalOperations)
                    if !result.success {
                        failureDetails.append("Revision: \(result.error ?? "Unknown error")")
                        if firstModelConfigurationError == nil {
                            firstModelConfigurationError = result.modelConfigurationError
                        }
                    }
                }
            }
        }
        // Final cleanup: Remove any empty letters that might have been created during failed generations
        emergencyCleanup(for: jobApp)
        // Surface failures: a missing model configuration takes priority so the
        // UI can route the user to the model settings picker.
        if let modelConfigurationError = firstModelConfigurationError {
            throw modelConfigurationError
        }
        if !failureDetails.isEmpty {
            throw BatchCoverLetterError.operationsFailed(
                failureCount: failureDetails.count,
                totalCount: totalOperations,
                details: failureDetails
            )
        }
    }
    /// Generates revisions for existing cover letters.
    /// Throws when any revision fails; successful revisions are already persisted.
    /// - Parameters:
    ///   - existingLetters: Array of existing cover letters to revise
    ///   - resume: The resume to use for context
    ///   - revisionModel: The model to use for all revisions
    ///   - revisions: Array of revision types to apply
    ///   - onProgress: Progress callback with (completed, total) operations
    func generateRevisionsForExistingLetters(
        existingLetters: [CoverLetter],
        resume: Resume,
        revisionModel: String,
        revisions: [CoverLetterPrompts.EditorPrompts],
        onProgress: @escaping (Int, Int) async -> Void
    ) async throws {
        // Calculate total operations
        let totalOperations = existingLetters.count * revisions.count
        // Use actor for thread-safe progress tracking
        actor ProgressTracker {
            private var _completedOperations = 0
            func increment() -> Int {
                _completedOperations += 1
                return _completedOperations
            }
        }
        let progressTracker = ProgressTracker()
        var failureDetails: [String] = []
        var firstModelConfigurationError: ModelConfigurationError?
        // Create task group for parallel execution
        await withTaskGroup(of: GenerationResult.self) { group in
            // For each existing letter
            for letter in existingLetters {
                // For each revision type
                for revision in revisions {
                    group.addTask { @MainActor [weak self] in
                        guard let self = self else {
                            return GenerationResult(success: false, error: "Self was deallocated")
                        }
                        do {
                            // Handle "same as generating model" option
                            let modelToUse: String
                            if revisionModel == "SAME_AS_GENERATING" {
                                guard let generationModel = letter.generationModel, !generationModel.isEmpty else {
                                    throw ModelConfigurationError.modelNotConfigured(
                                        settingKey: "generationModel",
                                        operationName: "Batch Cover Letter Revision"
                                    )
                                }
                                modelToUse = generationModel
                            } else {
                                modelToUse = revisionModel
                            }
                            // Get the jobApp from the existing letter
                            guard let jobApp = letter.jobApp else {
                                throw NSError(domain: "BatchGeneration", code: 4, userInfo: [NSLocalizedDescriptionKey: "Existing letter must have an associated job application"])
                            }
                            _ = try await self.generateSingleCoverLetter(
                                baseCoverLetter: letter,
                                jobApp: jobApp,
                                resume: resume,
                                model: modelToUse,
                                revision: revision
                            )
                            return GenerationResult(success: true, model: modelToUse)
                        } catch {
                            return GenerationResult(
                                success: false,
                                model: revisionModel,
                                error: "\(revision.operation.rawValue) revision of \(letter.sequencedName): \(error.localizedDescription)",
                                modelConfigurationError: error as? ModelConfigurationError
                            )
                        }
                    }
                }
            }
            // Collect results and update progress
            for await result in group {
                let completed = await progressTracker.increment()
                await onProgress(completed, totalOperations)
                if !result.success {
                    Logger.error("🚨 Revision generation failed for model \(result.model ?? "unknown"): \(result.error ?? "Unknown error")", category: .ai)
                    failureDetails.append(result.error ?? "Unknown error")
                    if firstModelConfigurationError == nil {
                        firstModelConfigurationError = result.modelConfigurationError
                    }
                }
            }
        }
        if let modelConfigurationError = firstModelConfigurationError {
            throw modelConfigurationError
        }
        if !failureDetails.isEmpty {
            throw BatchCoverLetterError.operationsFailed(
                failureCount: failureDetails.count,
                totalCount: totalOperations,
                details: failureDetails
            )
        }
    }
    /// Generates a single cover letter with the specified model using one
    /// self-contained request (no conversation state).
    @MainActor
    private func generateSingleCoverLetter(
        baseCoverLetter: CoverLetter,
        jobApp: JobApp,
        resume: Resume,
        model: String,
        knowledgeCards: [KnowledgeCard] = [],
        dossierContext: String? = nil,
        revision: CoverLetterPrompts.EditorPrompts?
    ) async throws -> CoverLetter {
        let applicantProfile = applicantProfileStore.currentProfile()
        // Prepare name for the letter (will be used after successful generation)
        let modelName = AIModels.friendlyModelName(for: model) ?? model
        let letterName: String
        if let revision = revision {
            // For revisions, use clean model name + revision type
            letterName = "\(modelName) - \(revision.operation.rawValue)"
        } else {
            // For base generations, include knowledge card indicator if enabled
            var baseName = modelName
            if baseCoverLetter.knowledgeCardInclusion != .none {
                baseName += " with KC"
            }
            letterName = baseName
        }
        // The voice block comes from the writing samples selected for the base
        // letter — the same selection the user made in the sheet.
        let query = CoverLetterQuery(
            coverLetter: baseCoverLetter,
            resume: resume,
            jobApp: jobApp,
            exportCoordinator: exportCoordinator,
            applicantProfile: applicantProfile,
            writersVoice: CoverLetterVoiceContext.build(
                selectedRefs: baseCoverLetter.enabledRefs,
                allRefs: coverRefStore.storedCoverRefs
            ),
            knowledgeCards: knowledgeCards,
            dossierContext: dossierContext,
            saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        )
        let prompt: String
        if let revision = revision {
            prompt = try await query.revisionPrompt(feedback: "", editorPrompt: revision)
        } else {
            prompt = try await query.generationPrompt()
        }
        let responseText = try await llmFacade.executeText(prompt: prompt, modelId: model)
        let content = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Validate that the content is not empty
        guard !content.isEmpty else {
            throw NSError(domain: "BatchGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty response from AI model"])
        }
        // Now create the actual letter object that will be persisted
        let newLetter = CoverLetter(
            enabledRefs: baseCoverLetter.enabledRefs,
            jobApp: jobApp
        )
        newLetter.knowledgeCardInclusion = baseCoverLetter.knowledgeCardInclusion
        newLetter.selectedKnowledgeCardIds = baseCoverLetter.selectedKnowledgeCardIds
        newLetter.content = content
        newLetter.generated = true
        newLetter.moddedDate = Date()
        newLetter.generationModel = model
        newLetter.editorPrompt = revision ?? CoverLetterPrompts.EditorPrompts.zinsser
        // Set the final name - always use "Option X" format for consistency
        let nextOptionLetter = newLetter.getNextOptionLetter()
        newLetter.name = "Option \(nextOptionLetter): \(letterName)"
        // Persist the letter after it's fully populated
        coverLetterStore.addLetter(letter: newLetter, to: jobApp)
        Logger.debug("📝 Created cover letter: \(newLetter.name) for model: \(model)", category: .ai)
        return newLetter
    }
    /// Cleans up any ungenerated draft letters in the store
    func cleanupUngeneratedDrafts() {
        coverLetterStore.deleteUngeneratedDrafts()
    }
    /// Emergency cleanup - deletes any cover letters with empty content that might have been created during failed generations
    func emergencyCleanup(for jobApp: JobApp) {
        let emptyLetters = jobApp.coverLetters.filter { letter in
            letter.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !letter.generated
        }
        for letter in emptyLetters {
            Logger.warning("🧹 Emergency cleanup: Removing empty cover letter: \(letter.sequencedName)", category: .ai)
            coverLetterStore.deleteLetter(letter)
        }
    }
}
// Result type for tracking generation outcomes
private struct GenerationResult {
    let success: Bool
    let model: String?
    let error: String?
    let generatedLetter: CoverLetter?
    let modelConfigurationError: ModelConfigurationError?
    init(
        success: Bool,
        model: String? = nil,
        error: String? = nil,
        generatedLetter: CoverLetter? = nil,
        modelConfigurationError: ModelConfigurationError? = nil
    ) {
        self.success = success
        self.model = model
        self.error = error
        self.generatedLetter = generatedLetter
        self.modelConfigurationError = modelConfigurationError
    }
}
