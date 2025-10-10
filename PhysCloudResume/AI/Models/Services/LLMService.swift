//
//  LLMService.swift
//  PhysCloudResume
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
        }
    }
}

// MARK: - Conversation Cache

private actor ConversationCache {
    private var storage: [UUID: [LLMMessageDTO]] = [:]

    func messages(for conversationId: UUID) -> [LLMMessageDTO]? {
        storage[conversationId]
    }

    func setMessages(_ messages: [LLMMessageDTO], for conversationId: UUID) {
        storage[conversationId] = messages
    }

    func clear(_ conversationId: UUID) {
        storage.removeValue(forKey: conversationId)
    }
}

// MARK: - LLM Service

@Observable
final class LLMService {

    // Dependencies
    private var appState: AppState?
    private var enabledLLMStore: EnabledLLMStore?
    private var conversationStore: LLMConversationStore?

    // Components
    private let requestExecutor: LLMRequestExecutor
    private let conversationCache = ConversationCache()

    // Configuration
    private let defaultTemperature: Double = 1.0

    init(requestExecutor: LLMRequestExecutor = LLMRequestExecutor()) {
        self.requestExecutor = requestExecutor
    }

    // MARK: - Initialization

    @MainActor
    func initialize(appState: AppState, modelContext: ModelContext? = nil) {
        self.appState = appState
        self.enabledLLMStore = appState.enabledLLMStore
        if let modelContext {
            self.conversationStore = LLMConversationStore(modelContext: modelContext)
        } else if conversationStore == nil {
            self.conversationStore = LLMConversationStore(modelContext: nil)
        }

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

        await MainActor.run {
            if self.conversationStore == nil {
                self.conversationStore = LLMConversationStore(modelContext: nil)
            }
        }
    }

    // MARK: - Helpers

    private func loadMessages(conversationId: UUID) async -> [LLMMessageDTO] {
        if let cached = await conversationCache.messages(for: conversationId) {
            return cached
        }
        let persisted = await conversationStore?.loadMessages(conversationId: conversationId) ?? []
        if !persisted.isEmpty {
            await conversationCache.setMessages(persisted, for: conversationId)
        }
        return persisted
    }

    private func persistConversation(
        conversationId: UUID,
        messages: [LLMMessageDTO],
        objectId: UUID? = nil,
        objectType: ConversationType? = nil
    ) async {
        await conversationCache.setMessages(messages, for: conversationId)
        await conversationStore?.saveMessages(
            conversationId: conversationId,
            objectId: objectId,
            objectType: objectType,
            messages: messages
        )
    }

