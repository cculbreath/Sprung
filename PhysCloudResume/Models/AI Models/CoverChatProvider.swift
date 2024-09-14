
import Foundation
import SwiftOpenAI

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
}
