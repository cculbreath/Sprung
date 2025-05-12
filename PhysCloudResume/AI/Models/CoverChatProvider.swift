//
//  CoverChatProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/14/24.
//

import Foundation
import SwiftUI

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
        // This handles cases like "gpt-4o-latest" -> "Gpt" or "gemini-pro" -> "Gemini"
        return modelName.split(separator: "-").first?.capitalized ?? modelName.capitalized
    }

    /// Add a user message to the chat history
    /// - Parameter text: The message text
    func appendUserMessage(_ text: String) {
        let message = ChatMessage(role: .user, content: text)
        genericMessages.append(message)
    }

    /// Add a system message to the chat history
    /// - Parameter text: The message text
    func appendSystemMessage(_ text: String) {
        let message = ChatMessage(role: .system, content: text)
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

        // Get the current cover letter
        guard let letter = app.selectedCover else { return }

        buttons.wrappedValue.runRequested = true

        // If this is a new conversation from toolbar button, clear the response ID
        if isNewConversation {
            letter.previousResponseId = nil
        }

        // Set up the system message
        let systemMessage = CoverLetterPrompts.systemMessage

        // Add the system message
        genericMessages = [systemMessage]

        // Get the userMessage based on the mode
        let userMessage = CoverLetterPrompts.generate(
            coverLetter: letter,
            resume: res!, // res is guaranteed to exist if we reach here due to app logic
            mode: letter.currentMode ?? .none // Use .none as a fallback if currentMode is nil
        )

        // Add the user message to the history
        appendUserMessage(userMessage)

        // Get the preferred model
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        // Send the completion request
        Task {
            do {
                // Use the Responses API if available
                if isResponsesAPIEnabled() {
                    // Combine messages for the Responses API
                    let combinedMessage = "System context:\n\(systemMessage.content)\n\nUser message:\n\(userMessage)"

                    let response = try await openAIClient.sendResponseRequestAsync(
                        message: combinedMessage,
                        model: modelString,
                        temperature: 1.0, // Standard temperature
                        previousResponseId: letter.previousResponseId, // Pass previous ID for context
                        schema: nil // No specific schema for cover letter generation
                    )

                    // Save the response ID for future continuations
                    letter.previousResponseId = response.id

                    // Process the results on the main thread
                    await MainActor.run {
                        processResults(
                            newMessage: response.content,
                            coverLetter: letter,
                            buttons: buttons,
                            model: modelString,
                            isRevision: !isNewConversation // It's a revision if not a new conversation
                        )
                    }
                } else {
                    // Fallback to the original ChatCompletion API
                    let response = try await openAIClient.sendChatCompletionAsync(
                        messages: genericMessages,
                        model: modelString,
                        temperature: 1.0 // Standard temperature
                    )

                    // Process the results on the main thread
                    await MainActor.run {
                        processResults(
                            newMessage: response.content,
                            coverLetter: letter,
                            buttons: buttons,
                            model: modelString,
                            isRevision: !isNewConversation // It's a revision if not a new conversation
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    // Handle any errors
                    buttons.wrappedValue.runRequested = false
                    errorMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Check if the Responses API should be used
    /// - Returns: True if the Responses API should be used
    private func isResponsesAPIEnabled() -> Bool {
        // We can add a feature flag here in the future
        // For now, always return true to use the new API
        return true
    }

    /// Process the results from the OpenAI API
    /// - Parameters:
    ///   - newMessage: The new message to process
    ///   - coverLetter: The cover letter to update
    ///   - buttons: The cover letter buttons
    ///   - model: The model used for generation (optional)
    ///   - isRevision: A boolean indicating if this is a revision operation
    private func processResults(
        newMessage: String,
        coverLetter: CoverLetter,
        buttons: Binding<CoverLetterButtons>,
        model: String? = nil,
        isRevision: Bool
    ) {
        // Add the assistant message to the history
        appendAssistantMessage(newMessage)

        // Update the cover letter with the results
        coverLetter.content = newMessage
        coverLetter.generated = true // Mark as generated
        coverLetter.moddedDate = Date() // Update modification date

        // Format the model name (simplified version without date)
        let formattedModel = formatModelName(model ?? "LLM")

        // Update letter name based on whether it's a new generation or a revision
        if isRevision {
            // Append revision type to the existing name
            let revisionType = coverLetter.editorPrompt.operation.rawValue // e.g., "Mimic", "Zissner"
            if !coverLetter.name.contains(revisionType) { // Avoid duplicate revision tags
                coverLetter.name = "\(coverLetter.name), \(revisionType)"
            }
        } else {
            // First generation - set the model name
            // Append "Res Background" if includeResumeRefs is true
            var baseName = formattedModel
            if coverLetter.includeResumeRefs {
                baseName += ", Res Background"
            }
            coverLetter.name = baseName
        }

        buttons.wrappedValue.runRequested = false

        // Save the message history for potential revisions later
        coverLetter.messageHistory = genericMessages.map {
            MessageParams(
                content: $0.content,
                role: messageRoleFromChatRole($0.role)
            )
        }
    }

    /// Converts a ChatRole to a MessageRole
    /// - Parameter chatRole: The ChatRole to convert
    /// - Returns: The corresponding MessageRole
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

    /// Calls the OpenAI API to revise a cover letter
    /// - Parameters:
    ///   - res: The resume to use
    ///   - jobAppStore: The job app store
    ///   - chatProvider: The chat provider
    ///   - buttons: The cover letter buttons
    ///   - customFeedback: Custom feedback for revision
    ///   - isNewConversation: Whether this is a new conversation (default false for revisions)
    @MainActor
    func coverChatRevise(
        res _: Resume?, // res is optional as it might not always be needed for revisions
        jobAppStore: JobAppStore,
        chatProvider _: CoverChatProvider, // chatProvider is self
        buttons: Binding<CoverLetterButtons>,
        customFeedback: Binding<String>, // For custom feedback mode
        isNewConversation: Bool = false // Revisions are typically not new conversations
    ) {
        guard let app = jobAppStore.selectedApp else { return }

        // Get the current cover letter
        guard let letter = app.selectedCover else { return }

        buttons.wrappedValue.runRequested = true

        // If this is a new conversation, clear the response ID
        if isNewConversation {
            letter.previousResponseId = nil
        }

        // Set up the system message
        let systemMessage = CoverLetterPrompts.systemMessage

        // Add the system message
        genericMessages = [systemMessage]

        // Get the userMessage based on the mode
        let userMessage: String
        if letter.editorPrompt == .custom {
            // Use the feedback provided by the user
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
            // Use the prompt template from the editor prompts
            let promptTemplate = letter.editorPrompt
            userMessage = """
            My initial draft of a cover letter to accompany my application is included below.
            \(promptTemplate.rawValue)

            Cover Letter initial draft:
            \(letter.content)
            """
        }

        // For legacy API, add the user message to the message history
        appendUserMessage(userMessage)

        // Get the preferred model
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        // Send the completion request
        Task {
            do {
                // Use the Responses API if available
                if isResponsesAPIEnabled() {
                    // Combine messages for the Responses API
                    let combinedMessage = "System context:\n\(systemMessage.content)\n\nUser message:\n\(userMessage)"

                    let response = try await openAIClient.sendResponseRequestAsync(
                        message: combinedMessage,
                        model: modelString,
                        temperature: 1.0, // Standard temperature
                        previousResponseId: letter.previousResponseId, // Pass previous ID for context
                        schema: nil // No specific schema for cover letter revision
                    )

                    // Save the response ID for future continuations
                    letter.previousResponseId = response.id

                    // Process the results on the main thread
                    await MainActor.run {
                        processResults(
                            newMessage: response.content,
                            coverLetter: letter,
                            buttons: buttons,
                            model: modelString,
                            isRevision: true // Revisions are always true here
                        )
                    }
                } else {
                    // Fallback to the original ChatCompletion API
                    let response = try await openAIClient.sendChatCompletionAsync(
                        messages: genericMessages,
                        model: modelString,
                        temperature: 1.0 // Standard temperature
                    )

                    // Process the results on the main thread
                    await MainActor.run {
                        processResults(
                            newMessage: response.content,
                            coverLetter: letter,
                            buttons: buttons,
                            model: modelString,
                            isRevision: true // Revisions are always true here
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    // Handle any errors
                    buttons.wrappedValue.runRequested = false
                    errorMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
