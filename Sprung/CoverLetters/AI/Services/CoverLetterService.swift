//
//  CoverLetterService.swift
//  Sprung
//
//  Created on 6/5/2025
//
//  Service for cover letter generation and revision using unified LLMService

import Foundation
import SwiftUI

@MainActor
@Observable
final class CoverLetterService {
    // MARK: - Properties
    
    /// Conversation tracking
    internal var conversations: [UUID: UUID] = [:] // coverLetterId -> conversationId
    private let llmFacade: LLMFacade
    private let exportCoordinator: ResumeExportCoordinator

    // MARK: - Initialization

    init(llmFacade: LLMFacade, exportCoordinator: ResumeExportCoordinator) {
        self.llmFacade = llmFacade
        self.exportCoordinator = exportCoordinator
    }
    
    // MARK: - Cover Letter Generation
    
    /// Generate a new cover letter from the toolbar (handles creation and management)
    /// - Parameters:
    ///   - jobApp: The job application to generate a cover letter for
    ///   - resume: The resume to use for context
    ///   - modelId: The model ID to use for generation
    ///   - coverLetterStore: The store to create the cover letter in
    ///   - selectedRefs: The selected cover references to include
    ///   - includeResumeRefs: Whether to include resume background references
    func generateNewCoverLetter(
        jobApp: JobApp,
        resume: Resume,
        modelId: String,
        coverLetterStore: CoverLetterStore,
        selectedRefs: [CoverRef],
        includeResumeRefs: Bool
    ) async throws {
        // Create a new cover letter
        let newCoverLetter = coverLetterStore.create(jobApp: jobApp)
        
        // Set initial properties
        newCoverLetter.content = ""
        newCoverLetter.setEditableName("Generating...")
        newCoverLetter.generated = false
        newCoverLetter.includeResumeRefs = includeResumeRefs
        newCoverLetter.enabledRefs = selectedRefs
        
        // Store generation metadata (snapshot of sources and settings at generation time)
        newCoverLetter.generationSources = selectedRefs
        newCoverLetter.generationUsedResumeRefs = includeResumeRefs
        
        // Set it as the selected cover letter
        jobApp.selectedCover = newCoverLetter
        
        do {
            // Generate the content
            _ = try await generateCoverLetter(
                coverLetter: newCoverLetter,
                resume: resume,
                modelId: modelId,
                includeResumeRefs: includeResumeRefs
            )
            
            Logger.debug("✅ Cover letter generated successfully")
            
        } catch {
            // Clean up the failed cover letter
            coverLetterStore.deleteLetter(newCoverLetter)
            throw error
        }
    }
    
    /// Generate a new cover letter using AI
    /// - Parameters:
    ///   - coverLetter: The cover letter to generate content for
    ///   - resume: The resume to use for context
    ///   - modelId: The model ID to use for generation
    ///   - includeResumeRefs: Whether to include resume references
    /// - Returns: The generated cover letter content
    func generateCoverLetter(
        coverLetter: CoverLetter,
        resume: Resume,
        modelId: String,
        includeResumeRefs: Bool = true
    ) async throws -> String {
        let llm = llmFacade
        // Ensure cover letter has an associated job application
        guard let jobApp = coverLetter.jobApp else {
            throw NSError(domain: "CoverLetterService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cover letter must have an associated job application"])
        }
        
        // Create CoverLetterQuery for centralized prompt management
        let query = CoverLetterQuery(
            coverLetter: coverLetter,
            resume: resume,
            jobApp: jobApp,
            exportCoordinator: exportCoordinator,
            saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        )
        
        // Build system and user prompts
        let systemPrompt = query.systemPrompt(for: modelId)
        let userMessage = await query.generationPrompt(
            mode: .generate,
            includeResumeRefs: includeResumeRefs
        )
        
        // Check if this is an o1 model that doesn't support system messages
        let isO1Model = isReasoningModel(modelId)
        
