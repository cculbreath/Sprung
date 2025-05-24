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
        // Calculate total operations
        let baseGenerations = models.count
        let revisionOperations = models.count * revisions.count
        let totalOperations = baseGenerations + revisionOperations
        var completedOperations = 0
        
        // Create task group for parallel execution
        await withTaskGroup(of: GenerationResult.self) { group in
            // First, generate base cover letters for each model
            for model in models {
                group.addTask { [weak self] in
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
                            
                            await self.generateRevisions(
                                baseCoverLetter: coverLetter,
                                resume: resume,
                                model: modelToUseForRevisions,
                                revisions: revisions
                            )
                        }
                        
                        return GenerationResult(success: true, model: model)
                    } catch {
                        return GenerationResult(success: false, model: model, error: error.localizedDescription)
                    }
                }
            }
            
            // Collect results and update progress
            for await result in group {
                completedOperations += 1
                await onProgress(completedOperations, totalOperations)
                
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
        var completedOperations = 0
        
        // Create task group for parallel execution
        await withTaskGroup(of: GenerationResult.self) { group in
            // For each existing letter
            for letter in existingLetters {
                // For each revision type
                for revision in revisions {
                    group.addTask { [weak self] in
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
                completedOperations += 1
                await onProgress(completedOperations, totalOperations)
                
                if !result.success {
                    Logger.error("🚨 Revision generation failed for model \(result.model ?? "unknown"): \(result.error ?? "Unknown error")")
                }
            }
        }
    }
    
    /// Generates a single cover letter with specified model
    private func generateSingleCoverLetter(
        baseCoverLetter: CoverLetter,
        resume: Resume,
        model: String,
        revision: CoverLetterPrompts.EditorPrompts?
    ) async throws -> CoverLetter {
        // Create a new cover letter as a copy of the base
        let newLetter = coverLetterStore.createDuplicate(letter: baseCoverLetter)
        
        // Set up the model-specific client
        let client = AppLLMClientFactory.createClientForModel(
            model: model,
            appState: appState
        )
        
        // Create provider with the specific client
        let provider = CoverChatProvider(client: client)
        
        // Update the letter's name to indicate the model and revision
        let modelName = AIModels.friendlyModelName(for: model) ?? model
        if let revision = revision {
            newLetter.name = "Option \(newLetter.optionLetter): \(modelName) - \(revision.operation.rawValue)"
        } else {
            newLetter.name = "Option \(newLetter.optionLetter): \(modelName)"
        }
        
        // Set up for generation or revision
        if let revision = revision {
            newLetter.editorPrompt = revision
            newLetter.currentMode = .rewrite
        } else {
            newLetter.currentMode = .generate
        }
        
        // Prepare messages
        let systemMessage = buildSystemMessage(for: model)
        let userMessage = CoverLetterPrompts.generate(
            coverLetter: newLetter,
            resume: resume,
            mode: newLetter.currentMode ?? .generate
        )
        
        // Initialize conversation
        _ = provider.initializeConversation(systemPrompt: systemMessage, userPrompt: userMessage)
        
        // Create and execute query
        let query = AppLLMQuery(
            messages: provider.conversationHistory,
            modelIdentifier: model,
            temperature: 1.0
        )
        
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
        
        // Update the cover letter with generated content
        newLetter.content = responseText
        newLetter.generated = true
        newLetter.moddedDate = Date()
        newLetter.generationModel = model
        
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
        
        return newLetter
    }
    
    /// Generates revisions for a base cover letter
    private func generateRevisions(
        baseCoverLetter: CoverLetter,
        resume: Resume,
        model: String,
        revisions: [CoverLetterPrompts.EditorPrompts]
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for revision in revisions {
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    
                    do {
                        _ = try await self.generateSingleCoverLetter(
                            baseCoverLetter: baseCoverLetter,
                            resume: resume,
                            model: model,
                            revision: revision
                        )
                    } catch {
                        Logger.error("🚨 Failed to generate revision \(revision.rawValue) for model \(model): \(error)")
                    }
                }
            }
        }
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

