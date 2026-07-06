//
//  LLMFacade.swift
//  Sprung
//
//  A thin facade over LLMClient that centralizes capability gating and
//  exposes a stable surface to callers. Delegates to specialized components
//  for streaming, capability validation, and specialized API operations.
//
import Foundation
import Observation
import SwiftOpenAI

struct LLMStreamingHandle {
    let conversationId: UUID?
    let stream: AsyncThrowingStream<LLMStreamChunkDTO, Error>
    let cancel: @Sendable () -> Void
}

/// `LLMFacade` is the **only public entry point** for LLM operations in Sprung.
///
/// ## Usage
/// Create via `LLMFacadeFactory.create(...)` and register additional backends
/// via `registerClient(_:for:)`.
///
/// ## Public API
/// - `executeText(...)` - Simple text prompts
/// - `executeTextWithImages(...)` - Vision capabilities
/// - `executeStructured(...)` - Structured JSON responses
/// - `startConversation(...)` / `continueConversation(...)` - Multi-turn conversations
/// - `startConversationStreaming(...)` / `continueConversationStreaming(...)` - Streaming
/// - `registerClient(_:for:)` - Register custom backend implementations
@Observable
@MainActor
final class LLMFacade {
    enum Backend: CaseIterable {
        case openRouter
        case openAI
        case anthropic
        var displayName: String {
            switch self {
            case .openRouter: return "OpenRouter"
            case .openAI: return "OpenAI"
            case .anthropic: return "Anthropic"
            }
        }
    }

    private let client: LLMClient
    private let llmService: OpenRouterServiceBackend
    private let openRouterService: OpenRouterService
    private var backendClients: [Backend: LLMClient] = [:]

