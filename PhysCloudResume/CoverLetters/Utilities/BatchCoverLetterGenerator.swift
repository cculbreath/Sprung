import Foundation
import SwiftUI

@MainActor
class BatchCoverLetterGenerator {
    private let appState: AppState
    private let jobAppStore: JobAppStore
    private let coverLetterStore: CoverLetterStore
    
    init(appState: AppState, jobAppStore: JobAppStore, coverLetterStore: CoverLetterStore) {
        self.appState = appState
        self.jobAppStore = jobAppStore
        self.coverLetterStore = coverLetterStore
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
        resume: Resume,
        models: [String],
        revisions: [CoverLetterPrompts.EditorPrompts],
        revisionModel: String,
        onProgress: @escaping (Int, Int) async -> Void
    ) async throws {
        // Clean up any existing ungenerated drafts before starting
        cleanupUngeneratedDrafts()
        
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
        
        // Create task group for parallel execution
        await withTaskGroup(of: GenerationResult.self) { group in
            // First, generate base cover letters for each model
            for model in models {
                group.addTask { @MainActor [weak self] in
                    guard let self = self else { 
                        return GenerationResult(success: false, error: "Self was deallocated")
                    }
                    
                    do {
                        let coverLetter = try await self.generateSingleCoverLetter(
                            baseCoverLetter: baseCoverLetter,
                            resume: resume,
                            model: model,
                            revision: nil
                        )
                        
                        // For each base generation, also create revisions
                        if !revisions.isEmpty {
                            // Handle "same as generating model" option
                            let modelToUseForRevisions: String
                            if revisionModel == "SAME_AS_GENERATING" {
                                modelToUseForRevisions = model
                            } else {
                                modelToUseForRevisions = revisionModel
                            }
                            
                            // Generate revisions and track their progress
                            var revisionResults: [GenerationResult] = []
                            for revision in revisions {
                                do {
                                    _ = try await self.generateSingleCoverLetter(
                                        baseCoverLetter: coverLetter,
                                        resume: resume,
                                        model: modelToUseForRevisions,
                                        revision: revision
                                    )
                                    revisionResults.append(GenerationResult(success: true, model: modelToUseForRevisions))
                                } catch {
                                    Logger.error("🚨 Failed to generate revision \(revision.rawValue) for model \(modelToUseForRevisions): \(error)")
                                    revisionResults.append(GenerationResult(success: false, model: modelToUseForRevisions, error: error.localizedDescription))
                                }
                                
                                // Update progress for each revision
                                let completed = await progressTracker.increment()
                                await onProgress(completed, totalOperations)
                            }
                        }
                        
                        return GenerationResult(success: true, model: model)
                    } catch {
                        return GenerationResult(success: false, model: model, error: error.localizedDescription)
                    }
                }
            }
            
            // Collect results and update progress for base generations only
            for await result in group {
                let completed = await progressTracker.increment()
                await onProgress(completed, totalOperations)
                
                if !result.success {
                    Logger.error("🚨 Batch generation failed for model \(result.model ?? "unknown"): \(result.error ?? "Unknown error")")
                }
            }
        }
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
                                modelToUse = letter.generationModel ?? OpenAIModelFetcher.getPreferredModelString()
                            } else {
                                modelToUse = revisionModel
                            }
                            
