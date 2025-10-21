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

actor OpenAIResponsesConversationService: LLMStreamingConversationService {
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
        let parameters = makeParameters(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature,
            state: nil,
            images: [],
            streaming: false
        )
        let response = try await service.responseCreate(parameters)

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

        let parameters = makeParameters(
            systemPrompt: state.systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature,
            state: state,
            images: images,
            streaming: false
        )
        let response = try await service.responseCreate(parameters)

        guard let text = extractText(from: response), !text.isEmpty else {
            throw LLMError.unexpectedResponseFormat
        }

        state.lastResponseId = response.id
        conversations[conversationId] = state
        return text
    }

    func startConversationStreaming(
        systemPrompt: String?,
        userMessage: String,
        modelId: String,
        temperature: Double?,
        images: [Data]
    ) async throws -> (UUID, AsyncThrowingStream<LLMStreamChunkDTO, Error>) {
        let parameters = makeParameters(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature,
            state: nil,
            images: images,
            streaming: true
        )

        let localConversationId = UUID()
        let stream = try await streamConversation(
            parameters: parameters,
            localConversationId: localConversationId,
            existingState: nil,
            systemPrompt: systemPrompt,
            modelId: modelId
        )

        return (localConversationId, stream)
    }

    func continueConversationStreaming(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data],
        temperature: Double?
    ) async throws -> AsyncThrowingStream<LLMStreamChunkDTO, Error> {
        guard let state = conversations[conversationId] else {
            throw LLMError.clientError("Conversation not found")
        }
        guard state.modelId == modelId else {
            throw LLMError.clientError("Model mismatch for conversation")
        }

        let parameters = makeParameters(
            systemPrompt: state.systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature,
            state: state,
            images: images,
            streaming: true
        )

        return try await streamConversation(
            parameters: parameters,
            localConversationId: conversationId,
            existingState: state,
            systemPrompt: state.systemPrompt,
            modelId: modelId
        )
    }

    // MARK: - Helpers

    private func makeParameters(
        systemPrompt: String?,
        userMessage: String,
        modelId: String,
        temperature: Double?,
        state: ConversationState?,
        images: [Data],
        streaming: Bool
    ) -> ModelResponseParameter {
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
            conversation: nil,
            instructions: systemPrompt,
            previousResponseId: nil,
            store: true,
            temperature: temperature ?? defaultTemperature,
            text: TextConfiguration(format: .text)
        )
        if let state {
            parameters.conversation = .id(state.remoteConversationId)
        }
        // Ensure we do not enable parallel tool calls until explicit support exists.
        parameters.parallelToolCalls = false
        parameters.stream = streaming
        return parameters
    }

    private func streamConversation(
        parameters: ModelResponseParameter,
        localConversationId: UUID,
        existingState: ConversationState?,
        systemPrompt: String?,
        modelId: String
    ) async throws -> AsyncThrowingStream<LLMStreamChunkDTO, Error> {
        let sdkStream = try await service.responseCreateStream(parameters)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var accumulatedReasoning = ""
                var remoteConversationId = existingState?.remoteConversationId
                var lastResponseId = existingState?.lastResponseId
                var hasEmittedFinish = false

                do {
                    for try await event in sdkStream {
                        try Task.checkCancellation()
                        switch event {
                        case .responseCreated(let created):
                            remoteConversationId = self.extractConversationId(from: created.response)
                            lastResponseId = created.response.id
                            await self.storeConversationStateIfNeeded(
                                localConversationId: localConversationId,
                                remoteConversationId: remoteConversationId,
                                lastResponseId: lastResponseId,
                                systemPrompt: systemPrompt,
                                modelId: modelId
                            )
                        case .responseInProgress(let inProgress):
                            remoteConversationId = self.extractConversationId(from: inProgress.response)
                            lastResponseId = inProgress.response.id
                            await self.storeConversationStateIfNeeded(
                                localConversationId: localConversationId,
                                remoteConversationId: remoteConversationId,
                                lastResponseId: lastResponseId,
                                systemPrompt: systemPrompt,
                                modelId: modelId
                            )
                        case .outputTextDelta(let delta):
                            continuation.yield(
                                LLMStreamChunkDTO(
                                    content: delta.delta,
                                    reasoning: nil,
                                    isFinished: false
                                )
                            )
                        case .reasoningTextDelta(let delta):
                            accumulatedReasoning += delta.delta
                            continuation.yield(
                                LLMStreamChunkDTO(
                                    content: nil,
                                    reasoning: delta.delta,
                                    isFinished: false
                                )
                            )
                        case .reasoningSummaryTextDelta(let delta):
                            accumulatedReasoning += delta.delta
                            continuation.yield(
                                LLMStreamChunkDTO(
                                    content: nil,
                                    reasoning: delta.delta,
                                    isFinished: false
                                )
                            )
                        case .customToolCallInputDelta(let delta):
                            let payload = delta.delta.trimmingCharacters(in: .whitespacesAndNewlines)
                            continuation.yield(
                                LLMStreamChunkDTO(
                                    content: nil,
                                    reasoning: nil,
                                    event: .tool(
                                        LLMToolStreamEvent(
                                            callId: delta.itemId,
                                            status: "Preparing tool input…",
                                            payload: payload,
                                            appendsPayload: true,
                                            isComplete: false
                                        )
                                    ),
                                    isFinished: false
                                )
                            )
                        case .customToolCallInputDone(let done):
                            let payload = done.input.trimmingCharacters(in: .whitespacesAndNewlines)
                            continuation.yield(
                                LLMStreamChunkDTO(
                                    content: nil,
                                    reasoning: nil,
                                    event: .tool(
                                        LLMToolStreamEvent(
                                            callId: done.itemId,
                                            status: "Tool input submitted.",
                                            payload: payload.isEmpty ? nil : payload,
                                            appendsPayload: false,
                                            isComplete: false
                                        )
                                    ),
                                    isFinished: false
                                )
                            )
                        case .mcpCallInProgress(let progress):
                            continuation.yield(
                                LLMStreamChunkDTO(
                                    content: nil,
                                    reasoning: nil,
                                    event: .tool(
                                        LLMToolStreamEvent(
                                            callId: progress.itemId,
                                            status: "Tool execution in progress…",
                                            payload: nil,
                                            appendsPayload: false,
                                            isComplete: false
                                        )
                                    ),
                                    isFinished: false
                                )
                            )
                        case .mcpCallCompleted(let completed):
                            continuation.yield(
                                LLMStreamChunkDTO(
                                    content: nil,
                                    reasoning: nil,
                                    event: .tool(
                                        LLMToolStreamEvent(
                                            callId: completed.itemId,
                                            status: "Tool execution completed.",
                                            payload: nil,
                                            appendsPayload: false,
                                            isComplete: true
                                        )
                                    ),
                                    isFinished: false
                                )
                            )
                        case .mcpCallFailed(let failed):
                            continuation.yield(
                                LLMStreamChunkDTO(
                                    content: nil,
                                    reasoning: nil,
                                    event: .tool(
                                        LLMToolStreamEvent(
                                            callId: failed.itemId,
                                            status: "Tool execution failed.",
                                            payload: nil,
                                            appendsPayload: false,
                                            isComplete: true
                                        )
                                    ),
                                    isFinished: false
                                )
                            )
                        case .responseCompleted(let completed):
                            remoteConversationId = self.extractConversationId(from: completed.response)
                            lastResponseId = completed.response.id
                            await self.updateConversationState(
                                localConversationId: localConversationId,
                                remoteConversationId: remoteConversationId,
                                lastResponseId: lastResponseId,
                                systemPrompt: systemPrompt,
                                modelId: modelId
                            )
                            if !hasEmittedFinish {
                                hasEmittedFinish = true
                                continuation.yield(
                                    LLMStreamChunkDTO(
                                        content: nil,
                                        reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
                                        isFinished: true
                                    )
                                )
                            }
                        case .responseFailed(let failed):
                            throw LLMError.clientError(failed.response.error?.message ?? "OpenAI streaming request failed")
                        case .responseIncomplete(let incomplete):
                            remoteConversationId = self.extractConversationId(from: incomplete.response)
                            lastResponseId = incomplete.response.id
                            await self.updateConversationState(
                                localConversationId: localConversationId,
                                remoteConversationId: remoteConversationId,
                                lastResponseId: lastResponseId,
                                systemPrompt: systemPrompt,
                                modelId: modelId
                            )
                            if !hasEmittedFinish {
                                hasEmittedFinish = true
                                continuation.yield(
                                    LLMStreamChunkDTO(
                                        content: nil,
                                        reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
                                        isFinished: true
                                    )
                                )
                            }
                        case .error(let errorEvent):
                            throw LLMError.clientError(errorEvent.message)
                        default:
                            continue
                        }
                    }
                    if !hasEmittedFinish {
                        continuation.yield(
                            LLMStreamChunkDTO(
                                content: nil,
                                reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
                                isFinished: true
                            )
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func storeConversationStateIfNeeded(
        localConversationId: UUID,
        remoteConversationId: String?,
        lastResponseId: String?,
        systemPrompt: String?,
        modelId: String
    ) async {
        guard let remoteConversationId, let lastResponseId else { return }
        if conversations[localConversationId] == nil {
            conversations[localConversationId] = ConversationState(
                remoteConversationId: remoteConversationId,
                lastResponseId: lastResponseId,
                systemPrompt: systemPrompt,
                modelId: modelId
            )
        }
    }

    private func updateConversationState(
        localConversationId: UUID,
        remoteConversationId: String?,
        lastResponseId: String?,
        systemPrompt: String?,
        modelId: String
    ) async {
        guard let remoteConversationId, let lastResponseId else { return }
        if var existing = conversations[localConversationId] {
            existing.lastResponseId = lastResponseId
            conversations[localConversationId] = existing
        } else {
            conversations[localConversationId] = ConversationState(
                remoteConversationId: remoteConversationId,
                lastResponseId: lastResponseId,
                systemPrompt: systemPrompt,
                modelId: modelId
            )
        }
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
