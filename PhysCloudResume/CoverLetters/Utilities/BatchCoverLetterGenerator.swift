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
        jobApp: JobApp,
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
                                    modelToUseForRevisions = baseLetter.generationModel ?? "gpt-4o"
                                } else {
                                    modelToUseForRevisions = revisionModel
                                }
                                
                                // Validate we have a model
                                guard !modelToUseForRevisions.isEmpty else {
                                    throw NSError(domain: "BatchGeneration", code: 2, userInfo: [NSLocalizedDescriptionKey: "No model specified for revision"])
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
        
        // Prepare name for the letter (will be used after successful generation)
        let modelName = AIModels.friendlyModelName(for: model) ?? model
        let letterName: String
        if let revision = revision {
            // For revisions, include the base letter name
            let baseName = baseCoverLetter.sequencedName
            letterName = "\(baseName) - \(revision.operation.rawValue) (\(modelName))"
        } else {
            letterName = modelName
        }
        
        // Set up mode
        let mode: CoverAiMode = revision != nil ? .rewrite : .generate
        
        // Create a new cover letter object for generation
        let newLetter = CoverLetter(
            enabledRefs: baseCoverLetter.enabledRefs,
            jobApp: jobApp
        )
        newLetter.includeResumeRefs = baseCoverLetter.includeResumeRefs
        newLetter.content = baseCoverLetter.content
        newLetter.currentMode = mode
        newLetter.editorPrompt = revision ?? CoverLetterPrompts.EditorPrompts.zissner
        
        // Store generation metadata - for revisions, preserve original generation sources
        if revision != nil {
            // For revisions, preserve the original letter's generation metadata
            newLetter.generationSources = baseCoverLetter.generationSources.isEmpty ? baseCoverLetter.enabledRefs : baseCoverLetter.generationSources
            newLetter.generationUsedResumeRefs = baseCoverLetter.generationUsedResumeRefs
        } else {
            // For new generations, use current settings
            newLetter.generationSources = baseCoverLetter.enabledRefs
            newLetter.generationUsedResumeRefs = baseCoverLetter.includeResumeRefs
        }
        
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
        
        // Set the final name - different for revisions vs new generations
        if revision != nil {
            // For revisions, don't add "Option" prefix since it's a revision of an existing letter
            newLetter.name = letterName
        } else {
            // For new generations, use the traditional "Option X" naming
            let nextOptionLetter = newLetter.getNextOptionLetter()
            newLetter.name = "Option \(nextOptionLetter): \(letterName)"
        }
        
        // Persist the letter after it's fully populated
        // Note: jobApp is guaranteed to exist due to guard statement above
        coverLetterStore.addLetter(letter: newLetter, to: jobApp)
        
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
    let generatedLetter: CoverLetter?
    
    init(success: Bool, model: String? = nil, error: String? = nil, generatedLetter: CoverLetter? = nil) {
        self.success = success
        self.model = model
        self.error = error
        self.generatedLetter = generatedLetter
    }
}

