import Foundation
import SwiftOpenAI // Will be removed later in the migration
import SwiftUI

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
        openAIClient = client
        service = nil
    }

    /// Initialize with the legacy SwiftOpenAI service (for backward compatibility)
    /// - Parameter service: The OpenAIService from SwiftOpenAI
    init(service: OpenAIService) {
        self.service = service
        // Get API key from UserDefaults since OpenAIService doesn't expose it
        let apiKey = UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
        openAIClient = SwiftOpenAIClient(apiKey: apiKey)
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
            // Map the roles directly - we know all the possible values from SwiftOpenAI
            let role: ChatMessage.ChatRole
            switch message.role {
            case .user:
                role = .user
            case .assistant:
                role = .assistant
            case .system:
                role = .system
            default:
                role = .user // Default fallback
            }
            
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
            case let .success(response):
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

            case let .failure(error):
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

            // Add message to cover letter history
            cL.messageHistory.append(.init(content: prompt, role: .user))

            // Add to generic message history
            self.genericMessages.append(ChatMessage(role: .user, content: prompt))

            // Update legacy message history for backwards compatibility
            let myContent: ChatCompletionParameters.Message.ContentType = .text(prompt)
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

            // We'll use both the string and Model versions during transition
            let modelString = OpenAIModelFetcher.getPreferredModelString()
            let swiftOpenAIModel = OpenAIModelFetcher.getPreferredModel()
            print("Using OpenAI model: \(modelString)")

            // Legacy parameters for backward compatibility
            let parameters = ChatCompletionParameters(
                messages: self.messageHist,
                model: swiftOpenAIModel,
                responseFormat: .text
            )

            try await self.startChat(
                parameters: parameters,
                onComplete: { @MainActor [self] newMessage in
                    self.processResults(
                        newMessage: newMessage,
                        coverLetter: cL,
                        buttons: buttons
                    )
                }
            )
        }
    }

    /// New method that uses the abstraction layer directly
    @MainActor
    func coverChatActionWithGenericClient(
        res: Resume?,
        jobAppStore: JobAppStore,
        buttons: Binding<CoverLetterButtons>
    ) async {
        print("chatAction with generic client")
        buttons.wrappedValue.runRequested = true

        guard let resume = res, let cL = jobAppStore.selectedApp?.selectedCover
        else {
            print("guard fail")
            return
        }

        print("generate with abstraction layer")
        // Access MainActor-isolated method
        let prompt = await CoverLetterPrompts.generate(
            coverLetter: cL, resume: resume, mode: cL.currentMode ?? .generate
        )

        // Extract system message content
        let systemContent: String = {
            switch CoverLetterPrompts.systemMessage.content {
            case let .text(text): return text
            case .contentArray: return "" // Handle as needed
            }
        }()

        // Store message history in generic format
        let messages = [
            ChatMessage(role: .system, content: systemContent),
            ChatMessage(role: .user, content: prompt),
        ]

        // Update state
        genericMessages = messages

        // Add to cover letter's history
        cL.messageHistory = [
            .init(content: systemContent, role: .system),
            .init(content: prompt, role: .user),
        ]

        // Get model as string
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        print("Using OpenAI model: \(modelString)")

        do {
            // Use our abstraction layer directly with async/await
            let response = try await openAIClient.sendChatCompletionAsync(
                messages: messages,
                model: modelString,
                temperature: 0.7
            )

            // Process the results
            self.processResults(
                newMessage: response.content,
                coverLetter: cL,
                buttons: buttons
            )
        } catch {
            // Handle any errors
            errorMessage = error.localizedDescription
            buttons.wrappedValue.runRequested = false
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

            // For backward compatibility, store in legacy format
            let myContent: ChatCompletionParameters.Message.ContentType = .text(prompt)

            // Extract system message content for generic storage
            let systemContent: String = {
                switch CoverLetterPrompts.systemMessage.content {
                case let .text(text): return text
                case .contentArray: return "" // Handle as needed
                }
            }()

            // Store message history in both formats for transition period

            // 1. Legacy format for SwiftOpenAI
            self.messageHist = [
                CoverLetterPrompts.systemMessage,
                .init(role: .user, content: myContent),
            ]

            // 2. Generic format for our abstraction layer
            self.genericMessages = [
                ChatMessage(role: .system, content: systemContent),
                ChatMessage(role: .user, content: prompt),
            ]

            // 3. Cover letter's own history
            cL.messageHistory = [
                .init(content: systemContent, role: .system),
                .init(content: prompt, role: .user),
            ]

            print("handler message count: \(self.messageHist.count)")
            print("Generic message count: \(self.genericMessages.count)")
            print("CL message count: \(cL.messageHistory.count)")

            // Get model in both formats
            let modelString = OpenAIModelFetcher.getPreferredModelString()
            let swiftOpenAIModel = OpenAIModelFetcher.getPreferredModel()
            print("Using OpenAI model: \(modelString)")

            // Use legacy format parameters for now
            let parameters = ChatCompletionParameters(
                messages: self.messageHist,
                model: swiftOpenAIModel,
                responseFormat: .text
            )

            try await self.startChat(
                parameters: parameters,
                onComplete: { @MainActor [self] newMessage in
                    self.processResults(
                        newMessage: newMessage,
                        coverLetter: cL,
                        buttons: buttons
                    )
                }
            )
        }
    }
}