    // Extracted components
    private static func jsonLogString<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: value)
    }

    private let streamingManager = LLMStreamingService()
    private let capabilityValidator: LLMFacadeCapabilityValidator
    private let specializedAPIs = LLMFacadeSpecializedAPIs()

    init(
        client: LLMClient,
        llmService: OpenRouterServiceBackend,
        openRouterService: OpenRouterService,
        enabledLLMStore: EnabledLLMStore?,
        modelValidationService: ModelValidationService
    ) {
        self.client = client
        self.llmService = llmService
        self.openRouterService = openRouterService
        self.capabilityValidator = LLMFacadeCapabilityValidator(
            enabledLLMStore: enabledLLMStore,
            openRouterService: openRouterService,
            modelValidationService: modelValidationService
        )
        backendClients[.openRouter] = client
    }

    func registerClient(_ client: LLMClient, for backend: Backend) {
        backendClients[backend] = client
    }

    func registerOpenAIService(_ service: OpenAIService) {
        specializedAPIs.registerOpenAIService(service)
    }

    func registerAnthropicService(_ service: AnthropicService) {
        specializedAPIs.registerAnthropicService(service)
    }

    /// The currently-registered Anthropic service (for the recording/replay swap).
    func currentAnthropicService() -> AnthropicService? {
        specializedAPIs.currentAnthropicService()
    }

    /// Observer for per-request token usage from the Anthropic structured/text
    /// execution path. A host installs this to aggregate cost; see `LLMRequestUsage`.
    var anthropicUsageObserver: (@Sendable (LLMRequestUsage) -> Void)? {
        get { specializedAPIs.anthropicUsageObserver }
        set { specializedAPIs.anthropicUsageObserver = newValue }
    }

    private func resolveClient(for backend: Backend) throws -> LLMClient {
        guard let resolved = backendClients[backend] else {
            throw LLMError.clientError("Backend \(backend.displayName) is not configured")
        }
        return resolved
    }
    // MARK: - Text Execution

    func executeText(
        prompt: String,
        modelId: String,
        backend: Backend = .openRouter
    ) async throws -> String {
        let start = ContinuousClock.now
        let result: String
        if backend == .openRouter {
            try await capabilityValidator.validate(modelId: modelId, requires: [])
            result = try await client.executeText(prompt: prompt, modelId: modelId)
        } else {
            let altClient = try resolveClient(for: backend)
            result = try await altClient.executeText(prompt: prompt, modelId: modelId)
        }
        LLMTranscriptLogger.logTextCall(
            method: "executeText", modelId: modelId, backend: backend.displayName,
            prompt: prompt, response: result, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func executeTextWithImages(
        prompt: String,
        modelId: String,
        images: [Data],
        backend: Backend = .openRouter
    ) async throws -> String {
        let start = ContinuousClock.now
        let result: String
        if backend == .openRouter {
            try await capabilityValidator.validate(modelId: modelId, requires: [.vision])
            result = try await client.executeTextWithImages(prompt: prompt, modelId: modelId, images: images)
        } else {
            let altClient = try resolveClient(for: backend)
            result = try await altClient.executeTextWithImages(prompt: prompt, modelId: modelId, images: images)
        }
        LLMTranscriptLogger.logTextCall(
            method: "executeTextWithImages", modelId: modelId, backend: backend.displayName,
            prompt: "[+\(images.count) images] \(prompt)", response: result, durationMs: elapsedMs(from: start)
        )
        return result
    }

    // MARK: - Structured Execution

    func executeStructured<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        backend: Backend = .openRouter
    ) async throws -> T {
        let start = ContinuousClock.now
        let result: T
        if backend == .openRouter {
            try await capabilityValidator.validate(modelId: modelId, requires: [.structuredOutput])
            result = try await client.executeStructured(prompt: prompt, modelId: modelId, as: type)
        } else {
            let altClient = try resolveClient(for: backend)
            result = try await altClient.executeStructured(prompt: prompt, modelId: modelId, as: type)
        }
        let jsonString = Self.jsonLogString(result)
        LLMTranscriptLogger.logStructuredCall(
            method: "executeStructured", modelId: modelId, backend: backend.displayName,
            prompt: prompt, responseType: String(describing: T.self), responseJSON: jsonString, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func executeStructuredWithImages<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        images: [Data],
        as type: T.Type,
        backend: Backend = .openRouter
    ) async throws -> T {
        let start = ContinuousClock.now
        let result: T
        if backend == .openRouter {
            try await capabilityValidator.validate(modelId: modelId, requires: [.vision, .structuredOutput])
            result = try await client.executeStructuredWithImages(prompt: prompt, modelId: modelId, images: images, as: type)
        } else {
            let altClient = try resolveClient(for: backend)
            result = try await altClient.executeStructuredWithImages(prompt: prompt, modelId: modelId, images: images, as: type)
        }
        let jsonString = Self.jsonLogString(result)
        LLMTranscriptLogger.logStructuredCall(
            method: "executeStructuredWithImages", modelId: modelId, backend: backend.displayName,
            prompt: "[+\(images.count) images] \(prompt)", responseType: String(describing: T.self), responseJSON: jsonString, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func executeStructuredWithSchema<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        schema: JSONSchema,
        schemaName: String,
        backend: Backend = .openRouter
    ) async throws -> T {
        let start = ContinuousClock.now
        let result: T
        if backend == .openRouter {
            try await capabilityValidator.validate(modelId: modelId, requires: [.structuredOutput])
            result = try await client.executeStructuredWithSchema(prompt: prompt, modelId: modelId, as: type, schema: schema, schemaName: schemaName)
        } else {
            let altClient = try resolveClient(for: backend)
            result = try await altClient.executeStructuredWithSchema(prompt: prompt, modelId: modelId, as: type, schema: schema, schemaName: schemaName)
        }
        let jsonString = Self.jsonLogString(result)
        LLMTranscriptLogger.logStructuredCall(
            method: "executeStructuredWithSchema(\(schemaName))", modelId: modelId, backend: backend.displayName,
            prompt: prompt, responseType: String(describing: T.self), responseJSON: jsonString, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func executeStructuredWithDictionarySchema<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        schema: [String: Any],
        schemaName: String,
        maxOutputTokens: Int = 32768,
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        backend: Backend = .openRouter
    ) async throws -> T {
        let start = ContinuousClock.now
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = keyDecodingStrategy

        let result: T
        switch backend {
        case .anthropic:
            let systemContent: [AnthropicSystemBlock] = [
                AnthropicSystemBlock(text: "You are a helpful assistant that responds with well-structured JSON.")
            ]
            result = try await executeStructuredWithAnthropicCaching(
                systemContent: systemContent,
                userPrompt: prompt,
                modelId: modelId,
                responseType: type,
                schema: schema
            )

        case .openRouter, .openAI:
            let jsonSchema = try JSONSchema.from(dictionary: schema)
            result = try await executeStructuredWithSchema(
                prompt: prompt,
                modelId: modelId,
                as: type,
                schema: jsonSchema,
                schemaName: schemaName,
                backend: backend
            )
        }
        let jsonString = Self.jsonLogString(result)
        LLMTranscriptLogger.logStructuredCall(
            method: "executeStructuredWithDictionarySchema(\(schemaName))", modelId: modelId, backend: backend.displayName,
            prompt: prompt, responseType: String(describing: T.self), responseJSON: jsonString, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func executeFlexibleJSON<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        jsonSchema: JSONSchema? = nil,
        backend: Backend = .openRouter
    ) async throws -> T {
        let start = ContinuousClock.now
        let required: [ModelCapability] = jsonSchema == nil ? [] : [.structuredOutput]
        let result: T
        if backend == .openRouter {
            try await capabilityValidator.validate(modelId: modelId, requires: required)
            result = try await llmService.executeFlexibleJSON(
                prompt: prompt,
                modelId: modelId,
                responseType: type,
                jsonSchema: jsonSchema
            )
        } else {
            let altClient = try resolveClient(for: backend)
            result = try await altClient.executeStructured(
                prompt: prompt,
                modelId: modelId,
                as: type
            )
        }
        let jsonString = Self.jsonLogString(result)
        LLMTranscriptLogger.logStructuredCall(
            method: "executeFlexibleJSON", modelId: modelId, backend: backend.displayName,
            prompt: prompt, responseType: String(describing: T.self), responseJSON: jsonString, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func executeStructuredStreaming<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil,
        backend: Backend = .openRouter,
        systemPrompt: String? = nil
    ) async throws -> LLMStreamingHandle {
        guard backend == .openRouter else {
            throw LLMError.clientError("Structured streaming is not supported for backend \(backend.displayName)")
        }
        var required: [ModelCapability] = [.structuredOutput]
        if reasoning != nil { required.append(.reasoning) }
        try await capabilityValidator.validate(modelId: modelId, requires: required)

        let sourceStream = llmService.executeStructuredStreaming(
            prompt: prompt,
            modelId: modelId,
            responseType: type,
            reasoning: reasoning,
            jsonSchema: jsonSchema,
            systemPrompt: systemPrompt
        )
        LLMTranscriptLogger.logStreamingRequest(
            method: "executeStructuredStreaming", modelId: modelId,
            backend: backend.displayName, prompt: prompt
        )
        return streamingManager.makeStreamingHandle(conversationId: nil, sourceStream: sourceStream)
    }
    // MARK: - Conversation Streaming

    /// The provider-reported maximum output (completion) token limit for a model,
    /// or `nil` when OpenRouter doesn't expose one. Used to give structured-output
    /// requests full headroom instead of relying on a small provider default.
    func maxOutputTokens(forModel modelId: String) -> Int? {
        openRouterService.resolveModel(id: modelId)?.maxOutputTokens
    }

    func startConversationStreaming(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil,
        maxTokens: Int? = nil
    ) async throws -> LLMStreamingHandle {
        try await startConversationStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            reasoning: reasoning,
            jsonSchema: jsonSchema,
            backend: .openRouter,
            maxTokens: maxTokens
        )
    }

    func startConversationStreaming(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil,
        backend: Backend,
        maxTokens: Int? = nil
    ) async throws -> LLMStreamingHandle {
        guard backend == .openRouter else {
            throw LLMError.clientError("Streaming conversations are not supported for backend \(backend.displayName)")
        }
        var required: [ModelCapability] = []
        if reasoning != nil { required.append(.reasoning) }
        if jsonSchema != nil { required.append(.structuredOutput) }
        try await capabilityValidator.validate(modelId: modelId, requires: required)
        let (conversationId, sourceStream) = try await llmService.startConversationStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            reasoning: reasoning,
            jsonSchema: jsonSchema,
            maxTokens: maxTokens
        )
        let handle = streamingManager.makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        LLMTranscriptLogger.logStreamingRequest(
            method: "startConversationStreaming", modelId: modelId, backend: backend.displayName,
            prompt: "System: \(systemPrompt ?? "(none)")\nUser: \(userMessage)"
        )
        return handle
    }

    func continueConversationStreaming(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data] = [],
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil,
        backend: Backend = .openRouter
    ) async throws -> LLMStreamingHandle {
        guard backend == .openRouter else {
            throw LLMError.clientError("Streaming conversations are not supported for backend \(backend.displayName)")
        }
        var required: [ModelCapability] = images.isEmpty ? [] : [.vision]
        if reasoning != nil { required.append(.reasoning) }
        if jsonSchema != nil { required.append(.structuredOutput) }
        try await capabilityValidator.validate(modelId: modelId, requires: required)
        let sourceStream = llmService.continueConversationStreaming(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            images: images,
            reasoning: reasoning,
            jsonSchema: jsonSchema
        )
        let handle = streamingManager.makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        LLMTranscriptLogger.logStreamingRequest(
            method: "continueConversationStreaming", modelId: modelId, backend: backend.displayName,
            prompt: "ConversationId: \(conversationId)\nUser: \(userMessage)"
        )
        return handle
    }

    // MARK: - Conversation (Non-Streaming)

    func continueConversation(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data] = [],
        backend: Backend = .openRouter
    ) async throws -> String {
        let start = ContinuousClock.now
        guard backend == .openRouter else {
            throw LLMError.clientError("Conversations are only supported via OpenRouter at this time")
        }
        let required: [ModelCapability] = images.isEmpty ? [] : [.vision]
        try await capabilityValidator.validate(modelId: modelId, requires: required)
        let result = try await llmService.continueConversation(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            images: images
        )
        LLMTranscriptLogger.logTextCall(
            method: "continueConversation", modelId: modelId, backend: backend.displayName,
            prompt: "ConversationId: \(conversationId)\nUser: \(userMessage)", response: result, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func continueConversationStructured<T: Codable & Sendable>(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        as type: T.Type,
        images: [Data] = [],
        jsonSchema: JSONSchema? = nil,
        backend: Backend = .openRouter
    ) async throws -> T {
        let start = ContinuousClock.now
        guard backend == .openRouter else {
            throw LLMError.clientError("Conversations are only supported via OpenRouter at this time")
        }
        var required: [ModelCapability] = [.structuredOutput]
        if !images.isEmpty { required.append(.vision) }
        try await capabilityValidator.validate(modelId: modelId, requires: required)
        let result = try await llmService.continueConversationStructured(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            responseType: type,
            images: images,
            jsonSchema: jsonSchema
        )
        let jsonString = Self.jsonLogString(result)
        LLMTranscriptLogger.logStructuredCall(
            method: "continueConversationStructured", modelId: modelId, backend: backend.displayName,
            prompt: "ConversationId: \(conversationId)\nUser: \(userMessage)", responseType: String(describing: T.self), responseJSON: jsonString, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func startConversation(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        backend: Backend = .openRouter
    ) async throws -> (UUID, String) {
        let start = ContinuousClock.now
        guard backend == .openRouter else {
            throw LLMError.clientError("Conversations are only supported via OpenRouter at this time")
        }
        try await capabilityValidator.validate(modelId: modelId, requires: [])
        let result = try await llmService.startConversation(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId
        )
        LLMTranscriptLogger.logTextCall(
            method: "startConversation", modelId: modelId, backend: backend.displayName,
            prompt: "System: \(systemPrompt ?? "(none)")\nUser: \(userMessage)", response: result.1, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func cancelAllRequests() {
        streamingManager.cancelAllTasks()
        llmService.cancelAllRequests()
    }

    // MARK: - OpenAI Responses API (Specialized)

    func executeWithWebSearch(
        systemPrompt: String,
        userMessage: String,
        modelId: String,
        reasoningEffort: String? = nil,
        webSearchLocation: String? = nil,
        onWebSearching: (@MainActor @Sendable () async -> Void)? = nil,
        onWebSearchComplete: (@MainActor @Sendable () async -> Void)? = nil,
        onTextDelta: (@MainActor @Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        let start = ContinuousClock.now
        let result = try await specializedAPIs.executeWithWebSearch(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            reasoningEffort: reasoningEffort,
            webSearchLocation: webSearchLocation,
            onWebSearching: onWebSearching,
            onWebSearchComplete: onWebSearchComplete,
            onTextDelta: onTextDelta
        )
        LLMTranscriptLogger.logTextCall(
            method: "executeWithWebSearch", modelId: modelId, backend: "OpenAI",
            prompt: "System: \(systemPrompt)\nUser: \(userMessage)", response: result, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func responseCreateStream(
        parameters: ModelResponseParameter
    ) async throws -> AsyncThrowingStream<ResponseStreamEvent, Error> {
        try await specializedAPIs.responseCreateStream(parameters: parameters)
    }

    // MARK: - Anthropic Messages API (Specialized)

    func anthropicMessagesStream(
        parameters: AnthropicMessageParameter
    ) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        try await specializedAPIs.anthropicMessagesStream(parameters: parameters)
    }

    /// Non-streaming Anthropic messages call — used by multi-turn agent loops
    /// (git analysis, card merge) where the full response is consumed at once.
    func anthropicMessages(
        parameters: AnthropicMessageParameter
    ) async throws -> AnthropicMessageResponse {
        try await specializedAPIs.anthropicMessages(parameters: parameters)
    }

    func anthropicListModels() async throws -> AnthropicModelsResponse {
        try await specializedAPIs.anthropicListModels()
    }

    /// Upload a file to the Anthropic Files API for use in document blocks
    /// (`{"type": "document", "source": {"type": "file", "file_id": ...}}`).
    func anthropicUploadFile(data: Data, filename: String, mimeType: String) async throws -> AnthropicFileMetadata {
        try await specializedAPIs.anthropicUploadFile(data: data, filename: filename, mimeType: mimeType)
    }

    /// Delete a file from the Anthropic Files API.
    func anthropicDeleteFile(id: String) async throws -> AnthropicFileDeletedResponse {
        try await specializedAPIs.anthropicDeleteFile(id: id)
    }

    /// Count tokens for a prospective Anthropic Messages API request.
    /// Counted requests carry the same beta headers as the request that will be sent.
    func anthropicCountTokens(parameters: AnthropicTokenCountParameter) async throws -> AnthropicTokenCountResponse {
        try await specializedAPIs.anthropicCountTokens(parameters: parameters)
    }

    /// Execute a text prompt via direct Anthropic API with prompt caching.
    /// The system content blocks can include cache_control for server-side caching.
    /// - Parameters:
    ///   - systemContent: Array of system content blocks (some may have cache_control)
    ///   - userPrompt: The user's request/prompt
    ///   - modelId: Anthropic model ID (e.g., "claude-sonnet-4-20250514")
    /// - Returns: The assistant's text response
    func executeTextWithAnthropicCaching(
        systemContent: [AnthropicSystemBlock],
        userPrompt: String,
        modelId: String
    ) async throws -> String {
        let start = ContinuousClock.now
        let result = try await specializedAPIs.executeTextWithAnthropicCaching(
            systemContent: systemContent,
            userPrompt: userPrompt,
            modelId: modelId
        )
        LLMTranscriptLogger.logAnthropicCall(
            method: "executeTextWithAnthropicCaching", modelId: modelId,
            systemBlockCount: systemContent.count, userPrompt: userPrompt,
            response: result, durationMs: elapsedMs(from: start)
        )
        return result
    }

    /// Execute a structured JSON request via direct Anthropic API with prompt caching and schema enforcement.
    /// Uses Anthropic's structured outputs feature via the `output_config.format` parameter.
    /// - Parameters:
    ///   - systemContent: Array of system content blocks (some may have cache_control)
    ///   - userPrompt: The user's request/prompt
    ///   - modelId: Anthropic model ID (e.g., "claude-sonnet-4-20250514")
    ///   - responseType: The expected response type
    ///   - schema: JSON schema dictionary for the structured output
    /// - Returns: The parsed response of type T
    func executeStructuredWithAnthropicCaching<T: Codable>(
        systemContent: [AnthropicSystemBlock],
        userPrompt: String,
        modelId: String,
        responseType: T.Type,
        schema: [String: Any]
    ) async throws -> T {
        let start = ContinuousClock.now
        // Give structured output the model's full completion headroom so large
        // (schema-bounded) responses aren't truncated mid-JSON. Falls back to a
        // conservative floor only when OpenRouter doesn't expose the model's limit.
        let maxTokens = maxOutputTokens(forModel: modelId) ?? 4096
        let result = try await specializedAPIs.executeStructuredWithAnthropicCaching(
            systemContent: systemContent,
            userPrompt: userPrompt,
            modelId: modelId,
            responseType: responseType,
            schema: schema,
            maxTokens: maxTokens
        )
        LLMTranscriptLogger.logAnthropicCall(
            method: "executeStructuredWithAnthropicCaching", modelId: modelId,
            systemBlockCount: systemContent.count, userPrompt: userPrompt,
            response: String(describing: result), durationMs: elapsedMs(from: start)
        )
        return result
    }

    /// Execute a structured JSON request whose user content is arbitrary Anthropic content blocks.
    /// Supports document blocks (Files API or base64) with cache control so multiple analysis
    /// passes can share one cached document prefix.
    func executeStructuredWithAnthropicBlocks<T: Codable>(
        systemContent: [AnthropicSystemBlock],
        userBlocks: [AnthropicContentBlock],
        modelId: String,
        responseType: T.Type,
        schema: [String: Any],
        maxTokens: Int = 8192
    ) async throws -> T {
        let start = ContinuousClock.now
        let result = try await specializedAPIs.executeStructuredWithAnthropicBlocks(
            systemContent: systemContent,
            userBlocks: userBlocks,
            modelId: modelId,
            responseType: responseType,
            schema: schema,
            maxTokens: maxTokens
        )
        LLMTranscriptLogger.logAnthropicCall(
            method: "executeStructuredWithAnthropicBlocks", modelId: modelId,
            systemBlockCount: systemContent.count, userPrompt: "[\(userBlocks.count) content blocks]",
            response: String(describing: result), durationMs: elapsedMs(from: start)
        )
        return result
    }

    // MARK: - Text-to-Speech (Specialized)

    func createTTSClient() -> TTSCapable {
        specializedAPIs.createTTSClient()
    }

    // MARK: - Transcript Timing

    private func elapsedMs(from start: ContinuousClock.Instant) -> Int {
        let elapsed = start.duration(to: .now)
        return Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
