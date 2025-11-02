//
//  LLMService.swift
//  Sprung
//
//  Unified service that coordinates LLM operations while isolating vendor SDK
//  types behind adapter helpers.
//

import Foundation
import Observation
import SwiftData

// MARK: - LLM Error Types

enum LLMError: LocalizedError {
    case clientError(String)
    case decodingFailed(Error)
    case unexpectedResponseFormat
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case unauthorized(String)
    case invalidModelId(String)

    var errorDescription: String? {
        switch self {
        case .clientError(let message):
            return message
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unexpectedResponseFormat:
            return "Unexpected response format from LLM"
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limited. Retry after \(retryAfter) seconds"
            } else {
                return "Rate limited"
            }
        case .timeout:
            return "Request timed out"
        case .unauthorized(let modelId):
            return "Access denied for model '\(modelId)'. This model may require special authorization or billing setup."
        case .invalidModelId(let modelId):
            return "Model '\(modelId)' is no longer available."
        }
    }
}

// MARK: - LLM Service

@Observable
final class LLMService {

    // Dependencies
    private var appState: AppState?
    private var enabledLLMStore: EnabledLLMStore?
    private var openRouterService: OpenRouterService?

    // Components
    private let requestExecutor: LLMRequestExecutor
    private let streamingExecutor: StreamingExecutor
    private let flexibleJSONExecutor: FlexibleJSONExecutor
    private var conversationCoordinator: ConversationCoordinator

    // Configuration
    private let defaultTemperature: Double = 1.0

    init(requestExecutor: LLMRequestExecutor = LLMRequestExecutor()) {
        self.requestExecutor = requestExecutor
        self.streamingExecutor = StreamingExecutor(requestExecutor: requestExecutor)
        self.flexibleJSONExecutor = FlexibleJSONExecutor(requestExecutor: requestExecutor)
        self.conversationCoordinator = ConversationCoordinator()
    }

    // MARK: - Initialization

    @MainActor
    func initialize(appState: AppState, modelContext: ModelContext? = nil, enabledLLMStore: EnabledLLMStore? = nil, openRouterService: OpenRouterService? = nil) {
        self.appState = appState
        self.enabledLLMStore = enabledLLMStore
        self.openRouterService = openRouterService
        let conversationStore = LLMConversationStore(modelContext: modelContext)
        self.conversationCoordinator = ConversationCoordinator(store: conversationStore)

        Task { [weak self] in
            guard let self else { return }
            await self.requestExecutor.configureClient()
            Logger.info("🔄 LLMService initialized with OpenRouter client")
        }
    }

    func reconfigureClient() {
        Task.detached { [requestExecutor] in
            await requestExecutor.configureClient()
            Logger.info("🔄 LLMService reconfigured OpenRouter client")
        }
    }

    private func ensureInitialized() async throws {
        let hasAppState = await MainActor.run { self.appState != nil }
        guard hasAppState else {
            throw LLMError.clientError("LLMService not initialized - call initialize() first")
        }

        if !(await requestExecutor.isConfigured()) {
            await requestExecutor.configureClient()
        }

        guard await requestExecutor.isConfigured() else {
            throw LLMError.clientError("OpenRouter API key not configured")
        }
    }

    // MARK: - Helpers

    private func loadMessages(conversationId: UUID) async -> [LLMMessageDTO] {
        await conversationCoordinator.messages(for: conversationId)
    }

    private func persistConversation(
        conversationId: UUID,
        messages: [LLMMessageDTO],
        objectId: UUID? = nil,
        objectType: ConversationType? = nil
    ) async {
        await conversationCoordinator.persist(
            conversationId: conversationId,
            messages: messages,
            objectId: objectId,
            objectType: objectType
        )
    }

    private func makeUserMessage(_ text: String, images: [Data]) -> LLMMessageDTO {
        guard !images.isEmpty else {
            return .text(text, role: .user)
        }

        let attachments = images.map { LLMAttachment(data: $0, mimeType: "image/png") }
        return LLMMessageDTO(role: .user, text: text, attachments: attachments)
    }

    private func assistantMessage(from text: String) -> LLMMessageDTO {
        LLMMessageDTO(role: .assistant, text: text, attachments: [])
    }

