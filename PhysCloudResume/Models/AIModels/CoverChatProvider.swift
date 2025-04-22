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
    func coverChatAction(
        res: Resume?,
        jobAppStore: JobAppStore,
        chatProvider: CoverChatProvider,
        buttons: Binding<CoverLetterButtons>
    ) {
        guard let app = jobAppStore.selectedApp else { return }
        
        // Get the current cover letter
        let letter = app.selectedCover!
        
        buttons.wrappedValue.runRequested = true
        print("Cover letter mode: \(String(describing: letter.currentMode))")
        
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
                    temperature: 0.7
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
                    print("Chat completion error: \(error.localizedDescription)")
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
}