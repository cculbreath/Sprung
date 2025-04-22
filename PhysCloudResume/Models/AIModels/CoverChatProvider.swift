import Foundation
import SwiftUI
import SwiftOpenAI // Will be removed later in the migration

@Observable
final class CoverChatProvider {
    // The OpenAI client that will be used for API calls
    private let openAIClient: OpenAIClientProtocol
    // For backward compatibility during migration
    private let service: OpenAIService?
    
    var message: String = ""
    var messages: [String] = []
    // For backward compatibility - will be replaced with our new message type
    var messageHist: [ChatCompletionParameters.Message] = []
    // Stores generic chat messages for the new abstraction layer
    var genericMessages: [ChatMessage] = []
    var errorMessage: String = ""
    var resultsAvailable: Bool = false
    var lastResponse: String = ""

    // MARK: - Initializers
    
    /// Initialize with the new abstraction layer client
    /// - Parameter client: An OpenAI client conforming to OpenAIClientProtocol
    init(client: OpenAIClientProtocol) {
        self.openAIClient = client
        self.service = nil
    }
    
    /// Initialize with the legacy SwiftOpenAI service (for backward compatibility)
    /// - Parameter service: The OpenAIService from SwiftOpenAI
    init(service: OpenAIService) {
        self.service = service
        self.openAIClient = SwiftOpenAIClient(apiKey: service.apiKey)
    }

