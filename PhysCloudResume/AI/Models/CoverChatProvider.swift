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
    @MainActor
    func coverChatAction(
        res: Resume?,
        jobAppStore: JobAppStore,
        chatProvider _: CoverChatProvider,
        buttons: Binding<CoverLetterButtons>
    ) {
        guard let app = jobAppStore.selectedApp else { return }

        // Get the current cover letter
        guard let letter = app.selectedCover else { return }

        buttons.wrappedValue.runRequested = true

        // Set up the system message
        let systemMessage = CoverLetterPrompts.systemMessage

        // Add the system message
        genericMessages = [systemMessage]

        // Get the userMessage based on the mode
        let userMessage = CoverLetterPrompts.generate(
            coverLetter: letter,
            resume: res!,
            mode: letter.currentMode ?? .none
        )

        // Add the user message to the history
        appendUserMessage(userMessage)

        // Get the preferred model
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        // Send the completion request
        Task {
            do {
                let response = try await openAIClient.sendChatCompletionAsync(
                    messages: genericMessages,
                    model: modelString,
                    temperature: 1.0
                )

                // Process the results on the main thread
                await MainActor.run {
                    processResults(
                        newMessage: response.content,
                        coverLetter: letter,
                        buttons: buttons
                    )
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

    /// Process the results from the OpenAI API
    /// - Parameters:
    ///   - newMessage: The new message to process
    ///   - coverLetter: The cover letter to update
    ///   - buttons: The cover letter buttons
    private func processResults(
        newMessage: String,
        coverLetter: CoverLetter,
        buttons: Binding<CoverLetterButtons>
    ) {
        // Add the assistant message to the history
        appendAssistantMessage(newMessage)

        // Update the cover letter with the results
        coverLetter.content = newMessage
        coverLetter.generated = true
        coverLetter.moddedDate = Date()
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
    @MainActor
    func coverChatRevise(
        res _: Resume?,
        jobAppStore: JobAppStore,
        chatProvider _: CoverChatProvider,
        buttons: Binding<CoverLetterButtons>,
        customFeedback: Binding<String>
    ) {
        guard let app = jobAppStore.selectedApp else { return }

        // Get the current cover letter
        guard let letter = app.selectedCover else { return }

        buttons.wrappedValue.runRequested = true

        // Set up the system message
        let systemMessage = CoverLetterPrompts.systemMessage

        // Add the system message
        genericMessages = [systemMessage]

        // Get the userMessage based on the mode
        let userMessage: String
        if letter.editorPrompt == .custom {
            // Use the feedback provided by the user
            let feedbackPrompt = """
                Upon reading your latest draft, \(Applicant().name) has provided the following feedback:

                    \(customFeedback.wrappedValue)

                Please prepare a revised draft that improves upon the original while incorporating this feedback. 
                Your response should only include the plain full text of the revised letter draft without any 
                markdown formatting or additional explanations or reasoning.

                Current draft:
                \(letter.content)
            """
            appendUserMessage(feedbackPrompt)
        } else {
            // Use the prompt template from the editor prompts
            let promptTemplate = letter.editorPrompt ?? .zissner
            let rewritePrompt = """
                My initial draft of a cover letter to accompany my application is included below.
                \(promptTemplate.rawValue)

                Cover Letter initial draft:
                \(letter.content)
            """
            appendUserMessage(rewritePrompt)
        }

        // Get the preferred model
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        // Send the completion request
        Task {
            do {
                let response = try await openAIClient.sendChatCompletionAsync(
                    messages: genericMessages,
                    model: modelString,
                    temperature: 1.0
                )

                // Process the results on the main thread
                await MainActor.run {
                    processResults(
                        newMessage: response.content,
                        coverLetter: letter,
                        buttons: buttons
                    )
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