    private func parseResponseText(from response: LLMResponseDTO) throws -> String {
        guard let text = response.choices.first?.message?.text else {
            throw LLMError.unexpectedResponseFormat
        }
        return text
    }

    // MARK: - Core Operations

    func executeStructuredStreaming<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        responseType: T.Type,
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil
    ) -> AsyncThrowingStream<LLMStreamChunkDTO, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.ensureInitialized()

                    var parameters = LLMRequestBuilder.buildStructuredRequest(
                        prompt: prompt,
                        modelId: modelId,
                        responseType: responseType,
                        temperature: temperature ?? self.defaultTemperature,
                        jsonSchema: jsonSchema
                    )
                    self.streamingExecutor.applyReasoning(reasoning, to: &parameters)
                    parameters.stream = true

                    let stream = self.streamingExecutor.stream(
                        parameters: parameters,
                        accumulateContent: false
                    ) { _ in }

                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Conversation Streaming

    func startConversationStreaming(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> (conversationId: UUID, stream: AsyncThrowingStream<LLMStreamChunkDTO, Error>) {
        try await ensureInitialized()

        let conversationId = UUID()
        var messages: [LLMMessageDTO] = []
        if let systemPrompt {
            messages.append(.text(systemPrompt, role: .system))
        }
        messages.append(makeUserMessage(userMessage, images: []))
        await persistConversation(conversationId: conversationId, messages: messages)

        var parameters = LLMRequestBuilder.buildConversationRequest(
            messages: messages,
            modelId: modelId,
            temperature: temperature ?? defaultTemperature
        )
        if let jsonSchema = jsonSchema {
            let responseFormatSchema = JSONSchemaResponseFormat(
                name: "structured_response",
                strict: true,
                schema: jsonSchema
            )
            parameters.responseFormat = .jsonSchema(responseFormatSchema)
            Logger.debug("📝 Streaming conversation using structured output with JSON Schema enforcement")
        }
        streamingExecutor.applyReasoning(reasoning, to: &parameters)
        parameters.stream = true

        let seededMessages = messages
        let stream = streamingExecutor.stream(
            parameters: parameters,
            accumulateContent: true
        ) { [weak self] result in
            guard let self else { return }
            Task {
                switch result {
                case .success(let content?):
                    var updatedMessages = seededMessages
                    updatedMessages.append(self.assistantMessage(from: content))
                    await self.persistConversation(conversationId: conversationId, messages: updatedMessages)
                case .success:
                    break
                case .failure:
                    break
                }
            }
        }

        Logger.info("🗣️ Started streaming conversation: \(conversationId) with model: \(modelId)")
        return (conversationId: conversationId, stream: stream)
    }

    func continueConversationStreaming(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data] = [],
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil
    ) -> AsyncThrowingStream<LLMStreamChunkDTO, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.ensureInitialized()

                    var messages = await self.loadMessages(conversationId: conversationId)
                    messages.append(self.makeUserMessage(userMessage, images: images))
                    await self.persistConversation(conversationId: conversationId, messages: messages)
                    let seededMessages = messages

                    var parameters = LLMRequestBuilder.buildConversationRequest(
                        messages: messages,
                        modelId: modelId,
                        temperature: temperature ?? self.defaultTemperature
                    )
                    if let jsonSchema = jsonSchema {
                        let responseFormatSchema = JSONSchemaResponseFormat(
                            name: "structured_response",
                            strict: true,
                            schema: jsonSchema
                        )
                        parameters.responseFormat = .jsonSchema(responseFormatSchema)
                        Logger.debug("📝 Streaming conversation using structured output with JSON Schema enforcement")
                    }
                    self.streamingExecutor.applyReasoning(reasoning, to: &parameters)
                    parameters.stream = true

                    let stream = self.streamingExecutor.stream(
                        parameters: parameters,
                        accumulateContent: true
                    ) { [weak self] result in
                        guard let self else { return }
                        Task {
                            switch result {
                            case .success(let content?):
                                var updatedMessages = seededMessages
                                updatedMessages.append(self.assistantMessage(from: content))
                                await self.persistConversation(conversationId: conversationId, messages: updatedMessages)
                            case .success:
                                break
                            case .failure:
                                break
                            }
                        }
                    }

                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Conversation (non-streaming)

    func startConversation(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        temperature: Double? = nil
    ) async throws -> (conversationId: UUID, response: String) {
        try await ensureInitialized()

        var messages: [LLMMessageDTO] = []
        if let systemPrompt {
            messages.append(.text(systemPrompt, role: .system))
        }
        messages.append(makeUserMessage(userMessage, images: []))

        let parameters = LLMRequestBuilder.buildConversationRequest(
            messages: messages,
            modelId: modelId,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await requestExecutor.execute(parameters: parameters)
        let dto = LLMVendorMapper.responseDTO(from: response)
        let responseText = try parseResponseText(from: dto)

        messages.append(assistantMessage(from: responseText))

        let conversationId = UUID()
        await persistConversation(conversationId: conversationId, messages: messages)
        Logger.info("✅ Conversation started successfully: \(conversationId)")
        return (conversationId: conversationId, response: responseText)
    }

    func continueConversation(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data] = [],
        temperature: Double? = nil
    ) async throws -> String {
        try await ensureInitialized()

        var messages = await loadMessages(conversationId: conversationId)
        messages.append(self.makeUserMessage(userMessage, images: images))

        let parameters = LLMRequestBuilder.buildConversationRequest(
            messages: messages,
            modelId: modelId,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await requestExecutor.execute(parameters: parameters)
        let dto = LLMVendorMapper.responseDTO(from: response)
        let responseText = try parseResponseText(from: dto)

        messages.append(self.assistantMessage(from: responseText))
        await persistConversation(conversationId: conversationId, messages: messages)
        Logger.info("✅ Conversation continued successfully: \(conversationId)")
        return responseText
    }

    func continueConversationStructured<T: Codable>(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        responseType: T.Type,
        images: [Data] = [],
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> T {
        try await ensureInitialized()

        var messages = await loadMessages(conversationId: conversationId)
        messages.append(self.makeUserMessage(userMessage, images: images))

        let parameters = LLMRequestBuilder.buildStructuredConversationRequest(
            messages: messages,
            modelId: modelId,
            responseType: responseType,
            temperature: temperature ?? defaultTemperature,
            jsonSchema: jsonSchema
        )
        let response = try await requestExecutor.execute(parameters: parameters)
        let dto = LLMVendorMapper.responseDTO(from: response)
        let result = try JSONResponseParser.parseStructured(dto, as: responseType)

        let responseText: String
        if let data = try? JSONEncoder().encode(result) {
            responseText = String(data: data, encoding: .utf8) ?? "Structured response"
        } else {
            responseText = "Structured response"
        }
        messages.append(self.assistantMessage(from: responseText))
        await persistConversation(conversationId: conversationId, messages: messages)
        Logger.info("✅ Structured conversation continued successfully: \(conversationId)")
        return result
    }

    /// Request with flexible JSON output - uses structured output when available, basic JSON mode otherwise
    func executeFlexibleJSON<T: Codable>(
        prompt: String,
        modelId: String,
        responseType: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> T {
        try await ensureInitialized()

        let model = await MainActor.run { self.openRouterService?.findModel(id: modelId) }
        let supportsStructuredOutput = model?.supportsStructuredOutput ?? false
        let shouldAvoidJSONSchema = await MainActor.run {
            self.enabledLLMStore?.shouldAvoidJSONSchema(modelId: modelId) ?? false
        }
        let store = await MainActor.run { self.enabledLLMStore }

        let recordSchemaSuccess: () async -> Void = {
            guard let store else { return }
            await store.recordJSONSchemaSuccess(modelId: modelId)
        }
        let recordSchemaFailure: (_ reason: String) async -> Void = { reason in
            guard let store else { return }
            await store.recordJSONSchemaFailure(modelId: modelId, reason: reason)
        }

        return try await flexibleJSONExecutor.execute(
            prompt: prompt,
            modelId: modelId,
            responseType: responseType,
            temperature: temperature ?? defaultTemperature,
            jsonSchema: jsonSchema,
            supportsStructuredOutput: supportsStructuredOutput,
            shouldAvoidJSONSchema: shouldAvoidJSONSchema,
            recordSchemaSuccess: recordSchemaSuccess,
            recordSchemaFailure: recordSchemaFailure
        )
    }

    func cancelAllRequests() {
        Task.detached { [requestExecutor] in
            await requestExecutor.cancelAllRequests()
            Logger.info("🛑 Cancelled all LLM requests")
        }
    }
}