    // Legacy method - uses SwiftOpenAI directly
    func startChat(
        parameters: ChatCompletionParameters,
        onComplete: @escaping (_: String) -> Void
    ) async throws {
        // If we have a service, use it directly for backward compatibility
        if let service = service {
            do {
                print("sending request using legacy service")
                let result = try await service.startChat(parameters: parameters)
                let choices = result.choices ?? []

                // Process messages using proper optional handling
                messages = choices.compactMap { choice in
                    if let message = choice.message, let content = message.content {
                        return content.asJsonFormatted()
                    }
                    return nil
                }
                assert(messages.count == 1)
                print(messages.last ?? "Nothing")
                // Get the last response content safely
                let lastContent: String = {
                    if let lastChoice = choices.last,
                       let message = lastChoice.message,
                       let content = message.content
                    {
                        return content
                    }
                    return ""
                }()

                messageHist.append(
                    .init(
                        role: .assistant,
                        content: .text(lastContent)
                    )
                )

                lastResponse = lastContent
                resultsAvailable = true

                // Check for refusal safely
                errorMessage = {
                    if let firstChoice = choices.first,
                       let message = firstChoice.message,
                       let refusal = message.refusal
                    {
                        return refusal
                    }
                    return ""
                }()
                onComplete(lastResponse)
            } catch let APIError.responseUnsuccessful(description, statusCode) {
                self.errorMessage =
                    "Network error with status code: \(statusCode) and description: \(description)"
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            // Use the abstraction layer if no service is available
            await withCheckedContinuation { continuation in
                startChatWithGenericClient(parameters: parameters) { result in
                    onComplete(result)
                    continuation.resume()
                }
            }
        }
    }
    
    /// New method using the abstraction layer
    func startChatWithGenericClient(
        parameters: ChatCompletionParameters,
        onComplete: @escaping (_: String) -> Void
    ) {
        print("sending request using abstraction layer")
        
        // Convert SwiftOpenAI messages to generic format
        let genericMessages = parameters.messages.map { message in
            let role = ChatMessage.ChatRole(rawValue: message.role.rawValue) ?? .user
            let content: String
            
            switch message.content {
            case let .text(text):
                content = text
            case let .contentArray(array):
                // Simplified handling of content array - this might need enhancement
                // based on actual usage in your application
                content = array.compactMap { item in
                    switch item {
                    case let .text(text):
                        return text
                    default:
                        return nil
                    }
                }.joined(separator: "\n")
            }
            
            return ChatMessage(role: role, content: content)
        }
        
        // Store for future reference
        self.genericMessages = genericMessages
        
        // Get model as string
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        
        // Send the request using our abstraction layer
        openAIClient.sendChatCompletion(
            messages: genericMessages,
            model: modelString,
            temperature: parameters.temperature ?? 0.7
        ) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                let content = response.content
                
                // Update state to match legacy behavior
                self.messages = [content.asJsonFormatted()]
                self.lastResponse = content
                self.resultsAvailable = true
                
                // Also update legacy message history for compatibility
                self.messageHist.append(
                    .init(
                        role: .assistant,
                        content: .text(content)
                    )
                )
                
                // Add to generic message history
                self.genericMessages.append(ChatMessage(role: .assistant, content: content))
                
                onComplete(content)
                
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func processResults(
        newMessage: String,
        coverLetter: CoverLetter,
        buttons: Binding<CoverLetterButtons>
    ) {
        print("processResults")

        coverLetter.generated = true
        // Once generated, allow editing
        buttons.wrappedValue.canEdit = true
        // Update modification date
        coverLetter.moddedDate = Date()
        // Determine the human-readable operation name
        let opName = coverLetter.editorPrompt.operation.rawValue
        if coverLetter.currentMode == .generate {
            coverLetter.name = "Generated at \(coverLetter.modDate)"
        } else {
            let oldName = coverLetter.name
            if oldName.isEmpty {
                coverLetter.name = "Generated at \(coverLetter.modDate)"
            } else if let start = oldName.firstIndex(of: "("), let end = oldName.lastIndex(of: ")"), start < end {
                let base = oldName[..<start].trimmingCharacters(in: .whitespaces)
                let ops = oldName[oldName.index(after: start) ..< end]
                var items = ops.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                items.append(opName)
                coverLetter.name = "\(base) (\(items.joined(separator: ", ")) )"
            } else {
                coverLetter.name = "\(oldName) (\(opName))"
            }
        }
        // Append new content to message history and update content
        coverLetter.messageHistory.append(.init(content: newMessage, role: .assistant))
        coverLetter.content = newMessage
        print(newMessage)
        buttons.wrappedValue.runRequested = false
        resultsAvailable = false
    }

    @MainActor
    func coverChatRevise(
        res: Resume?,
        jobAppStore: JobAppStore,
        chatProvider _: CoverChatProvider,
        buttons: Binding<CoverLetterButtons>,
        customFeedback: Binding<String>
    ) {
        Task { @MainActor in
            print("reviseAction")
            buttons.wrappedValue.runRequested = true
            defer {
                customFeedback.wrappedValue = ""
            }

            guard let resume = res, let cL = jobAppStore.selectedApp?.selectedCover
            else {
                print("guard fail")
                return
            }

            print("revise")
            // Access MainActor-isolated method
            let prompt = await CoverLetterPrompts.generate(
                coverLetter: cL, resume: resume, mode: cL.currentMode ?? .revise,
                customFeedbackString: customFeedback.wrappedValue
            )
            let myContent: ChatCompletionParameters.Message.ContentType = .text(
                prompt)
            cL.messageHistory.append(.init(content: prompt, role: .user))
            self.messageHist = cL.messageHistory.map { messageParam in
                ChatCompletionParameters.Message(
                    role: ChatCompletionParameters.Message.Role(
                        rawValue: messageParam.role.rawValue) ?? .user, // Assuming a fallback to `.user`
                    content: .text(messageParam.content), // Assuming content is text-based
                    refusal: nil, // Assuming no refusal messages
                    name: nil, // Assuming no specific name
                    audio: nil, // Assuming no audio data
                    functionCall: nil, // Deprecated; set to nil
                    toolCalls: nil, // Assuming no tool calls
                    toolCallID: nil // Assuming no tool call ID
                )
            }

            print("message count: \(self.messageHist.count)")
            let model = OpenAIModelFetcher.getPreferredModel()
            print("Using OpenAI model: \(model)")
            let parameters = ChatCompletionParameters(
                messages: self.messageHist,
                model: model,
                responseFormat: .text
            )
            try await self.startChat(
                parameters: parameters,
                onComplete: { @MainActor newMessage in
                    processResults(
                        newMessage: newMessage,
                        coverLetter: cL,
                        buttons: buttons
                    )
                }
            )
        }
    }

    @MainActor
    func coverChatAction(
        res: Resume?,
        jobAppStore: JobAppStore,
        chatProvider _: CoverChatProvider,
        buttons: Binding<CoverLetterButtons>
    ) {
        Task { @MainActor in
            print("chatAction")
            buttons.wrappedValue.runRequested = true

            guard let resume = res, let cL = jobAppStore.selectedApp?.selectedCover
            else {
                print("guard fail")
                return
            }

            print("generate")
            // Access MainActor-isolated method
            let prompt = await CoverLetterPrompts.generate(
                coverLetter: cL, resume: resume, mode: cL.currentMode ?? .generate
            )
            print("prompt: \(prompt)")
            let myContent: ChatCompletionParameters.Message.ContentType = .text(
                prompt)
            self.messageHist = [
                CoverLetterPrompts.systemMessage,
                .init(role: .user, content: myContent),
            ]
            cL.messageHistory = [
                .init(
                    content: {
                        switch CoverLetterPrompts.systemMessage.content {
                        case let .text(text): return text
                        case .contentArray: return "" // Handle as needed
                        }
                    }(), role: .system
                ),
                .init(content: prompt, role: .user),
            ]
            print("handler message count: \(self.messageHist.count)")
            print("CL message count:  \(cL.messageHistory.count)")
            let model = OpenAIModelFetcher.getPreferredModel()
            print("Using OpenAI model: \(model)")
            let parameters = ChatCompletionParameters(
                messages: self.messageHist,
                model: model,
                responseFormat: .text
            )
            try await self.startChat(
                parameters: parameters,
                onComplete: { @MainActor newMessage in
                    processResults(
                        newMessage: newMessage,
                        coverLetter: cL,
                        buttons: buttons
                    )
                }
            )
        }
    }
}
