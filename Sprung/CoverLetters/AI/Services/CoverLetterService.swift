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
    private let applicantProfileStore: ApplicantProfileStore
    private let coverRefStore: CoverRefStore
    // MARK: - Initialization
    init(
        llmFacade: LLMFacade,
        exportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
        coverRefStore: CoverRefStore
    ) {
        self.llmFacade = llmFacade
        self.exportCoordinator = exportCoordinator
        self.applicantProfileStore = applicantProfileStore
        self.coverRefStore = coverRefStore
    }
    // MARK: - Cover Letter Generation
    /// Generate a new cover letter from the toolbar (handles creation and management)
    /// - Parameters:
    ///   - jobApp: The job application to generate a cover letter for
    ///   - resume: The resume to use for context
    ///   - modelId: The model ID to use for generation
    ///   - coverLetterStore: The store to create the cover letter in
    ///   - selectedRefs: The selected cover references to include
    ///   - knowledgeCards: Knowledge cards to include in the prompt
    ///   - knowledgeCardInclusion: The knowledge card inclusion mode
    ///   - selectedKnowledgeCardIds: IDs of selected knowledge cards
    ///   - dossierContext: Optional candidate dossier context
    func generateNewCoverLetter(
        jobApp: JobApp,
        resume: Resume,
        modelId: String,
        coverLetterStore: CoverLetterStore,
        selectedRefs: [CoverRef],
        knowledgeCards: [KnowledgeCard],
        knowledgeCardInclusion: KnowledgeCardInclusion,
        selectedKnowledgeCardIds: Set<String>,
        dossierContext: String?
    ) async throws {
        // Create a new cover letter
        let newCoverLetter = coverLetterStore.create(jobApp: jobApp)
        // Set initial properties
        newCoverLetter.content = ""
        newCoverLetter.setEditableName("Generating...")
        newCoverLetter.generated = false
        newCoverLetter.knowledgeCardInclusion = knowledgeCardInclusion
        newCoverLetter.selectedKnowledgeCardIds = selectedKnowledgeCardIds
        newCoverLetter.enabledRefs = selectedRefs
        // Store generation metadata (snapshot of sources and settings at generation time)
        newCoverLetter.generationSources = selectedRefs
        // Set it as the selected cover letter
        jobApp.selectedCover = newCoverLetter
        do {
            // Generate the content
            _ = try await generateCoverLetter(
                coverLetter: newCoverLetter,
                resume: resume,
                modelId: modelId,
                knowledgeCards: knowledgeCards,
                dossierContext: dossierContext
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
    ///   - knowledgeCards: Knowledge cards to include in the prompt
    ///   - dossierContext: Optional candidate dossier context
    /// - Returns: The generated cover letter content
    func generateCoverLetter(
        coverLetter: CoverLetter,
        resume: Resume,
        modelId: String,
        knowledgeCards: [KnowledgeCard] = [],
        dossierContext: String? = nil
    ) async throws -> String {
        let llm = llmFacade
        // Ensure cover letter has an associated job application
        guard let jobApp = coverLetter.jobApp else {
            Logger.error("🚨 Cover letter generation requested without job application (letter id: \(coverLetter.id))")
            throw NSError(
                domain: "CoverLetterService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to generate a cover letter. Please choose a job application first."]
            )
        }
        // Create CoverLetterQuery for centralized prompt management
        let query = CoverLetterQuery(
            coverLetter: coverLetter,
            resume: resume,
            jobApp: jobApp,
            exportCoordinator: exportCoordinator,
            applicantProfile: applicantProfileStore.currentProfile(),
            writersVoice: coverRefStore.writersVoice,
            knowledgeCards: knowledgeCards,
            dossierContext: dossierContext,
            saveDebugPrompt: UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        )
        // Build system and user prompts
        let systemPrompt = query.systemPrompt(for: modelId)
        let userMessage = await query.generationPrompt()
        // Check if this is an o1 model that doesn't support system messages
        let isO1Model = isReasoningModel(modelId)
        let response: String
        if isO1Model {
            let combinedMessage = systemPrompt + "\n\n" + userMessage
            response = try await llm.executeText(
                prompt: combinedMessage,
                modelId: modelId
            )
        } else {
            let (conversationId, initialResponse) = try await llm.startConversation(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId
            )
            conversations[coverLetter.id] = conversationId
            response = initialResponse
        }
        // Extract cover letter content from response
        let content = extractCoverLetterContent(from: response, modelId: modelId)
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
            Logger.error("🚨 Cover letter revision requested without job application (letter id: \(coverLetter.id))")
            throw NSError(
                domain: "CoverLetterService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to revise this cover letter because no job application is selected."]
            )
        }
        // Create CoverLetterQuery for centralized prompt management
        let query = CoverLetterQuery(
            coverLetter: coverLetter,
            resume: resume,
            jobApp: jobApp,
            exportCoordinator: exportCoordinator,
            applicantProfile: applicantProfileStore.currentProfile(),
            writersVoice: coverRefStore.writersVoice,
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
                images: []
            )
        } else {
            let systemPrompt = query.systemPrompt(for: modelId)
            let (conversationId, initialResponse) = try await llm.startConversation(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId
            )
            conversations[coverLetter.id] = conversationId
            response = initialResponse
        }
        // Extract cover letter content from response
        let content = extractCoverLetterContent(from: response, modelId: modelId)
        // Update cover letter
        updateCoverLetter(coverLetter, with: content, modelId: modelId, isRevision: true)
        return content
    }
    // MARK: - Conversation Management
    // MARK: - Helper Methods
    /// Extract cover letter content from response, handling various JSON formats and reasoning models
    internal func extractCoverLetterContent(from text: String, modelId: String) -> String {
        // Reasoning models (o1) return plain text directly, not JSON
        if isReasoningModel(modelId) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Use shared JSON extraction logic from LLMResponseParser
        let extractedJSON = LLMResponseParser.extractJSONFromText(text)

        // If we got the same text back, it's not JSON - return as-is
        if extractedJSON == text {
            return text
        }

        // Try to parse the extracted JSON
        if let data = extractedJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for known field names in priority order
            let knownKeys = ["cover_letter_body", "body_content", "cover_letter", "letter", "content", "text"]
            for key in knownKeys {
                if let value = json[key] as? String {
                    return value
                }
            }
            // If no known keys found, look for any string value that looks like cover letter content
            for (_, value) in json {
                if let stringValue = value as? String,
                   stringValue.count > 100,  // At least 100 characters
                   stringValue.contains(".") || stringValue.contains("\n") {  // Has sentences or paragraphs
                    return stringValue
                }
            }
            // If JSON has only one key-value pair with a string value, use it
            if json.count == 1, let firstValue = json.values.first as? String {
                return firstValue
            }
        }

        // Fallback: return original text if JSON parsing failed
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
            if coverLetter.knowledgeCardInclusion != .none {
                nameSuffix += " with KC"
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