        let response: String
        if isO1Model {
            let combinedMessage = systemPrompt + "\n\n" + userMessage
            response = try await llm.executeText(
                prompt: combinedMessage,
                modelId: modelId,
                temperature: nil
            )
        } else {
            let (conversationId, initialResponse) = try await llm.startConversation(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                temperature: nil
            )
            conversations[coverLetter.id] = conversationId
            response = initialResponse
        }
        
        // Extract cover letter content from response
        let content = extractCoverLetterContent(from: response)
        
        // Update cover letter
        updateCoverLetter(coverLetter, with: content, modelId: modelId, isRevision: false)
        
        return content
    }
    
    // MARK: - Cover Letter Revision
    
    /// Revise an existing cover letter based on feedback
    /// - Parameters:
    ///   - coverLetter: The cover letter to revise
    ///   - resume: The resume to use for context
    ///   - modelId: The model ID to use for revision
    ///   - feedback: Optional custom feedback
    ///   - editorPrompt: The type of revision to perform
    /// - Returns: The revised cover letter content
    func reviseCoverLetter(
        coverLetter: CoverLetter,
        resume: Resume,
        modelId: String,
        feedback: String? = nil,
        editorPrompt: CoverLetterPrompts.EditorPrompts = .improve
    ) async throws -> String {
        let llm = llmFacade
        // Ensure cover letter has an associated job application
        guard let jobApp = coverLetter.jobApp else {
            throw NSError(domain: "CoverLetterService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cover letter must have an associated job application for revision"])
        }
        
        // Create CoverLetterQuery for centralized prompt management
        let query = CoverLetterQuery(
            coverLetter: coverLetter,
            resume: resume,
            jobApp: jobApp,
            exportCoordinator: exportCoordinator,
            saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        )
        
        // Build user message for revision
        let userMessage = await query.revisionPrompt(
            feedback: feedback ?? "",
            editorPrompt: editorPrompt
        )
        
        // Check if we have an existing conversation
        let response: String
        if let conversationId = conversations[coverLetter.id] {
            response = try await llm.continueConversation(
                userMessage: userMessage,
                modelId: modelId,
                conversationId: conversationId,
                images: [],
                temperature: nil
            )
        } else {
            let systemPrompt = query.systemPrompt(for: modelId)
            let (conversationId, initialResponse) = try await llm.startConversation(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                temperature: nil
            )
            conversations[coverLetter.id] = conversationId
            response = initialResponse
        }
        
        // Extract cover letter content from response
        let content = extractCoverLetterContent(from: response)
        
        // Update cover letter
        updateCoverLetter(coverLetter, with: content, modelId: modelId, isRevision: true)
        
        return content
    }
    
    // MARK: - Conversation Management
    
    
    // MARK: - Helper Methods
    
    /// Extract cover letter content from response, handling Gemini and Claude JSON formats
    internal func extractCoverLetterContent(from text: String) -> String {
        // Check if the response contains curly braces (indicating JSON)
        if text.contains("{") && text.contains("}") {
            // Find the JSON portion (from first { to last })
            if let jsonStart = text.range(of: "{"),
               let jsonEnd = text.range(of: "}", options: .backwards),
               jsonStart.lowerBound <= jsonEnd.lowerBound {
                // Safely extract the substring using indices
                let startIndex = jsonStart.lowerBound
                let endIndex = text.index(after: jsonEnd.lowerBound) // Include the closing brace
                
                // Ensure we don't go past the end of the string
                guard endIndex <= text.endIndex else {
                    return text // Return original text if indices are invalid
                }
                
                let jsonSubstring = String(text[startIndex..<endIndex])
                
                // Try to parse the JSON
                if let data = jsonSubstring.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // First check for known field names
                    let knownKeys = ["cover_letter_body", "body_content", "cover_letter", "letter", "content", "text"]
                    for key in knownKeys {
                        if let value = json[key] as? String {
                            return value
                        }
                    }
                    
                    // If no known keys found, look for any string value that looks like cover letter content
                    // (long enough to be a cover letter, contains multiple sentences/paragraphs)
                    for (_, value) in json {
                        if let stringValue = value as? String,
                           stringValue.count > 100,  // At least 100 characters
                           stringValue.contains(".") || stringValue.contains("\n") {  // Has sentences or paragraphs
                            return stringValue
                        }
                    }
                    
                    // If JSON has only one key-value pair with a string value, use it
                    if json.count == 1,
                       let firstValue = json.values.first as? String {
                        return firstValue
                    }
                }
            }
        }
        
        // If no JSON detected or parsing failed, return as-is
        return text
    }
    
    /// Update cover letter with generated content
    private func updateCoverLetter(
        _ coverLetter: CoverLetter,
        with content: String,
        modelId: String,
        isRevision: Bool
    ) {
        // Update the cover letter with the response
        coverLetter.content = content
        coverLetter.generated = true
        coverLetter.moddedDate = Date()
        coverLetter.generationModel = modelId
        
        let formattedModel = formatModelName(modelId)
        
        // Naming logic update:
        if isRevision {
            // For revisions, append the revision type if it's not present
            let revisionType = coverLetter.editorPrompt.operation.rawValue
            let nameBase = coverLetter.editableName
            
            // Only append the revision type if it's not already there
            if !nameBase.contains(revisionType) {
                coverLetter.setEditableName(nameBase + ", " + revisionType)
            }
        } else {
            // This is a fresh generation of content (not a revision)
            // Get or create an appropriate option letter
            let optionLetter: String
            if coverLetter.optionLetter.isEmpty {
                // No existing option letter, use the next available letter
                optionLetter = coverLetter.getNextOptionLetter()
            } else {
                // Already has an option letter, preserve it
                optionLetter = coverLetter.optionLetter
            }
            
            // Create a descriptive suffix with model and resume background info
            var nameSuffix = formattedModel
            if coverLetter.includeResumeRefs {
                nameSuffix += " with Res BG"
            }
            
            // Set the full name with the "Option X: description" format
            coverLetter.name = "Option \(optionLetter): \(nameSuffix)"
        }
        
        // Note: Message history is handled by LLMService conversation management
    }
    
    /// Format model name to a simplified version
    private func formatModelName(_ modelName: String) -> String {
        // Use AIModels helper if available, otherwise use our local implementation
        if let formattedName = AIModels.friendlyModelName(for: modelName) {
            return formattedName
        }
        
        // Fallback logic if AIModels doesn't have this model
        let components = modelName.split(separator: "-")
        
        // Handle different model naming patterns
        if modelName.lowercased().contains("gpt") {
            if components.count >= 2 {
                // Extract main version (e.g., "GPT-4" from "gpt-4-1106-preview")
                if components[1].allSatisfy({ $0.isNumber || $0 == "." }) { // Check if it's a version number like 4 or 3.5
                    return "GPT-\(components[1])"
                }
            }
        } else if modelName.lowercased().contains("claude") {
            // Handle Claude models
            if components.count >= 2 {
                if components[1] == "3" && components.count >= 3 {
                    // Handle "claude-3-opus-20240229" -> "Claude 3 Opus"
                    return "Claude 3 \(components[2].capitalized)"
                } else {
                    // Handle other Claude versions
                    return "Claude \(components[1])"
                }
            }
        }
        // Default fallback: Use the first part of the model name, capitalized.
        return modelName.split(separator: "-").first?.capitalized ?? modelName.capitalized
    }
    
    /// Determine if a model is an o1-series reasoning model
    internal func isReasoningModel(_ modelId: String) -> Bool {
        let modelLower = modelId.lowercased()
        return modelLower.contains("o1") && !modelLower.contains("o3") && !modelLower.contains("o4")
    }
}