    private func clearConversationCache(_ conversationId: UUID) async {
        await conversationCache.clear(conversationId)
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

    private func applyReasoning(
        _ reasoning: OpenRouterReasoning?,
        to parameters: inout ChatCompletionParameters
    ) {
        guard let reasoning else { return }
        let hasOverride =
            reasoning.maxTokens != nil ||
            (reasoning.exclude != nil && reasoning.exclude != false)

        if hasOverride {
            parameters.reasoningEffort = nil
            parameters.reasoning = ChatCompletionParameters.ReasoningOverrides(
                effort: reasoning.effort,
                exclude: reasoning.exclude,
                maxTokens: reasoning.maxTokens
            )
            Logger.debug(
                "🧠 Configured reasoning override: effort=\(reasoning.effort ?? "nil"), exclude=\(String(describing: reasoning.exclude)), max_tokens=\(String(describing: reasoning.maxTokens))"
            )
        } else {
            parameters.reasoning = nil
            parameters.reasoningEffort = reasoning.effort
        }
    }

    private func parseResponseText(from response: LLMResponseDTO) throws -> String {
        guard let text = response.choices.first?.message?.text else {
            throw LLMError.unexpectedResponseFormat
        }
        return text
    }

    private func fetchAppState() async -> AppState? {
        await MainActor.run { self.appState }
    }

    // MARK: - Core Operations

    func execute(
        prompt: String,
        modelId: String,
        temperature: Double? = nil
    ) async throws -> String {
        try await ensureInitialized()
        try await validateModel(modelId: modelId, for: [])

        let parameters = LLMRequestBuilder.buildTextRequest(
            prompt: prompt,
            modelId: modelId,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await requestExecutor.execute(parameters: parameters)
        let dto = LLMVendorMapper.responseDTO(from: response)
        return try parseResponseText(from: dto)
    }

    func executeWithImages(
        prompt: String,
        modelId: String,
        images: [Data],
        temperature: Double? = nil
    ) async throws -> String {
        try await ensureInitialized()
        try await validateModel(modelId: modelId, for: [.vision])

        let parameters = LLMRequestBuilder.buildVisionRequest(
            prompt: prompt,
            modelId: modelId,
            images: images,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await requestExecutor.execute(parameters: parameters)
        let dto = LLMVendorMapper.responseDTO(from: response)
        return try parseResponseText(from: dto)
    }

    func executeStructured<T: Codable>(
        prompt: String,
        modelId: String,
        responseType: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> T {
        try await ensureInitialized()
        try await validateModel(modelId: modelId, for: [])

        let parameters = LLMRequestBuilder.buildStructuredRequest(
            prompt: prompt,
            modelId: modelId,
            responseType: responseType,
            temperature: temperature ?? defaultTemperature,
            jsonSchema: jsonSchema
        )
        let response = try await requestExecutor.execute(parameters: parameters)
        let dto = LLMVendorMapper.responseDTO(from: response)
        return try JSONResponseParser.parseStructured(dto, as: responseType)
    }

    func executeStructuredWithImages<T: Codable>(
        prompt: String,
        modelId: String,
        images: [Data],
        responseType: T.Type,
        temperature: Double? = nil
    ) async throws -> T {
        try await ensureInitialized()
        try await validateModel(modelId: modelId, for: [.vision])

        let parameters = LLMRequestBuilder.buildStructuredVisionRequest(
            prompt: prompt,
            modelId: modelId,
            images: images,
            responseType: responseType,
            temperature: temperature ?? defaultTemperature
        )
        let response = try await requestExecutor.execute(parameters: parameters)
        let dto = LLMVendorMapper.responseDTO(from: response)
        return try JSONResponseParser.parseStructured(dto, as: responseType)
    }

    // MARK: - Streaming Operations

    func executeStreaming(
        prompt: String,
        modelId: String,
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil
    ) -> AsyncThrowingStream<LLMStreamChunkDTO, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.ensureInitialized()
                    try await self.validateModel(modelId: modelId, for: [])

                    var parameters = LLMRequestBuilder.buildTextRequest(
                        prompt: prompt,
                        modelId: modelId,
                        temperature: temperature ?? self.defaultTemperature
                    )
                    self.applyReasoning(reasoning, to: &parameters)
                    parameters.stream = true

                    let stream = try await self.requestExecutor.executeStreaming(parameters: parameters)
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        let dto = LLMVendorMapper.streamChunkDTO(from: chunk)
                        continuation.yield(dto)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

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
                    try await self.validateModel(modelId: modelId, for: [])

                    var parameters = LLMRequestBuilder.buildStructuredRequest(
                        prompt: prompt,
                        modelId: modelId,
                        responseType: responseType,
                        temperature: temperature ?? self.defaultTemperature,
                        jsonSchema: jsonSchema
                    )
                    self.applyReasoning(reasoning, to: &parameters)
                    parameters.stream = true

                    let stream = try await self.requestExecutor.executeStreaming(parameters: parameters)
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        let dto = LLMVendorMapper.streamChunkDTO(from: chunk)
                        continuation.yield(dto)
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
        try await validateModel(modelId: modelId, for: [])

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
        applyReasoning(reasoning, to: &parameters)
        parameters.stream = true

        let stream = AsyncThrowingStream<LLMStreamChunkDTO, Error> { continuation in
            Task {
                var accumulated = ""
                do {
                    let rawStream = try await self.requestExecutor.executeStreaming(parameters: parameters)
                    for try await chunk in rawStream {
                        if Task.isCancelled { break }
                        let dto = LLMVendorMapper.streamChunkDTO(from: chunk)
                        if let content = dto.content {
                            accumulated += content
                        }
                        continuation.yield(dto)
                    }
                    messages.append(self.assistantMessage(from: accumulated))
                    await self.persistConversation(conversationId: conversationId, messages: messages)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
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

                    let requiredCapabilities: [ModelCapability] = images.isEmpty ? [] : [.vision]
                    try await self.validateModel(modelId: modelId, for: requiredCapabilities)

                    var messages = await self.loadMessages(conversationId: conversationId)
                    messages.append(self.makeUserMessage(userMessage, images: images))
                    await self.persistConversation(conversationId: conversationId, messages: messages)

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
                    self.applyReasoning(reasoning, to: &parameters)
                    parameters.stream = true

                    let rawStream = try await self.requestExecutor.executeStreaming(parameters: parameters)
                    var accumulated = ""
                    for try await chunk in rawStream {
                        if Task.isCancelled { break }
                        let dto = LLMVendorMapper.streamChunkDTO(from: chunk)
                        if let content = dto.content {
                            accumulated += content
                        }
                        continuation.yield(dto)
                    }
                    messages.append(self.assistantMessage(from: accumulated))
                    await self.persistConversation(conversationId: conversationId, messages: messages)
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
        try await validateModel(modelId: modelId, for: [])

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

        let requiredCapabilities: [ModelCapability] = images.isEmpty ? [] : [.vision]
        try await validateModel(modelId: modelId, for: requiredCapabilities)

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

        var required: [ModelCapability] = [.structuredOutput]
        if !images.isEmpty { required.append(.vision) }
        try await validateModel(modelId: modelId, for: required)

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

    // MARK: - Multi-Model Operations

    func executeParallelStructured<T: Codable & Sendable>(
        prompt: String,
        modelIds: [String],
        responseType: T.Type,
        temperature: Double? = nil
    ) async throws -> [String: T] {
        try await ensureInitialized()

        Logger.info("🚀 Starting parallel execution across \(modelIds.count) models")
        var results: [String: T] = [:]

        try await withThrowingTaskGroup(of: (String, T).self) { group in
            for modelId in modelIds {
                group.addTask {
                    let result = try await self.executeStructured(
                        prompt: prompt,
                        modelId: modelId,
                        responseType: responseType,
                        temperature: temperature
                    )
                    return (modelId, result)
                }
            }

            for try await (modelId, result) in group {
                results[modelId] = result
            }
        }

        Logger.info("✅ Parallel execution completed: \(results.count)/\(modelIds.count) models succeeded")
        return results
    }

    struct ParallelExecutionResult<T: Codable & Sendable> {
        let successes: [String: T]
        let failures: [String: String]

        var hasSuccesses: Bool { !successes.isEmpty }
    }

    func executeParallelFlexibleJSONWithFailures<T: Codable & Sendable>(
        prompt: String,
        modelIds: [String],
        responseType: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> ParallelExecutionResult<T> {
        try await ensureInitialized()

        Logger.info("🚀 Starting flexible parallel execution across \(modelIds.count) models")
        var results: [String: T] = [:]
        var failures: [String: String] = [:]

        await withTaskGroup(of: (String, Result<T, Error>).self) { group in
            for modelId in modelIds {
                group.addTask {
                    do {
                        let value = try await self.executeFlexibleJSON(
                            prompt: prompt,
                            modelId: modelId,
                            responseType: responseType,
                            temperature: temperature,
                            jsonSchema: jsonSchema
                        )
                        return (modelId, .success(value))
                    } catch {
                        return (modelId, .failure(error))
                    }
                }
            }

            for await (modelId, result) in group {
                switch result {
                case .success(let value):
                    results[modelId] = value
                case .failure(let error):
                    failures[modelId] = error.localizedDescription
                }
            }
        }

        if !failures.isEmpty {
            Logger.warning("⚠️ Flexible parallel execution encountered \(failures.count) failures")
            for (modelId, error) in failures {
                Logger.debug("  - \(modelId): \(error)")
            }
        }

        Logger.info("✅ Flexible parallel execution completed: \(results.count)/\(modelIds.count) models succeeded, \(failures.count) failed")
        return ParallelExecutionResult(successes: results, failures: failures)
    }

    func executeParallelFlexibleJSON<T: Codable & Sendable>(
        prompt: String,
        modelIds: [String],
        responseType: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> [String: T] {
        let result = try await executeParallelFlexibleJSONWithFailures(
            prompt: prompt,
            modelIds: modelIds,
            responseType: responseType,
            temperature: temperature,
            jsonSchema: jsonSchema
        )
        return result.successes
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
        try await validateModel(modelId: modelId, for: [])

        let model = await MainActor.run { self.appState?.openRouterService.findModel(id: modelId) }
        let supportsStructuredOutput = model?.supportsStructuredOutput ?? false
        let shouldAvoidJSONSchema = await MainActor.run {
            self.enabledLLMStore?.shouldAvoidJSONSchema(modelId: modelId) ?? false
        }

        let parameters = LLMRequestBuilder.buildFlexibleJSONRequest(
            prompt: prompt,
            modelId: modelId,
            responseType: responseType,
            temperature: temperature ?? defaultTemperature,
            jsonSchema: jsonSchema,
            supportsStructuredOutput: supportsStructuredOutput,
            shouldAvoidJSONSchema: shouldAvoidJSONSchema
        )

        do {
            let response = try await requestExecutor.execute(parameters: parameters)
            let dto = LLMVendorMapper.responseDTO(from: response)
            let result = try JSONResponseParser.parseFlexible(from: dto, as: responseType)

            if supportsStructuredOutput && !shouldAvoidJSONSchema && jsonSchema != nil {
                await MainActor.run {
                    self.enabledLLMStore?.recordJSONSchemaSuccess(modelId: modelId)
                }
                Logger.info("✅ JSON schema validation successful for model: \(modelId)")
            }

            return result
        } catch {
            let description = error.localizedDescription.lowercased()
            if description.contains("response_format") || description.contains("json_schema") {
                await MainActor.run {
                    self.enabledLLMStore?.recordJSONSchemaFailure(modelId: modelId, reason: error.localizedDescription)
                }
                Logger.debug("🚫 Recorded JSON schema failure for \(modelId): \(error.localizedDescription)")
            }
            throw error
        }
    }

    // MARK: - Model Management

    func validateModel(modelId: String, for capabilities: [ModelCapability]) async throws {
        guard let appState = await fetchAppState() else {
            throw LLMError.clientError("LLMService not properly initialized")
        }

        let resolvedModel = await MainActor.run { appState.openRouterService.findModel(id: modelId) }
        guard let model = resolvedModel else {
            throw LLMError.clientError("Model '\(modelId)' not found")
        }

        for capability in capabilities {
            let hasCapability: Bool
            switch capability {
            case .vision:
                hasCapability = model.supportsImages
            case .structuredOutput:
                hasCapability = model.supportsStructuredOutput
            case .reasoning:
                hasCapability = model.supportsReasoning
            case .textOnly:
                hasCapability = model.isTextToText && !model.supportsImages
            }

            if !hasCapability {
                throw LLMError.clientError("Model '\(modelId)' does not support \(capability.displayName)")
            }
        }
    }

    // MARK: - Conversation Management

    func clearConversation(id conversationId: UUID) {
        Task {
            await self.clearConversationCache(conversationId)
            await self.conversationStore?.clearConversation(conversationId: conversationId)
        }
    }

    func cancelAllRequests() {
        Task.detached { [requestExecutor] in
            await requestExecutor.cancelAllRequests()
            Logger.info("🛑 Cancelled all LLM requests")
        }
    }
}
