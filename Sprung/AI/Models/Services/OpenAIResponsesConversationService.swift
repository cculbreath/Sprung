//
//  OpenAIResponsesConversationService.swift
//  Sprung
//
//  Bridges conversational flows to the OpenAI Responses API while keeping the
//  rest of the application backend-agnostic. Stores lightweight local state so
//  the facade can hand out UUID conversation identifiers even though the remote
//  API uses string-based IDs.
//

import Foundation
import SwiftOpenAI

struct OpenAIConversationState: Codable, Equatable {
    let remoteConversationId: String
    let lastResponseId: String
    let systemPrompt: String?
    let modelId: String
}

actor OpenAIResponsesConversationService: LLMConversationService {
    private struct ConversationState {
        let remoteConversationId: String
        var lastResponseId: String
        let systemPrompt: String?
        let modelId: String
    }

    private let service: OpenAIService
    private let defaultTemperature: Double = 1.0
    private var conversations: [UUID: ConversationState] = [:]

    init(service: OpenAIService) {
        self.service = service
    }

    func startConversation(
        systemPrompt: String?,
        userMessage: String,
        modelId: String,
        temperature: Double?
    ) async throws -> (UUID, String) {
        let response = try await sendRequest(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature,
            state: nil,
            images: []
        )

        guard let text = extractText(from: response), !text.isEmpty else {
            throw LLMError.unexpectedResponseFormat
        }

        let remoteConversationId = extractConversationId(from: response)
        let localId = UUID()
        let state = ConversationState(
            remoteConversationId: remoteConversationId,
            lastResponseId: response.id,
            systemPrompt: systemPrompt,
            modelId: modelId
        )
        conversations[localId] = state

        return (localId, text)
    }

    func continueConversation(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data],
        temperature: Double?
    ) async throws -> String {
        guard var state = conversations[conversationId] else {
            throw LLMError.clientError("Conversation not found")
        }
        guard state.modelId == modelId else {
            throw LLMError.clientError("Model mismatch for conversation")
        }

        let response = try await sendRequest(
            systemPrompt: state.systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature,
            state: state,
            images: images
        )

        guard let text = extractText(from: response), !text.isEmpty else {
            throw LLMError.unexpectedResponseFormat
        }

        state.lastResponseId = response.id
        conversations[conversationId] = state
        return text
    }

    // MARK: - Helpers

    private func sendRequest(
        systemPrompt: String?,
        userMessage: String,
        modelId: String,
        temperature: Double?,
        state: ConversationState?,
        images: [Data]
    ) async throws -> ResponseModel {
        var content: [ContentItem] = [
            .text(TextContent(text: userMessage))
        ]

        for imageData in images {
            let imageContent = ImageContent(
                detail: "auto",
                fileId: nil,
                imageUrl: dataURL(for: imageData)
            )
            content.append(.image(imageContent))
        }

        let message = InputMessage(role: "user", content: .array(content))
        let inputItems: [InputItem] = [.message(message)]

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: state.map { .id($0.remoteConversationId) },
            instructions: systemPrompt,
            previousResponseId: state?.lastResponseId,
            store: true,
            temperature: temperature ?? defaultTemperature,
            text: TextConfiguration(format: .text)
        )
        // Ensure we do not enable parallel tool calls until explicit support exists.
        parameters.parallelToolCalls = false

        return try await service.responseCreate(parameters)
    }

    private func extractConversationId(from response: ResponseModel) -> String {
        if let conversation = response.conversation {
            switch conversation {
            case .id(let identifier):
                return identifier
            case .object(let object):
                return object.id
            }
        }
        return response.id
    }

    private func extractText(from response: ResponseModel) -> String? {
        if let output = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty {
            return output
        }

        for item in response.output {
            if case let .message(message) = item {
                for content in message.content {
                    if case let .outputText(output) = content,
                       !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return output.text
                    }
                }
            }
        }

        return nil
    }

    private func dataURL(for data: Data, mimeType: String = "image/png") -> String {
        let base64 = data.base64EncodedString()
        return "data:\(mimeType);base64,\(base64)"
    }

    func persistedState(for conversationId: UUID) -> OpenAIConversationState? {
        guard let state = conversations[conversationId] else { return nil }
        return OpenAIConversationState(
            remoteConversationId: state.remoteConversationId,
            lastResponseId: state.lastResponseId,
            systemPrompt: state.systemPrompt,
            modelId: state.modelId
        )
    }

    func registerPersistedConversation(_ state: OpenAIConversationState) -> UUID {
        let localId = UUID()
        let stored = ConversationState(
            remoteConversationId: state.remoteConversationId,
            lastResponseId: state.lastResponseId,
            systemPrompt: state.systemPrompt,
            modelId: state.modelId
        )
        conversations[localId] = stored
        return localId
    }
}
