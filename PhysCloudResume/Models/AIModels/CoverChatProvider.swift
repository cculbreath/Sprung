import Foundation
import SwiftOpenAI
import SwiftUI

@Observable
final class CoverChatProvider {
    private let service: OpenAIService
    var message: String = ""
    var messages: [String] = []
    var messageHist: [ChatCompletionParameters.Message] = []
    var errorMessage: String = ""
    var resultsAvailable: Bool = false
    var lastResponse: String = ""

    // MARK: - Initializer

    init(service: OpenAIService) {
        self.service = service
    }

    func startChat(
        parameters: ChatCompletionParameters,
        onComplete: (_: String) -> Void
    ) async throws {
        do {
            print("sending request")
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
            print(messages.last ?? "Nothin")
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
    }

    func processResults(
        newMessage: String,
        coverLetter: CoverLetter,
        buttons: Binding<CoverLetterButtons>
    ) {
        print("processResults")

        coverLetter.generated = true
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
            let prompt = CoverLetterPrompts.generate(
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
            let prompt = CoverLetterPrompts.generate(
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
