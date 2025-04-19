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
            let choices = try await service.startChat(parameters: parameters).choices
            messages = choices.compactMap(\.message.content).map {
                $0.asJsonFormatted()
            }
            assert(messages.count == 1)
            print(messages.last ?? "Nothin")
            messageHist
                .append(
                    .init(
                        role: .assistant,
                        content: .text(choices.last?.message.content ?? "")
                    )
                )
            lastResponse = choices.last?.message.content ?? ""
            resultsAvailable = true
            errorMessage = choices.first?.message.refusal ?? ""
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
        coverLetter.messageHistory.append(
            .init(content: newMessage, role: .assistant))
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
