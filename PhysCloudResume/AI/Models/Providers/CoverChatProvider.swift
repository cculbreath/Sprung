// PhysCloudResume/AI/Models/CoverChatProvider.swift

import Foundation
import PDFKit
import AppKit
import SwiftUI
import SwiftData

@Observable
final class CoverChatProvider {
    // The OpenAI client that will be used for API calls
    private let openAIClient: OpenAIClientProtocol

    var message: String = ""
    var messages: [String] = []
    // Stores generic chat messages for the abstraction layer
    var genericMessages: [ChatMessage] = []
    var errorMessage: String = ""
    var resultsAvailable: Bool = false
    var lastResponse: String = ""

    // MARK: - Initializers

    /// Initialize with the new abstraction layer client
    /// - Parameter client: An OpenAI client conforming to OpenAIClientProtocol
    init(client: OpenAIClientProtocol) {
        openAIClient = client
    }

    /// Formats the model name to a simplified version
    /// - Parameter modelName: The full model name from the API
    /// - Returns: A simplified model name without snapshot dates
    private func formatModelName(_ modelName: String) -> String {
        // Remove any date/snapshot information
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

    /// Add a user message to the chat history
    /// - Parameter text: The message text
    func appendUserMessage(_ text: String) {
        let message = ChatMessage(role: .user, content: text)
        genericMessages.append(message)
    }



    /// Add an assistant message to the chat history
    /// - Parameter text: The message text
    func appendAssistantMessage(_ text: String) {
        let message = ChatMessage(role: .assistant, content: text)
        genericMessages.append(message)
    }

    /// Calls the OpenAI API to generate a cover letter
    /// - Parameters:
    ///   - res: The resume to use
    ///   - jobAppStore: The job app store
    ///   - chatProvider: The chat provider
    ///   - buttons: The cover letter buttons
    ///   - isNewConversation: Whether this is a new conversation (toolbar button press)
    @MainActor
    func coverChatAction(
        res: Resume?,
        jobAppStore: JobAppStore,
        chatProvider _: CoverChatProvider, // chatProvider is self, no need to pass
        buttons: Binding<CoverLetterButtons>,
        isNewConversation: Bool = true
    ) {
        guard let app = jobAppStore.selectedApp else { return }
        guard let selectedCover = app.selectedCover else { return }

        // If generating a new cover letter (using squiggle button) and the current letter is already generated,
        // create a new cover letter by getting the CoverLetterStore from the JobAppStore
        var letter = selectedCover
        if isNewConversation, selectedCover.generated {
            // Create a new cover letter for a fresh generation using the store passed in via JobAppStore
            let newLetter = jobAppStore.coverLetterStore.createDuplicate(letter: selectedCover)
            app.selectedCover = newLetter
            letter = newLetter
        }

        buttons.wrappedValue.runRequested = true

        if isNewConversation {
            // Clear conversation context instead of using deprecated previousResponseId
            Task { @MainActor in
                letter.clearConversationContext()
            }
        }

        let systemMessage = CoverLetterPrompts.systemMessage
        genericMessages = [systemMessage]

        // Get the user input depending on the mode
        let userMessage = CoverLetterPrompts.generate(
            coverLetter: letter,
            resume: res!, // Already safely unwrapped above
            mode: letter.currentMode ?? CoverAiMode.none
        )

        // Update the letter's AI mode to match what we're actually doing
        if letter.currentMode == nil || letter.currentMode == CoverAiMode.none {
            letter.currentMode = .generate
        }
        appendUserMessage(userMessage)
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        Task {
            // Always use ChatCompletions API with conversation management
                let combinedMessage = "System context:\n\(systemMessage.content)\n\nUser message:\n\(userMessage)"
                
                // Use the new conversation management methods
                if isNewConversation {
                    // Start new conversation using the correct method name
                    LLMRequestService.shared.sendCoverLetterConversationRequest(
                        coverLetter: letter,
                        userMessage: combinedMessage,
                        systemPrompt: systemMessage.content,
                        isNewConversation: true,
                        onProgress: { progress in
                            // Handle progress updates if needed
                        },
                        onComplete: { result in
                            Task { @MainActor in
                                switch result {
                                case .success(let content):
                                    self.processResults(
                                        newMessage: content,
                                        coverLetter: letter,
                                        buttons: buttons,
                                        model: modelString,
                                        isRevision: false // New conversation is not a revision
                                    )
                                case .failure(let error):
                                    buttons.wrappedValue.runRequested = false
                                    self.errorMessage = "Error: \(error.localizedDescription)"
                                }
                            }
                        }
                    )
                } else {
                    // Continue existing conversation
                    LLMRequestService.shared.sendCoverLetterConversationRequest(
                        coverLetter: letter,
                        userMessage: userMessage,
                        systemPrompt: nil, // System prompt already in context
                        isNewConversation: false,
                        onProgress: { progress in
                            // Handle progress updates if needed
                        },
                        onComplete: { result in
                            Task { @MainActor in
                                switch result {
                                case .success(let content):
                                    self.processResults(
                                        newMessage: content,
                                        coverLetter: letter,
                                        buttons: buttons,
                                        model: modelString,
                                        isRevision: true // Continuation is always a revision
                                    )
                                case .failure(let error):
                                    buttons.wrappedValue.runRequested = false
                                    self.errorMessage = "Error: \(error.localizedDescription)"
                                }
                            }
                        }
                    )
                }

        }
    }

    private func isResponsesAPIEnabled() -> Bool {
        // Migration to ChatCompletions API - always return false
        return false
    }
    
    // MARK: - New Conversational Methods (ChatCompletions API)
    
    /// Starts a new conversation for cover letter generation/revision
    /// - Parameters:
    ///   - coverLetter: The cover letter to work with
    ///   - userMessage: The initial user message
    ///   - onProgress: Progress callback for streaming responses
    ///   - onComplete: Completion callback with result
    @MainActor
    func startNewCoverLetterConversation(
        coverLetter: CoverLetter,
        userMessage: String,
        onProgress: @escaping (String) -> Void = { _ in },
        onComplete: @escaping (Result<String, Error>) -> Void = { _ in }
    ) {
        // Build system prompt for cover letters
        let systemPrompt = buildCoverLetterSystemPrompt(for: coverLetter)
        
        LLMRequestService.shared.sendCoverLetterConversationRequest(
            coverLetter: coverLetter,
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            isNewConversation: true,
            onProgress: onProgress,
            onComplete: onComplete
        )
    }
    
    /// Continues an existing conversation for the cover letter
    /// - Parameters:
    ///   - coverLetter: The cover letter being discussed
    ///   - userMessage: The user's message to continue the conversation
    ///   - onProgress: Progress callback for streaming responses
    ///   - onComplete: Completion callback with result
    @MainActor
    func continueCoverLetterConversation(
        coverLetter: CoverLetter,
        userMessage: String,
        onProgress: @escaping (String) -> Void = { _ in },
        onComplete: @escaping (Result<String, Error>) -> Void = { _ in }
    ) {
        LLMRequestService.shared.sendCoverLetterConversationRequest(
            coverLetter: coverLetter,
            userMessage: userMessage,
            systemPrompt: nil, // System prompt already in context
            isNewConversation: false,
            onProgress: onProgress,
            onComplete: onComplete
        )
    }
    
    /// Clears the conversation context for a cover letter
    /// - Parameter coverLetter: The cover letter whose conversation should be cleared
    @MainActor
    func clearCoverLetterConversation(coverLetter: CoverLetter) {
        ConversationContextManager.shared.clearContext(for: coverLetter.id, type: .coverLetter)
    }
    
    /// Builds a system prompt for cover letter conversations
    /// - Parameter coverLetter: The cover letter to build the prompt for
    /// - Returns: A system prompt string
    private func buildCoverLetterSystemPrompt(for coverLetter: CoverLetter) -> String {
        // Build a comprehensive system prompt for cover letter assistance
        var systemPrompt = """
        You are an expert cover letter writing assistant. Your role is to help create, revise, and improve cover letters that are personalized, compelling, and professional.
        
        Current cover letter content:
        \(coverLetter.content)
        """
        
        // Add job application context if available
        if let jobApp = coverLetter.jobApp {
            systemPrompt += """
            
            Job Application Context:
            - Position: \(jobApp.jobPosition)
            - Company: \(jobApp.companyName)
            - Job Description: \(jobApp.jobDescription)
            """
        }
        
        systemPrompt += """
        
        Please provide helpful suggestions, improvements, and revisions to make this cover letter more effective for the target position.
        """
        
        return systemPrompt
    }

    private func processResults(
        newMessage: String,
        coverLetter: CoverLetter,
        buttons: Binding<CoverLetterButtons>,
        model: String? = nil,
        isRevision: Bool // True if this is a revision of an existing letter
    ) {
        appendAssistantMessage(newMessage)
        coverLetter.content = newMessage
        coverLetter.generated = true
        coverLetter.moddedDate = Date()

        let formattedModel = formatModelName(model ?? "LLM")

        // Naming logic update:
        if isRevision {
            // For revisions, we should already have a new cover letter with
            // the appropriate option letter assigned in createDuplicate,
            // so we just need to append the revision type if it's not present
            let revisionType = coverLetter.editorPrompt.operation.rawValue

            // Extract the part after the colon (if it exists)
            let nameBase = coverLetter.editableName

            // Only append the revision type if it's not already there
            if !nameBase.contains(revisionType) {
                coverLetter.setEditableName(nameBase + ", " + revisionType)
            }
        } else {
            // This is a fresh generation of content (not a revision)
            // Either the first generation for this letter or a regeneration
            // with the Generate New button

            // Get or create an appropriate option letter
            let optionLetter: String
            if coverLetter.optionLetter.isEmpty {
                // No existing option letter, use the next available letter
                // This ensures we never reuse a letter, even if others are deleted
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
            // No "without Res BG" suffix is added when the checkbox is unchecked

            // Set the full name with the "Option X: description" format
            coverLetter.name = "Option \(optionLetter): \(nameSuffix)"
        }

        buttons.wrappedValue.runRequested = false
        coverLetter.messageHistory = genericMessages.map {
            MessageParams(
                content: $0.content,
                role: messageRoleFromChatRole($0.role)
            )
        }
    }

    private func messageRoleFromChatRole(_ chatRole: ChatMessage.ChatRole) -> MessageParams.MessageRole {
        switch chatRole {
        case .system:
            return .system
        case .user:
            return .user
        case .assistant:
            return .assistant
        }
    }

    @MainActor
    func coverChatRevise(
        res _: Resume?,
        jobAppStore: JobAppStore,
        chatProvider _: CoverChatProvider,
        buttons: Binding<CoverLetterButtons>,
        customFeedback: Binding<String>,
        isNewConversation: Bool = false
    ) {
        guard let app = jobAppStore.selectedApp else { return }
        guard let letter = app.selectedCover else { return }

        buttons.wrappedValue.runRequested = true

        if isNewConversation { // Should generally be false for revisions
            // Clear conversation context instead of using deprecated previousResponseId
            Task { @MainActor in
                letter.clearConversationContext()
            }
        }

        let systemMessage = CoverLetterPrompts.systemMessage
        genericMessages = [systemMessage] // Start with system message for this interaction

        let userMessage: String
        if letter.editorPrompt == .custom {
            userMessage = """
            Upon reading your latest draft, \(Applicant().name) has provided the following feedback:

                \(customFeedback.wrappedValue)

            Please prepare a revised draft that improves upon the original while incorporating this feedback. 
            Your response should only include the plain full text of the revised letter draft without any 
            markdown formatting or additional explanations or reasoning.

            Current draft:
            \(letter.content)
            """
        } else {
            let promptTemplate = letter.editorPrompt
            userMessage = """
            My initial draft of a cover letter to accompany my application is included below.
            \(promptTemplate.rawValue)

            Cover Letter initial draft:
            \(letter.content)
            """
        }
        appendUserMessage(userMessage)
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        Task {
            // Always use ChatCompletions API with conversation management
                let combinedMessage = "System context:\n\(systemMessage.content)\n\nUser message:\n\(userMessage)"
                
                // This is always a continuation since we're revising an existing letter
                LLMRequestService.shared.sendCoverLetterConversationRequest(
                    coverLetter: letter,
                    userMessage: combinedMessage,
                    systemPrompt: systemMessage.content,
                    isNewConversation: isNewConversation,
                    onProgress: { progress in
                        // Handle progress updates if needed
                    },
                    onComplete: { result in
                        Task { @MainActor in
                            switch result {
                            case .success(let content):
                                self.processResults(
                                    newMessage: content,
                                    coverLetter: letter,
                                    buttons: buttons,
                                    model: modelString,
                                    isRevision: true // Revisions are always true here
                                )
                            case .failure(let error):
                                buttons.wrappedValue.runRequested = false
                                self.errorMessage = "Error: \(error.localizedDescription)"
                            }
                        }
                    }
                )

        }
    }
}