                            _ = try await self.generateSingleCoverLetter(
                                baseCoverLetter: letter,
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
        resume: Resume,
        model: String,
        revision: CoverLetterPrompts.EditorPrompts?
    ) async throws -> CoverLetter {
        // Set up the model-specific client
        let client = AppLLMClientFactory.createClientForModel(
            model: model,
            appState: appState
        )
        
        // Create provider with the specific client
        let provider = CoverChatProvider(client: client)
        
        // Prepare name for the letter (will be used after successful generation)
        let modelName = AIModels.friendlyModelName(for: model) ?? model
        let letterName: String
        if let revision = revision {
            letterName = "\(modelName) - \(revision.operation.rawValue)"
        } else {
            letterName = modelName
        }
        
        // Set up mode
        let mode: CoverAiMode = revision != nil ? .rewrite : .generate
        
        // Check if this is an o1 model that doesn't support system messages
        let isO1Model = isReasoningModel(model)
        
        // Create a temporary letter object just for prompt generation (not persisted)
        let tempLetter = CoverLetter(
            enabledRefs: baseCoverLetter.enabledRefs,
            jobApp: baseCoverLetter.jobApp
        )
        tempLetter.includeResumeRefs = baseCoverLetter.includeResumeRefs
        tempLetter.content = baseCoverLetter.content
        tempLetter.editorPrompt = revision ?? CoverLetterPrompts.EditorPrompts.zissner
        tempLetter.currentMode = mode
        
        let userMessage = CoverLetterPrompts.generate(
            coverLetter: tempLetter,
            resume: resume,
            mode: mode
        )
        
        // Initialize conversation differently for o1 models
        if isO1Model {
            // For o1 models, manually build conversation history without system message
            let systemMessage = buildSystemMessage(for: model)
            let combinedMessage = systemMessage + "\n\n" + userMessage
            
            // Clear conversation history and add only user message
            provider.conversationHistory = []
            provider.conversationHistory.append(AppLLMMessage(role: .user, text: combinedMessage))
            Logger.debug("🧠 Built conversation history for o1 model without system message: \(model)")
        } else {
            // For other models, use normal system/user message separation
            let systemMessage = buildSystemMessage(for: model)
            _ = provider.initializeConversation(systemPrompt: systemMessage, userPrompt: userMessage)
        }
        
        // Create and execute query
        let query = AppLLMQuery(
            messages: provider.conversationHistory,
            modelIdentifier: model,
            temperature: 1.0
        )
        
        // Execute the API call - MUST succeed before creating the cover letter
        let response = try await provider.executeQuery(query)
        
        // Extract content from response
        let responseText: String
        switch response {
        case .text(let text):
            responseText = provider.extractCoverLetterContent(from: text)
        case .structured(let data):
            if let text = String(data: data, encoding: .utf8) {
                responseText = provider.extractCoverLetterContent(from: text)
            } else {
                responseText = ""
            }
        }
        
        // Validate that the response is not empty BEFORE creating the letter
        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "BatchGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty response from AI model"])
        }
        
        // Create a new cover letter object WITHOUT persisting it yet
        let newLetter = CoverLetter(
            enabledRefs: baseCoverLetter.enabledRefs,
            jobApp: baseCoverLetter.jobApp
        )
        newLetter.includeResumeRefs = baseCoverLetter.includeResumeRefs
        newLetter.content = responseText
        newLetter.generated = true  // Mark as generated since we have content
        newLetter.moddedDate = Date()
        newLetter.generationModel = model
        newLetter.encodedMessageHistory = baseCoverLetter.encodedMessageHistory
        newLetter.currentMode = mode
        newLetter.editorPrompt = revision ?? CoverLetterPrompts.EditorPrompts.zissner
        
        // Get next available option letter BEFORE adding to job app
        let nextOptionLetter = newLetter.getNextOptionLetter()
        newLetter.name = "Option \(nextOptionLetter): \(letterName)"
        
        // Store conversation history
        newLetter.messageHistory = provider.conversationHistory.map { appMessage in
            MessageParams(
                content: appMessage.contentParts.compactMap { 
                    if case let .text(content) = $0 { return content } 
                    return nil 
                }.joined(), 
                role: mapRole(appMessage.role)
            )
        }
        
        // Only persist the letter after it's fully populated
        if let jobApp = baseCoverLetter.jobApp {
            coverLetterStore.addLetter(letter: newLetter, to: jobApp)
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
    
    /// Determines if a model is an o1-series reasoning model that has special requirements
    /// - Parameter modelId: The model identifier to check
    /// - Returns: True if this is an o1 or o1-mini model
    private func isReasoningModel(_ modelId: String) -> Bool {
        let modelLower = modelId.lowercased()
        return modelLower.contains("o1") && !modelLower.contains("o3") && !modelLower.contains("o4")
    }
    
    /// Builds system message with model-specific adjustments
    private func buildSystemMessage(for model: String) -> String {
        var systemMessage = CoverLetterPrompts.systemMessage.content
        
        // Model-specific formatting instructions
        if model.lowercased().contains("gemini") {
            systemMessage += " Do not format your response as JSON. Return the cover letter text directly without any JSON wrapping or structure."
        } else if model.lowercased().contains("claude") {
            // Claude tends to return JSON even when not asked, so be very explicit
            systemMessage += "\n\nIMPORTANT: Return ONLY the plain text body of the cover letter. Do NOT include JSON formatting, do NOT include 'Dear Hiring Manager' or any salutation, do NOT include any closing or signature. Start directly with the first paragraph of the letter body and end with the last paragraph. No JSON, no formatting, just the plain text paragraphs."
        }
        
        return systemMessage
    }
    
    /// Maps AppLLMMessage.Role to MessageParams.MessageRole
    private func mapRole(_ role: AppLLMMessage.Role) -> MessageParams.MessageRole {
        switch role {
        case .system: return .system
        case .user: return .user
        case .assistant: return .assistant
        }
    }
}

// Result type for tracking generation outcomes
private struct GenerationResult {
    let success: Bool
    let model: String?
    let error: String?
    
    init(success: Bool, model: String? = nil, error: String? = nil) {
        self.success = success
        self.model = model
        self.error = error
    }
}

