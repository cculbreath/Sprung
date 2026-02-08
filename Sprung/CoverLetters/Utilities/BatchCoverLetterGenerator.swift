import Foundation
import SwiftUI
@MainActor
class BatchCoverLetterGenerator {
    private let coverLetterStore: CoverLetterStore
    private let llmFacade: LLMFacade
    private let coverLetterService: CoverLetterService
    private let exportCoordinator: ResumeExportCoordinator
    private let applicantProfileStore: ApplicantProfileStore
    private let coverRefStore: CoverRefStore
    init(
        coverLetterStore: CoverLetterStore,
        llmFacade: LLMFacade,
        coverLetterService: CoverLetterService,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
        coverRefStore: CoverRefStore
    ) {
        self.coverLetterStore = coverLetterStore
        self.llmFacade = llmFacade
        self.coverLetterService = coverLetterService
        self.exportCoordinator = exportCoordinator
        self.applicantProfileStore = applicantProfileStore
        self.coverRefStore = coverRefStore
    }
    private func executeText(_ prompt: String, modelId: String) async throws -> String {
        return try await llmFacade.executeText(prompt: prompt, modelId: modelId)
    }
    private func startConversation(systemPrompt: String?, userMessage: String, modelId: String) async throws -> (UUID, String) {
        return try await llmFacade.startConversation(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId
        )
    }
    private func continueConversation(userMessage: String, modelId: String, conversationId: UUID) async throws -> String {
        return try await llmFacade.continueConversation(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            images: []
        )
    }
    /// Generates cover letters in batch for multiple models and revisions
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
        revisions: [CoverLetterPrompts.EditorPrompts],
        revisionModel: String,
        onProgress: @escaping (Int, Int) async -> Void
    ) async throws {
        // Clean up any existing ungenerated drafts before starting
        cleanupUngeneratedDrafts()
        // Additional safety: Ensure we're starting with a clean state
        Logger.info("🚀 Starting batch generation with \(models.count) models and \(revisions.count) revisions")
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
                            revision: nil
                        )
                        return GenerationResult(success: true, model: model, generatedLetter: coverLetter)
                    } catch {
                        Logger.error("🚨 Failed to generate base cover letter for model \(model): \(error)")
                        return GenerationResult(success: false, model: model, error: error.localizedDescription)
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
                    Logger.error("🚨 Base generation failed for model \(result.model ?? "unknown"): \(result.error ?? "Unknown error")")
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
                                    revision: revision
                                )
                                return GenerationResult(success: true, model: modelToUseForRevisions)
                            } catch {
                                Logger.error("🚨 Failed to generate revision \(revision.rawValue) for base letter \(baseLetter.name): \(error)")
                                return GenerationResult(success: false, model: revisionModel, error: error.localizedDescription)
                            }
                        }
                    }
                }
                // Collect revision results
                for await result in group {
                    let completed = await progressTracker.increment()
                    await onProgress(completed, totalOperations)
                    if !result.success {
                        Logger.error("🚨 Revision generation failed: \(result.error ?? "Unknown error")")
                    }
                }
            }
        }
        // Final cleanup: Remove any empty letters that might have been created during failed generations
        emergencyCleanup(for: jobApp)
    }
    /// Generates revisions for existing cover letters
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
                                modelToUse = letter.generationModel ?? ""
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
                            return GenerationResult(success: false, model: revisionModel, error: error.localizedDescription)
                        }
                    }
                }
            }
            // Collect results and update progress
            for await result in group {
                let completed = await progressTracker.increment()
                await onProgress(completed, totalOperations)
                if !result.success {
                    Logger.error("🚨 Revision generation failed for model \(result.model ?? "unknown"): \(result.error ?? "Unknown error")")
                }
            }
        }
    }
    /// Generates a single cover letter with specified model
    @MainActor
    private func generateSingleCoverLetter(
        baseCoverLetter: CoverLetter,
        jobApp: JobApp,
        resume: Resume,
        model: String,
        revision: CoverLetterPrompts.EditorPrompts?
    ) async throws -> CoverLetter {
        // Debug: Verify jobApp parameter is provided
        Logger.debug("🔍 generateSingleCoverLetter called with jobApp: \(jobApp.id.uuidString)")
        let applicantProfile = applicantProfileStore.currentProfile()
        // Prepare name for the letter (will be used after successful generation)
        let modelName = AIModels.friendlyModelName(for: model) ?? model
        let letterName: String
        if let revision = revision {
            // For revisions, use clean model name + revision type
            letterName = "\(modelName) - \(revision.operation.rawValue)"
        } else {
            // For base generations, include resume background indicator if enabled
            var baseName = modelName
            if baseCoverLetter.includeResumeRefs {
                baseName += " with Res BG"
            }
            letterName = baseName
        }
        // Set up mode
        let mode: CoverAiMode = revision != nil ? .rewrite : .generate
        // Generate content using direct LLM calls (no temporary CoverLetter objects)
        let responseText: String
        var conversationIdForNewLetter: UUID?
        var usesReasoningModelForNewLetter = false
        if let revision = revision {
            // This is a revision - build prompt and call LLM directly
            let query = CoverLetterQuery(
                coverLetter: baseCoverLetter,
                resume: resume,
                jobApp: jobApp,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfile,
                writersVoice: coverRefStore.writersVoice,
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )
            let userMessage = await query.revisionPrompt(
                feedback: "",
                editorPrompt: revision
            )
            // Check if we have an existing conversation for revisions
            if let conversationId = coverLetterService.conversations[baseCoverLetter.id] {
                responseText = try await continueConversation(
                    userMessage: userMessage,
                    modelId: model,
                    conversationId: conversationId
                )
            } else {
                let systemPrompt = query.systemPrompt(for: model)
                let (conversationId, initialResponse) = try await startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userMessage,
                    modelId: model
                )
                coverLetterService.conversations[baseCoverLetter.id] = conversationId
                responseText = initialResponse
            }
        } else {
            // This is a new generation - build prompt and call LLM directly
            let query = CoverLetterQuery(
                coverLetter: baseCoverLetter,
                resume: resume,
                jobApp: jobApp,
                exportCoordinator: exportCoordinator,
                applicantProfile: applicantProfile,
                writersVoice: coverRefStore.writersVoice,
                saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
            )
            let systemPrompt = query.systemPrompt(for: model)
            let userMessage = await query.generationPrompt(includeResumeRefs: baseCoverLetter.includeResumeRefs)
            // Check if this is an o1 model that doesn't support system messages
            let isO1Model = coverLetterService.isReasoningModel(model)
            usesReasoningModelForNewLetter = isO1Model
            if isO1Model {
                let combinedMessage = systemPrompt + "\n\n" + userMessage
                responseText = try await executeText(combinedMessage, modelId: model)
            } else {
                let (newConversationId, initialResponse) = try await startConversation(
                    systemPrompt: systemPrompt,
                    userMessage: userMessage,
                    modelId: model
                )
                conversationIdForNewLetter = newConversationId
                responseText = initialResponse
            }
        }
        // Extract cover letter content from response
        let content = coverLetterService.extractCoverLetterContent(from: responseText, modelId: model)
        // Validate that the content is not empty
        guard !content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "BatchGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty response from AI model"])
        }
        // Now create the actual letter object that will be persisted
        let newLetter = CoverLetter(
            enabledRefs: baseCoverLetter.enabledRefs,
            jobApp: jobApp
        )
        newLetter.includeResumeRefs = baseCoverLetter.includeResumeRefs
        newLetter.content = content
        newLetter.generated = true
        newLetter.moddedDate = Date()
        newLetter.generationModel = model
        newLetter.currentMode = mode
        newLetter.editorPrompt = revision ?? CoverLetterPrompts.EditorPrompts.zinsser
        // Store generation metadata - for revisions, preserve original generation sources
        if revision != nil {
            newLetter.generationSources = baseCoverLetter.generationSources.isEmpty ? baseCoverLetter.enabledRefs : baseCoverLetter.generationSources
            newLetter.generationUsedResumeRefs = baseCoverLetter.generationUsedResumeRefs
        } else {
            newLetter.generationSources = baseCoverLetter.enabledRefs
            newLetter.generationUsedResumeRefs = baseCoverLetter.includeResumeRefs
        }
        // Set the final name - always use "Option X" format for consistency
        let nextOptionLetter = newLetter.getNextOptionLetter()
        newLetter.name = "Option \(nextOptionLetter): \(letterName)"
        // Only persist the letter if generation was successful and content is not empty
        guard !newLetter.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.error("🚨 Not persisting cover letter with empty content for model: \(model)")
            throw NSError(domain: "BatchGeneration", code: 5, userInfo: [NSLocalizedDescriptionKey: "Generated content was empty, letter not persisted"])
        }
        // Persist the letter after it's fully populated
        // Note: jobApp is guaranteed to exist due to guard statement above
        coverLetterStore.addLetter(letter: newLetter, to: jobApp)
        if let conversationIdForNewLetter, !usesReasoningModelForNewLetter {
            coverLetterService.conversations[newLetter.id] = conversationIdForNewLetter
        }
        Logger.debug("📝 Created cover letter: \(newLetter.name) for model: \(model)")
        return newLetter
    }
    // REMOVED: generateRevisions method is no longer needed as revision generation
    // is now handled inline with proper progress tracking
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
            Logger.warning("🧹 Emergency cleanup: Removing empty cover letter: \(letter.sequencedName)")
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
    init(success: Bool, model: String? = nil, error: String? = nil, generatedLetter: CoverLetter? = nil) {
        self.success = success
        self.model = model
        self.error = error
        self.generatedLetter = generatedLetter
    }
}
