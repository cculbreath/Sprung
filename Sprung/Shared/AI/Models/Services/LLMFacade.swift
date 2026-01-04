//
//  LLMFacade.swift
//  Sprung
//
//  A thin facade over LLMClient that centralizes capability gating (future) and
//  exposes a stable surface to callers.
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
/// ## Internal Types
/// Types prefixed with `_` (e.g., `_LLMRequestExecutor`, `_LLMService`) are
/// implementation details and should not be used directly outside the LLM layer.
/// They may change without notice.
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
        case gemini
        case anthropic
        var displayName: String {
            switch self {
            case .openRouter: return "OpenRouter"
            case .openAI: return "OpenAI"
            case .gemini: return "Gemini"
            case .anthropic: return "Anthropic"
            }
        }
    }
    private let client: LLMClient
    private let llmService: OpenRouterServiceBackend // temporary bridge for conversation flows
    private let openRouterService: OpenRouterService
    private let enabledLLMStore: EnabledLLMStore?
    private let modelValidationService: ModelValidationService
    private var activeStreamingTasks: [UUID: Task<Void, Never>] = [:]
    private var backendClients: [Backend: LLMClient] = [:]
    private var conversationServices: [Backend: LLMConversationService] = [:]

    // Direct service references for specialized APIs
    private var openAIService: OpenAIService?
    private var googleAIService: GoogleAIService?
    private var anthropicService: AnthropicService?
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
        self.enabledLLMStore = enabledLLMStore
        self.modelValidationService = modelValidationService
        backendClients[.openRouter] = client
        conversationServices[.openRouter] = OpenRouterConversationService(service: llmService)
    }
    func registerClient(_ client: LLMClient, for backend: Backend) {
        backendClients[backend] = client
    }
    func registerConversationService(_ service: LLMConversationService, for backend: Backend) {
        conversationServices[backend] = service
    }

    func registerOpenAIService(_ service: OpenAIService) {
        self.openAIService = service
    }

    func registerGoogleAIService(_ service: GoogleAIService) {
        self.googleAIService = service
    }

    func registerAnthropicService(_ service: AnthropicService) {
        self.anthropicService = service
    }
    private func resolveClient(for backend: Backend) throws -> LLMClient {
        guard let resolved = backendClients[backend] else {
            throw LLMError.clientError("Backend \(backend.displayName) is not configured")
        }
        return resolved
    }
    private func registerStreamingTask(_ task: Task<Void, Never>, for handleId: UUID) {
        activeStreamingTasks[handleId]?.cancel()
        activeStreamingTasks[handleId] = task
    }
    private func cancelStreaming(handleId: UUID) {
        if let task = activeStreamingTasks.removeValue(forKey: handleId) {
            task.cancel()
        }
    }
    private func makeStreamingHandle(
        conversationId: UUID?,
        sourceStream: AsyncThrowingStream<LLMStreamChunkDTO, Error>
    ) -> LLMStreamingHandle {
        let handleId = UUID()
        let stream = AsyncThrowingStream<LLMStreamChunkDTO, Error> { continuation in
            let task = Task {
                defer {
                    Task { @MainActor in
                        self.activeStreamingTasks.removeValue(forKey: handleId)
                    }
                }
                do {
                    for try await chunk in sourceStream {
                        if Task.isCancelled { break }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            registerStreamingTask(task, for: handleId)
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.cancelStreaming(handleId: handleId)
                }
            }
        }
        let cancelClosure: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.cancelStreaming(handleId: handleId)
            }
        }
        return LLMStreamingHandle(conversationId: conversationId, stream: stream, cancel: cancelClosure)
    }
    // MARK: - Capability Validation
    private func enabledModelRecord(for modelId: String) -> EnabledLLM? {
        enabledLLMStore?.enabledModels.first(where: { $0.modelId == modelId })
    }
    private func supports(_ capability: ModelCapability, metadata: OpenRouterModel?, record: EnabledLLM?) -> Bool {
        switch capability {
        case .vision:
            if let supports = record?.supportsImages { return supports }
            return metadata?.supportsImages ?? false
        case .structuredOutput:
            if let supportsSchema = record?.supportsJSONSchema { return supportsSchema }
            if let supportsStructured = record?.supportsStructuredOutput { return supportsStructured }
            return metadata?.supportsStructuredOutput ?? false
        case .reasoning:
            if let supportsReasoning = record?.supportsReasoning { return supportsReasoning }
            return metadata?.supportsReasoning ?? false
        case .textOnly:
            let isTextOnly = record?.isTextToText ?? metadata?.isTextToText ?? true
            let supportsVision = record?.supportsImages ?? metadata?.supportsImages ?? false
            return isTextOnly && !supportsVision
        }
    }
    private func missingCapabilities(
        metadata: OpenRouterModel?,
        record: EnabledLLM?,
        requires capabilities: [ModelCapability]
    ) -> [ModelCapability] {
        capabilities.filter { !supports($0, metadata: metadata, record: record) }
    }
    private func validate(modelId: String, requires capabilities: [ModelCapability]) async throws {
        if let store = enabledLLMStore, !store.isModelEnabled(modelId) {
            throw LLMError.clientError("Model '\(modelId)' is disabled. Enable it in AI Settings before use.")
        }
        let metadata = openRouterService.findModel(id: modelId)
        let record = enabledModelRecord(for: modelId)
        guard metadata != nil || record != nil else {
            throw LLMError.clientError("Model '\(modelId)' not found")
        }
        var missing = missingCapabilities(metadata: metadata, record: record, requires: capabilities)
        guard !missing.isEmpty else { return }
        // Attempt to refresh capabilities using validation service
        let validationResult = await modelValidationService.validateModel(modelId)
        if let capabilitiesInfo = validationResult.actualCapabilities {
            let supportsSchema = capabilitiesInfo.supportsStructuredOutputs || capabilitiesInfo.supportsResponseFormat
            let supportsReasoning = capabilitiesInfo.supportedParameters.contains { $0.lowercased().contains("reasoning") }
            enabledLLMStore?.updateModelCapabilities(
                modelId: modelId,
                supportsJSONSchema: supportsSchema,
                supportsImages: capabilitiesInfo.supportsImages,
                supportsReasoning: supportsReasoning
            )
        }
        let refreshedRecord = enabledModelRecord(for: modelId)
        let refreshedMetadata = openRouterService.findModel(id: modelId)
        missing = missingCapabilities(metadata: refreshedMetadata, record: refreshedRecord, requires: capabilities)
        guard missing.isEmpty else {
            let missingNames = missing.map { $0.displayName }.joined(separator: ", ")
            if let errorMessage = validationResult.error {
                throw LLMError.clientError("Model '\(modelId)' validation failed: \(errorMessage)")
            } else {
                throw LLMError.clientError("Model '\(modelId)' does not support: \(missingNames)")
            }
        }
    }
    // Text
    func executeText(
        prompt: String,
        modelId: String,
        temperature: Double? = nil,
        backend: Backend = .openRouter
    ) async throws -> String {
        if backend == .openRouter {
            try await validate(modelId: modelId, requires: [])
            return try await client.executeText(prompt: prompt, modelId: modelId, temperature: temperature)
        }
        let altClient = try resolveClient(for: backend)
        return try await altClient.executeText(prompt: prompt, modelId: modelId, temperature: temperature)
    }
    func executeTextWithImages(
        prompt: String,
        modelId: String,
        images: [Data],
        temperature: Double? = nil,
        backend: Backend = .openRouter
    ) async throws -> String {
        if backend == .openRouter {
            try await validate(modelId: modelId, requires: [.vision])
            return try await client.executeTextWithImages(prompt: prompt, modelId: modelId, images: images, temperature: temperature)
        }
        let altClient = try resolveClient(for: backend)
        return try await altClient.executeTextWithImages(prompt: prompt, modelId: modelId, images: images, temperature: temperature)
    }
    // Structured
    func executeStructured<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        temperature: Double? = nil,
        backend: Backend = .openRouter
    ) async throws -> T {
        if backend == .openRouter {
            try await validate(modelId: modelId, requires: [.structuredOutput])
            return try await client.executeStructured(prompt: prompt, modelId: modelId, as: type, temperature: temperature)
        }
        let altClient = try resolveClient(for: backend)
        return try await altClient.executeStructured(prompt: prompt, modelId: modelId, as: type, temperature: temperature)
    }
    func executeStructuredWithImages<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        images: [Data],
        as type: T.Type,
        temperature: Double? = nil,
        backend: Backend = .openRouter
    ) async throws -> T {
        if backend == .openRouter {
            try await validate(modelId: modelId, requires: [.vision, .structuredOutput])
            return try await client.executeStructuredWithImages(prompt: prompt, modelId: modelId, images: images, as: type, temperature: temperature)
        }
        let altClient = try resolveClient(for: backend)
        return try await altClient.executeStructuredWithImages(prompt: prompt, modelId: modelId, images: images, as: type, temperature: temperature)
    }

    /// Execute a structured request with an explicit JSON schema.
    /// Use this for backends (like OpenAI Responses API) that require a schema for structured output.
    func executeStructuredWithSchema<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        schema: JSONSchema,
        schemaName: String,
        temperature: Double? = nil,
        backend: Backend = .openRouter
    ) async throws -> T {
        if backend == .openRouter {
            try await validate(modelId: modelId, requires: [.structuredOutput])
            return try await client.executeStructuredWithSchema(prompt: prompt, modelId: modelId, as: type, schema: schema, schemaName: schemaName, temperature: temperature)
        }
        let altClient = try resolveClient(for: backend)
        return try await altClient.executeStructuredWithSchema(prompt: prompt, modelId: modelId, as: type, schema: schema, schemaName: schemaName, temperature: temperature)
    }

    /// Execute a structured request with a dictionary-based JSON schema.
    /// This is the **unified entry point** for structured output across all backends.
    ///
    /// - Parameters:
    ///   - prompt: The prompt text
    ///   - modelId: Model identifier (format depends on backend)
    ///   - type: The Codable type to decode the response into
    ///   - schema: JSON Schema as a dictionary (converted internally for each backend)
    ///   - schemaName: Name for the schema (used by some backends)
    ///   - temperature: Optional temperature override
    ///   - maxOutputTokens: Maximum output tokens (used by Gemini backend)
    ///   - keyDecodingStrategy: JSON key decoding strategy (default: `.useDefaultKeys`)
    ///   - backend: Which LLM backend to use
    /// - Returns: Decoded response of type T
    func executeStructuredWithDictionarySchema<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        schema: [String: Any],
        schemaName: String,
        temperature: Double? = nil,
        maxOutputTokens: Int = 32768,
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        backend: Backend = .openRouter
    ) async throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = keyDecodingStrategy

        switch backend {
        case .gemini:
            // Use native Gemini API for structured output
            guard let service = googleAIService else {
                throw LLMError.clientError("Google AI service is not configured. Call registerGoogleAIService first.")
            }
            let jsonString = try await service.generateStructuredJSON(
                prompt: prompt,
                modelId: modelId,
                temperature: temperature ?? 0.2,
                maxOutputTokens: maxOutputTokens,
                jsonSchema: schema
            )
            guard let data = jsonString.data(using: .utf8) else {
                throw LLMError.clientError("Failed to convert Gemini response to data")
            }
            return try decoder.decode(T.self, from: data)

        case .openRouter, .openAI, .anthropic:
            // Convert dictionary schema to JSONSchema and use OpenRouter/OpenAI path
            let jsonSchema = try JSONSchema.from(dictionary: schema)
            return try await executeStructuredWithSchema(
                prompt: prompt,
                modelId: modelId,
                as: type,
                schema: jsonSchema,
                schemaName: schemaName,
                temperature: temperature,
                backend: backend
            )
        }
    }

    func executeFlexibleJSON<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil,
        backend: Backend = .openRouter
    ) async throws -> T {
        let required: [ModelCapability] = jsonSchema == nil ? [] : [.structuredOutput]
        if backend == .openRouter {
            try await validate(modelId: modelId, requires: required)
            return try await llmService.executeFlexibleJSON(
                prompt: prompt,
                modelId: modelId,
                responseType: type,
                temperature: temperature,
                jsonSchema: jsonSchema
            )
        }
        let altClient = try resolveClient(for: backend)
        return try await altClient.executeStructured(
            prompt: prompt,
            modelId: modelId,
            as: type,
            temperature: temperature
        )
    }
    func executeStructuredStreaming<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil,
        backend: Backend = .openRouter
    ) async throws -> LLMStreamingHandle {
        guard backend == .openRouter else {
            throw LLMError.clientError("Structured streaming is not supported for backend \(backend.displayName)")
        }
        var required: [ModelCapability] = [.structuredOutput]
        if reasoning != nil { required.append(.reasoning) }
        try await validate(modelId: modelId, requires: required)
        let handleId = UUID()
        let sourceStream = llmService.executeStructuredStreaming(
            prompt: prompt,
            modelId: modelId,
            responseType: type,
            temperature: temperature,
            reasoning: reasoning,
            jsonSchema: jsonSchema
        )
        let stream = AsyncThrowingStream<LLMStreamChunkDTO, Error> { continuation in
            let task = Task {
                defer {
                    _ = Task { @MainActor in
                        self.activeStreamingTasks.removeValue(forKey: handleId)
                    }
                }
                do {
                    for try await chunk in sourceStream {
                        if Task.isCancelled { break }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            registerStreamingTask(task, for: handleId)
        }
        let cancelClosure: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.cancelStreaming(handleId: handleId)
            }
        }
        return LLMStreamingHandle(conversationId: nil, stream: stream, cancel: cancelClosure)
    }
    // MARK: - Conversation (temporary pass-through to LLMService)
    func startConversationStreaming(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> LLMStreamingHandle {
        try await startConversationStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature,
            reasoning: reasoning,
            jsonSchema: jsonSchema,
            backend: .openRouter
        )
    }
    func startConversationStreaming(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil,
        backend: Backend,
        images: [Data] = []
    ) async throws -> LLMStreamingHandle {
        if backend == .openRouter {
            var required: [ModelCapability] = []
            if reasoning != nil { required.append(.reasoning) }
            if jsonSchema != nil { required.append(.structuredOutput) }
            try await validate(modelId: modelId, requires: required)
            let (conversationId, sourceStream) = try await llmService.startConversationStreaming(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                temperature: temperature,
                reasoning: reasoning,
                jsonSchema: jsonSchema
            )
            return makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        }
        if backend == .openAI {
            guard reasoning == nil else {
                throw LLMError.clientError("Reasoning mode is not supported for OpenAI Responses streaming")
            }
            guard jsonSchema == nil else {
                throw LLMError.clientError("Structured outputs are not supported for OpenAI Responses streaming")
            }
            guard let service = conversationServices[.openAI] as? LLMStreamingConversationService else {
                throw LLMError.clientError("OpenAI streaming conversation service is unavailable")
            }
            let (conversationId, sourceStream) = try await service.startConversationStreaming(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                temperature: temperature,
                images: images
            )
            return makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        }
        throw LLMError.clientError("Streaming conversations are not supported for backend \(backend.displayName)")
    }
    func continueConversationStreaming(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data] = [],
        temperature: Double? = nil,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil,
        backend: Backend = .openRouter
    ) async throws -> LLMStreamingHandle {
        if backend == .openRouter {
            var required: [ModelCapability] = images.isEmpty ? [] : [.vision]
            if reasoning != nil { required.append(.reasoning) }
            if jsonSchema != nil { required.append(.structuredOutput) }
            try await validate(modelId: modelId, requires: required)
            let sourceStream = llmService.continueConversationStreaming(
                userMessage: userMessage,
                modelId: modelId,
                conversationId: conversationId,
                images: images,
                temperature: temperature,
                reasoning: reasoning,
                jsonSchema: jsonSchema
            )
            return makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        }
        if backend == .openAI {
            guard reasoning == nil else {
                throw LLMError.clientError("Reasoning mode is not supported for OpenAI Responses streaming")
            }
            guard jsonSchema == nil else {
                throw LLMError.clientError("Structured outputs are not supported for OpenAI Responses streaming")
            }
            guard let service = conversationServices[.openAI] as? LLMStreamingConversationService else {
                throw LLMError.clientError("OpenAI streaming conversation service is unavailable")
            }
            let sourceStream = try await service.continueConversationStreaming(
                userMessage: userMessage,
                modelId: modelId,
                conversationId: conversationId,
                images: images,
                temperature: temperature
            )
            return makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        }
        throw LLMError.clientError("Streaming conversations are not supported for backend \(backend.displayName)")
    }
    func continueConversation(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        images: [Data] = [],
        temperature: Double? = nil,
        backend: Backend = .openRouter
    ) async throws -> String {
        if backend == .openRouter {
            let required: [ModelCapability] = images.isEmpty ? [] : [.vision]
            try await validate(modelId: modelId, requires: required)
            return try await llmService.continueConversation(
                userMessage: userMessage,
                modelId: modelId,
                conversationId: conversationId,
                images: images,
                temperature: temperature
            )
        }
        guard let service = conversationServices[backend] else {
            throw LLMError.clientError("Selected backend does not support conversations")
        }
        return try await service.continueConversation(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            images: images,
            temperature: temperature
        )
    }
    func continueConversationStructured<T: Codable & Sendable>(
        userMessage: String,
        modelId: String,
        conversationId: UUID,
        as type: T.Type,
        images: [Data] = [],
        temperature: Double? = nil,
        jsonSchema: JSONSchema? = nil,
        backend: Backend = .openRouter
    ) async throws -> T {
        guard backend == .openRouter else {
            throw LLMError.clientError("Conversations are only supported via OpenRouter at this time")
        }
        var required: [ModelCapability] = [.structuredOutput]
        if !images.isEmpty { required.append(.vision) }
        try await validate(modelId: modelId, requires: required)
        return try await llmService.continueConversationStructured(
            userMessage: userMessage,
            modelId: modelId,
            conversationId: conversationId,
            responseType: type,
            images: images,
            temperature: temperature,
            jsonSchema: jsonSchema
        )
    }
    func startConversation(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        temperature: Double? = nil,
        backend: Backend = .openRouter
    ) async throws -> (UUID, String) {
        if backend == .openRouter {
            try await validate(modelId: modelId, requires: [])
            return try await llmService.startConversation(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                temperature: temperature
            )
        }
        guard let service = conversationServices[backend] else {
            throw LLMError.clientError("Selected backend does not support conversations")
        }
        return try await service.startConversation(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            temperature: temperature
        )
    }
    func cancelAllRequests() {
        for task in activeStreamingTasks.values {
            task.cancel()
        }
        activeStreamingTasks.removeAll()
        llmService.cancelAllRequests()
    }

    // MARK: - Tool Calling (for Agent Workflows)

    /// Execute a single turn of an agent conversation with tool calling support.
    /// Returns the raw ChatCompletionObject which includes tool calls if the model wants to use tools.
    ///
    /// Use this for multi-turn agent workflows where you need to handle tool calls yourself.
    /// The caller is responsible for:
    /// 1. Checking if `response.choices.first?.message?.toolCalls` is non-empty
    /// 2. Executing the tools locally
    /// 3. Building tool result messages and calling this method again
    ///
    /// - Parameters:
    ///   - messages: The conversation messages (system, user, assistant, tool)
    ///   - tools: The tools available to the model (use `ChatCompletionParameters.Tool`)
    ///   - toolChoice: Control which tool is called (auto, required, none, or specific function)
    ///   - modelId: The model to use (OpenRouter format, e.g., "openai/gpt-4o")
    ///   - temperature: Sampling temperature
    /// - Returns: The raw ChatCompletionObject containing the model's response and any tool calls
    func executeWithTools(
        messages: [ChatCompletionParameters.Message],
        tools: [ChatCompletionParameters.Tool],
        toolChoice: ToolChoice? = .auto,
        modelId: String,
        temperature: Double? = nil,
        reasoningEffort: String? = nil,
        backend: Backend = .openRouter
    ) async throws -> ChatCompletionObject {
        // For OpenRouter, use Chat Completions API
        if backend == .openRouter {
            try await validate(modelId: modelId, requires: [])

            let parameters = LLMRequestBuilder.buildToolRequest(
                messages: messages,
                modelId: modelId,
                tools: tools,
                toolChoice: toolChoice,
                temperature: temperature ?? 0.7,
                reasoningEffort: reasoningEffort
            )

            return try await llmService.executeToolRequest(parameters: parameters)
        }

        // For OpenAI, use Responses API with function tools
        guard let service = openAIService else {
            throw LLMError.clientError("OpenAI service is not configured")
        }

        // Strip OpenRouter prefix if present
        let openAIModelId = modelId.hasPrefix("openai/") ? String(modelId.dropFirst(7)) : modelId

        // Convert ChatCompletion messages to InputItems
        var inputItems: [InputItem] = []
        for message in messages {
            // Map ChatCompletion roles to OpenAI Responses API roles
            let role: String
            switch message.role {
            case "system": role = "developer"
            case "user": role = "user"
            case "assistant": role = "assistant"
            case "tool": role = "user"  // Tool results go as user messages in Responses API
            default: role = "user"
            }

            switch message.content {
            case .text(let text):
                inputItems.append(.message(InputMessage(role: role, content: .text(text))))
            case .contentArray:
                // Skip complex content for now
                break
            }
        }

        // Convert ChatCompletion tools to Responses API FunctionTools
        let responsesTools: [Tool] = tools.compactMap { chatTool in
            let function = chatTool.function
            return Tool.function(Tool.FunctionTool(
                name: function.name,
                parameters: function.parameters ?? JSONSchema(type: .object),
                strict: function.strict,
                description: function.description
            ))
        }

        // Convert toolChoice
        let responsesToolChoice: ToolChoiceMode?
        if let choice = toolChoice {
            switch choice {
            case .auto:
                responsesToolChoice = .auto
            case .none:
                responsesToolChoice = ToolChoiceMode.none
            case .required:
                responsesToolChoice = .required
            case .function(_, let name):
                // Force function by name - same pattern as Onboarding uses
                responsesToolChoice = .functionTool(FunctionTool(name: name))
            }
        } else {
            responsesToolChoice = nil
        }

        let reasoning: Reasoning? = reasoningEffort.map { Reasoning(effort: $0) }

        let parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(openAIModelId),
            reasoning: reasoning,
            store: true,
            temperature: temperature ?? 0.7,
            toolChoice: responsesToolChoice,
            tools: responsesTools.isEmpty ? nil : responsesTools
        )

        let response = try await service.responseCreate(parameters)

        // Convert ResponseModel back to ChatCompletionObject format via JSON
        return try convertResponseToCompletion(response)
    }

    /// Convert OpenAI Responses API ResponseModel to ChatCompletionObject format
    /// We use JSON encoding/decoding since ChatCompletionObject is Decodable-only
    private func convertResponseToCompletion(_ response: ResponseModel) throws -> ChatCompletionObject {
        var toolCallsArray: [[String: Any]] = []
        var content: String?

        for item in response.output {
            switch item {
            case .message(let message):
                for contentItem in message.content {
                    if case let .outputText(textOutput) = contentItem {
                        content = textOutput.text
                    }
                }
            case .functionCall(let functionCall):
                toolCallsArray.append([
                    "id": functionCall.callId,
                    "type": "function",
                    "function": [
                        "arguments": functionCall.arguments,
                        "name": functionCall.name
                    ]
                ])
            default:
                break
            }
        }

        // Build JSON structure matching ChatCompletionObject
        var messageDict: [String: Any] = [
            "role": "assistant"
        ]
        if let content = content {
            messageDict["content"] = content
        }
        if !toolCallsArray.isEmpty {
            messageDict["tool_calls"] = toolCallsArray
        }

        let json: [String: Any] = [
            "id": response.id,
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": response.model,
            "choices": [[
                "index": 0,
                "message": messageDict,
                "finish_reason": toolCallsArray.isEmpty ? "stop" : "tool_calls"
            ]]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(ChatCompletionObject.self, from: jsonData)
    }

    // MARK: - OpenAI Responses API with Web Search

    /// Execute a request using OpenAI Responses API with optional web search.
    /// This is used for discovery workflows that need real-time web data.
    ///
    /// - Parameters:
    ///   - systemPrompt: Developer/system instructions
    ///   - userMessage: The user's query
    ///   - modelId: OpenAI model ID (e.g., "gpt-4o" or "openai/gpt-4o" - prefix stripped automatically)
    ///   - reasoningEffort: Reasoning effort level ("low", "medium", "high")
    ///   - webSearchLocation: Optional location for web search (city name). If provided, enables web search tool.
    ///   - onWebSearching: Callback when web search starts
    ///   - onWebSearchComplete: Callback when web search completes
    ///   - onReasoningDelta: Callback for reasoning/output text deltas
    /// - Returns: The final response text
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
        guard let service = openAIService else {
            throw LLMError.clientError("OpenAI service is not configured. Call registerOpenAIService first.")
        }

        // Strip OpenRouter prefix if present
        let openAIModelId = modelId.hasPrefix("openai/") ? String(modelId.dropFirst(7)) : modelId

        let inputItems: [InputItem] = [
            .message(InputMessage(role: "developer", content: .text(systemPrompt))),
            .message(InputMessage(role: "user", content: .text(userMessage)))
        ]

        let reasoning: Reasoning? = reasoningEffort.map { Reasoning(effort: $0) }

        // Configure web search tool if location provided
        var tools: [Tool]?
        if let location = webSearchLocation {
            let webSearchTool = Tool.webSearch(Tool.WebSearchTool(
                type: .webSearch,
                userLocation: Tool.UserLocation(city: location, country: "US")
            ))
            tools = [webSearchTool]
        }

        let parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(openAIModelId),
            reasoning: reasoning,
            store: true,
            stream: true,
            toolChoice: tools != nil ? .auto : nil,
            tools: tools
        )

        Logger.info("🌐 LLMFacade.executeWithWebSearch (model: \(openAIModelId), webSearch: \(webSearchLocation != nil))", category: .ai)

        var finalResponse: ResponseModel?
        let stream = try await service.responseCreateStream(parameters)

        for try await event in stream {
            switch event {
            case .responseCompleted(let completed):
                finalResponse = completed.response
            case .webSearchCallSearching:
                await onWebSearching?()
            case .webSearchCallCompleted:
                await onWebSearchComplete?()
            case .outputTextDelta(let delta):
                await onTextDelta?(delta.delta)
            case .reasoningSummaryTextDelta(let delta):
                await onTextDelta?(delta.delta)
            default:
                break
            }
        }

        guard let response = finalResponse,
              let outputText = extractResponseText(from: response) else {
            throw LLMError.clientError("No response received from OpenAI")
        }

        Logger.info("✅ LLMFacade.executeWithWebSearch returned \(outputText.count) chars", category: .ai)
        return outputText
    }

    private func extractResponseText(from response: ResponseModel) -> String? {
        if let text = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
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

    // MARK: - Raw OpenAI Responses API Stream

    /// Execute an OpenAI Responses API request and return the raw stream.
    /// This is used by orchestration layers (like Onboarding) that need to process
    /// stream events themselves while still using LLMFacade for service management.
    ///
    /// - Parameter parameters: The ModelResponseParameter for the request
    /// - Returns: AsyncThrowingStream of ResponseStreamEvent events
    func responseCreateStream(
        parameters: ModelResponseParameter
    ) async throws -> AsyncThrowingStream<ResponseStreamEvent, Error> {
        guard let service = openAIService else {
            throw LLMError.clientError("OpenAI service is not configured. Call registerOpenAIService first.")
        }
        return try await service.responseCreateStream(parameters)
    }

    // MARK: - Anthropic Messages API Stream

    /// Execute an Anthropic Messages API request and return the raw stream.
    /// This is used by orchestration layers (like Onboarding) that need to process
    /// stream events themselves while still using LLMFacade for service management.
    ///
    /// - Parameter parameters: The AnthropicMessageParameter for the request
    /// - Returns: AsyncThrowingStream of AnthropicStreamEvent events
    func anthropicMessagesStream(
        parameters: AnthropicMessageParameter
    ) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        guard let service = anthropicService else {
            throw LLMError.clientError("Anthropic service is not configured. Call registerAnthropicService first.")
        }
        return try await service.messagesStream(parameters: parameters)
    }

    /// List available Anthropic models.
    func anthropicListModels() async throws -> AnthropicModelsResponse {
        guard let service = anthropicService else {
            throw LLMError.clientError("Anthropic service is not configured. Call registerAnthropicService first.")
        }
        return try await service.listModels()
    }

    // MARK: - Gemini Document Extraction

    /// Generate text from a PDF using Gemini vision.
    /// Used for vision-based text extraction when PDFKit fails on complex fonts.
    ///
    /// - Parameters:
    ///   - pdfData: The PDF file data
    ///   - filename: Display name for the file
    ///   - prompt: The extraction prompt
    ///   - modelId: Gemini model ID (uses default PDF extraction model if nil)
    ///   - maxOutputTokens: Maximum output tokens (default 65536)
    /// - Returns: Tuple of (extracted text, tokenUsage)
    func generateFromPDF(
        pdfData: Data,
        filename: String,
        prompt: String,
        modelId: String? = nil,
        maxOutputTokens: Int = 65536
    ) async throws -> (text: String, tokenUsage: GoogleAIService.GeminiTokenUsage?) {
        guard let service = googleAIService else {
            throw LLMError.clientError("Google AI service is not configured. Call registerGoogleAIService first.")
        }

        // Use configured model or default
        let effectiveModelId = modelId ?? UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId") ?? DefaultModels.gemini

        return try await service.generateFromPDF(
            pdfData: pdfData,
            filename: filename,
            prompt: prompt,
            modelId: effectiveModelId,
            maxOutputTokens: maxOutputTokens
        )
    }

    /// Generate a structured summary from document content using Gemini.
    /// Uses Gemini Flash-Lite for cost efficiency.
    ///
    /// - Parameters:
    ///   - content: The extracted document text
    ///   - filename: The document filename
    ///   - modelId: Gemini model ID (uses default if nil)
    /// - Returns: Structured DocumentSummary
    func generateDocumentSummary(
        content: String,
        filename: String,
        modelId: String? = nil
    ) async throws -> DocumentSummary {
        guard let service = googleAIService else {
            throw LLMError.clientError("Google AI service is not configured. Call registerGoogleAIService first.")
        }
        return try await service.generateSummary(
            content: content,
            filename: filename,
            modelId: modelId
        )
    }

    /// Analyze images using Gemini's vision capabilities.
    /// Used for PDF extraction quality judgment and vision-based text extraction.
    ///
    /// - Parameters:
    ///   - images: Array of image data (JPEG, PNG, WebP, HEIC, HEIF supported)
    ///   - prompt: The analysis prompt
    ///   - modelId: Gemini model ID (uses PDF extraction model setting if nil)
    /// - Returns: Text response from the model
    func analyzeImagesWithGemini(
        images: [Data],
        prompt: String,
        modelId: String? = nil
    ) async throws -> String {
        guard let service = googleAIService else {
            throw LLMError.clientError("Google AI service is not configured. Call registerGoogleAIService first.")
        }
        return try await service.analyzeImages(
            images: images,
            prompt: prompt,
            modelId: modelId
        )
    }

    /// Analyze images with Gemini using structured JSON output
    func analyzeImagesWithGeminiStructured(
        images: [Data],
        prompt: String,
        jsonSchema: [String: Any],
        modelId: String? = nil
    ) async throws -> String {
        guard let service = googleAIService else {
            throw LLMError.clientError("Google AI service is not configured. Call registerGoogleAIService first.")
        }
        return try await service.analyzeImagesStructured(
            images: images,
            prompt: prompt,
            jsonSchema: jsonSchema,
            modelId: modelId
        )
    }

    // MARK: - Text-to-Speech

    /// Creates a TTS-capable client using the registered OpenAI service.
    /// Returns UnavailableTTSClient if no OpenAI service is configured.
    ///
    /// - Returns: A TTSCapable client for text-to-speech operations
    func createTTSClient() -> TTSCapable {
        guard let service = openAIService else {
            Logger.warning("⚠️ No OpenAI service configured for TTS", category: .ai)
            return UnavailableTTSClient(errorMessage: "OpenAI service is not configured for TTS")
        }
        return OpenAIServiceTTSWrapper(service: service)
    }
}
