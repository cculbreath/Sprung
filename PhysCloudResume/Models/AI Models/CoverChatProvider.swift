
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
    onComplete: (_ : String)->Void
  ) async throws {
    do {
      print("sending request")
      let choices = try await service.startChat(parameters: parameters).choices
      self.messages = choices.compactMap(\.message.content).map { $0.asJsonFormatted() }
      assert(messages.count == 1)
      print(self.messages.last ?? "Nothin")
      messageHist
        .append(
          .init(role: .assistant, content: .text(choices.last?.message.content ?? ""))
        )
      self.lastResponse = choices.last?.message.content ?? ""
      self.resultsAvailable = true
      self.errorMessage = choices.first?.message.refusal ?? ""
      onComplete(self.lastResponse)
    } catch APIError.responseUnsuccessful(let description, let statusCode) {
      self.errorMessage =
      "Network error with status code: \(statusCode) and description: \(description)"
    } catch {
      self.errorMessage = error.localizedDescription
    }
  }
  func processResults(newMessage: String, coverLetter: CoverLetter, isLoading: Binding<Bool>) {
    print("processResults")

      coverLetter.generated = true
    coverLetter.messageHistory.append(.init(content: newMessage, role: .assistant))
    coverLetter.content = newMessage
      print(newMessage)
      isLoading.wrappedValue = false
      self.resultsAvailable = false

  }
  func coverChatAction(
    res: Resume?,
    jobAppStore: JobAppStore,
    isLoading: Binding<Bool>,
    chatProvider: CoverChatProvider,
    buttons: Binding<CoverLetterButtons>
  ) {
    Task {
      print("chatAction")
      isLoading.wrappedValue = true
      defer {
        isLoading.wrappedValue = false
         var myButtons = buttons.wrappedValue
          myButtons.runRequested = false
      }

      guard let resume = res, let cL = jobAppStore.selectedApp?.selectedCover else {
        print("guard fail")
        return
      }


          print("generate")
          let prompt = CoverLetterPrompts.generate(
            coverLetter: cL, resume: resume, mode: cL.currentMode ?? .generate)
          print("prompt: \(prompt)")
          let myContent: ChatCompletionParameters.Message.ContentType = .text(prompt)
          self.messageHist = [
            CoverLetterPrompts.systemMessage,
            .init(role: .user, content: myContent),
          ]
          print("message count: \(self.messageHist.count)")
          cL.messageHistory.append(.init(content: prompt, role: .user))
          let parameters = ChatCompletionParameters(
            messages: self.messageHist,
            model: .gpt4o20240806,
            responseFormat: .text
          )
          try await self.startChat(
            parameters: parameters,
            onComplete: { @MainActor newMessage in
              processResults(
                newMessage: newMessage,
                coverLetter: cL,
                isLoading: isLoading
              )
            })


    }
  }
}
