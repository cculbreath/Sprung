import Foundation

/// Adapter class that wraps the legacy OpenAIClientProtocol in the new AppLLMClientProtocol
class LegacyOpenAIAdapterWrapper: AppLLMClientProtocol {
    private let legacyClient: OpenAIClientProtocol

    init(client: OpenAIClientProtocol) {
        self.legacyClient = client
    }

    func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
        // Convert AppLLMMessages to legacy ChatMessages
        let legacyMessages = query.messages.toChatMessages()

        // Check if we need to handle structured output
        if let responseType = query.desiredResponseType {
            if responseType == RevisionsContainer.self {
                do {
                    let response = try await legacyClient.sendChatCompletionWithStructuredOutput(
                        messages: legacyMessages,
                        model: query.modelIdentifier,
                        temperature: query.temperature,
                        structuredOutputType: RevisionsContainer.self
                    )

                    // Convert to JSON data
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(response)
                    return .structured(data)
                } catch {
                    // If structured output fails, try regular completion
                    Logger.error("❌ Structured output failed: \(error.localizedDescription). Falling back to regular completion.")

                    let response = try await legacyClient.sendChatCompletionAsync(
                        messages: legacyMessages,
                        model: query.modelIdentifier,
                        responseFormat: .jsonObject,
                        temperature: query.temperature
                    )

                    if let data = response.content.data(using: .utf8) {
                        return .structured(data)
                    } else {
                        return .text(response.content)
                    }
                }
            } else if responseType == BestCoverLetterResponse.self {
                do {
                    let response = try await legacyClient.sendChatCompletionWithStructuredOutput(
                        messages: legacyMessages,
                        model: query.modelIdentifier,
                        temperature: query.temperature,
                        structuredOutputType: BestCoverLetterResponse.self
                    )

                    // Convert to JSON data
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(response)
                    return .structured(data)
                } catch {
                    // If structured output fails, try regular completion
                    Logger.error("❌ Structured output failed: \(error.localizedDescription). Falling back to regular completion.")

                    let response = try await legacyClient.sendChatCompletionAsync(
                        messages: legacyMessages,
                        model: query.modelIdentifier,
                        responseFormat: .jsonObject,
                        temperature: query.temperature
                    )

                    if let data = response.content.data(using: .utf8) {
                        return .structured(data)
                    } else {
                        return .text(response.content)
                    }
                }
            } else {
                // For other structured output types, use regular completion
                // and convert the result to structured data
                let response = try await legacyClient.sendChatCompletionAsync(
                    messages: legacyMessages,
                    model: query.modelIdentifier,
                    responseFormat: .jsonObject,
                    temperature: query.temperature
                )

                let content = response.content
                if let data = content.data(using: .utf8) {
                    return .structured(data)
                } else {
                    throw AppLLMError.unexpectedResponseFormat
                }
            }
        } else {
            // For regular text output, use regular completion
            let response = try await legacyClient.sendChatCompletionAsync(
                messages: legacyMessages,
                model: query.modelIdentifier,
                responseFormat: nil,
                temperature: query.temperature
            )

            return .text(response.content)
        }
    }
}