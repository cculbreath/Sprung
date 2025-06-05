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
                                modelToUse = letter.generationModel ?? ""
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
        // Use CoverLetterService instead of CoverChatProvider
        
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
        
        // Create a new cover letter object for generation
        let newLetter = CoverLetter(
            enabledRefs: baseCoverLetter.enabledRefs,
            jobApp: baseCoverLetter.jobApp
        )
        newLetter.includeResumeRefs = baseCoverLetter.includeResumeRefs
        newLetter.content = baseCoverLetter.content
        newLetter.currentMode = mode
        newLetter.editorPrompt = revision ?? CoverLetterPrompts.EditorPrompts.zissner
        
        // Generate content using CoverLetterService
        let responseText: String
        if let revision = revision {
            // This is a revision
            responseText = try await CoverLetterService.shared.reviseCoverLetter(
                coverLetter: newLetter,
                resume: resume,
                modelId: model,
                feedback: "",
                editorPrompt: revision
            )
        } else {
            // This is a new generation
            responseText = try await CoverLetterService.shared.generateCoverLetter(
                coverLetter: newLetter,
                resume: resume,
                modelId: model,
                includeResumeRefs: newLetter.includeResumeRefs
            )
        }
        
        // Validate that the response is not empty
        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "BatchGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty response from AI model"])
        }
        
        // Update the letter with the response (CoverLetterService already did this, but ensure it's complete)
        newLetter.content = responseText
        newLetter.generated = true
        newLetter.moddedDate = Date()
        newLetter.generationModel = model
        
        // Get next available option letter BEFORE adding to job app
        let nextOptionLetter = newLetter.getNextOptionLetter()
        newLetter.name = "Option \(nextOptionLetter): \(letterName)"
        
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

