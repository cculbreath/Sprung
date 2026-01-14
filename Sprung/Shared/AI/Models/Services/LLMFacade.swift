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
    private let llmService: OpenRouterServiceBackend
    private let openRouterService: OpenRouterService
    private var backendClients: [Backend: LLMClient] = [:]
    private var conversationServices: [Backend: LLMConversationService] = [:]

    // Extracted components
    private let streamingManager = LLMFacadeStreamingManager()
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
        conversationServices[.openRouter] = OpenRouterConversationService(service: llmService)
    }

    func registerClient(_ client: LLMClient, for backend: Backend) {
        backendClients[backend] = client
    }

    func registerConversationService(_ service: LLMConversationService, for backend: Backend) {
        conversationServices[backend] = service
    }

    func registerOpenAIService(_ service: OpenAIService) {
        specializedAPIs.registerOpenAIService(service)
    }

    func registerGoogleAIService(_ service: GoogleAIService) {
        specializedAPIs.registerGoogleAIService(service)
    }

    func registerAnthropicService(_ service: AnthropicService) {
        specializedAPIs.registerAnthropicService(service)
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
        temperature: Double? = nil,
        backend: Backend = .openRouter
    ) async throws -> String {
        if backend == .openRouter {
            try await capabilityValidator.validate(modelId: modelId, requires: [])
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
            try await capabilityValidator.validate(modelId: modelId, requires: [.vision])
            return try await client.executeTextWithImages(prompt: prompt, modelId: modelId, images: images, temperature: temperature)
        }
        let altClient = try resolveClient(for: backend)
        return try await altClient.executeTextWithImages(prompt: prompt, modelId: modelId, images: images, temperature: temperature)
    }

    // MARK: - Structured Execution

    func executeStructured<T: Codable & Sendable>(
        prompt: String,
        modelId: String,
        as type: T.Type,
        temperature: Double? = nil,
        backend: Backend = .openRouter
    ) async throws -> T {
        if backend == .openRouter {
            try await capabilityValidator.validate(modelId: modelId, requires: [.structuredOutput])
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
            try await capabilityValidator.validate(modelId: modelId, requires: [.vision, .structuredOutput])
            return try await client.executeStructuredWithImages(prompt: prompt, modelId: modelId, images: images, as: type, temperature: temperature)
        }
        let altClient = try resolveClient(for: backend)
        return try await altClient.executeStructuredWithImages(prompt: prompt, modelId: modelId, images: images, as: type, temperature: temperature)
    }

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
            try await capabilityValidator.validate(modelId: modelId, requires: [.structuredOutput])
            return try await client.executeStructuredWithSchema(prompt: prompt, modelId: modelId, as: type, schema: schema, schemaName: schemaName, temperature: temperature)
        }
        let altClient = try resolveClient(for: backend)
        return try await altClient.executeStructuredWithSchema(prompt: prompt, modelId: modelId, as: type, schema: schema, schemaName: schemaName, temperature: temperature)
    }

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
            let jsonString = try await specializedAPIs.generateStructuredJSON(
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
            try await capabilityValidator.validate(modelId: modelId, requires: required)
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
        try await capabilityValidator.validate(modelId: modelId, requires: required)

        let sourceStream = llmService.executeStructuredStreaming(
            prompt: prompt,
            modelId: modelId,
            responseType: type,
            temperature: temperature,
            reasoning: reasoning,
            jsonSchema: jsonSchema
        )
        return streamingManager.makeStreamingHandle(conversationId: nil, sourceStream: sourceStream)
    }
    // MARK: - Conversation Streaming

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
            try await capabilityValidator.validate(modelId: modelId, requires: required)
            let (conversationId, sourceStream) = try await llmService.startConversationStreaming(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                temperature: temperature,
                reasoning: reasoning,
                jsonSchema: jsonSchema
            )
            return streamingManager.makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
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
            return streamingManager.makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
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
            try await capabilityValidator.validate(modelId: modelId, requires: required)
            let sourceStream = llmService.continueConversationStreaming(
                userMessage: userMessage,
                modelId: modelId,
                conversationId: conversationId,
                images: images,
                temperature: temperature,
                reasoning: reasoning,
                jsonSchema: jsonSchema
            )
            return streamingManager.makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
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
            return streamingManager.makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        }
        throw LLMError.clientError("Streaming conversations are not supported for backend \(backend.displayName)")
    }

    // MARK: - Conversation (Non-Streaming)

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
            try await capabilityValidator.validate(modelId: modelId, requires: required)
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
        try await capabilityValidator.validate(modelId: modelId, requires: required)
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
            try await capabilityValidator.validate(modelId: modelId, requires: [])
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
        streamingManager.cancelAllTasks()
        llmService.cancelAllRequests()
    }

    // MARK: - Tool Calling (for Agent Workflows)

    func executeWithTools(
        messages: [ChatCompletionParameters.Message],
        tools: [ChatCompletionParameters.Tool],
        toolChoice: ToolChoice? = .auto,
        modelId: String,
        temperature: Double? = nil,
        reasoningEffort: String? = nil,
        maxTokens: Int? = nil,
        useFullContextLength: Bool = false,
        backend: Backend = .openRouter
    ) async throws -> ChatCompletionObject {
        if backend == .openRouter {
            try await capabilityValidator.validate(modelId: modelId, requires: [])

            // Determine maxTokens: explicit value takes precedence, then fullMax lookup
            var resolvedMaxTokens = maxTokens
            if resolvedMaxTokens == nil && useFullContextLength {
                resolvedMaxTokens = openRouterService.findModel(id: modelId)?.contextLength
                if let tokens = resolvedMaxTokens {
                    Logger.debug("🔧 Using full context length for \(modelId): \(tokens) tokens", category: .ai)
                }
            }

            let parameters = LLMRequestBuilder.buildToolRequest(
                messages: messages,
                modelId: modelId,
                tools: tools,
                toolChoice: toolChoice,
                temperature: temperature ?? 0.7,
                reasoningEffort: reasoningEffort,
                maxTokens: resolvedMaxTokens
            )
            return try await llmService.executeToolRequest(parameters: parameters)
        }

        // For OpenAI backend, delegate to specialized handler
        return try await executeToolsViaOpenAI(
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            modelId: modelId,
            temperature: temperature,
            reasoningEffort: reasoningEffort
        )
    }

    private func executeToolsViaOpenAI(
        messages: [ChatCompletionParameters.Message],
        tools: [ChatCompletionParameters.Tool],
        toolChoice: ToolChoice?,
        modelId: String,
        temperature: Double?,
        reasoningEffort: String?
    ) async throws -> ChatCompletionObject {
        let openAIModelId = modelId.hasPrefix("openai/") ? String(modelId.dropFirst(7)) : modelId

        var inputItems: [InputItem] = []
        for message in messages {
            let role: String
            switch message.role {
            case "system": role = "developer"
            case "user": role = "user"
            case "assistant": role = "assistant"
            case "tool": role = "user"
            default: role = "user"
            }

            switch message.content {
            case .text(let text):
                inputItems.append(.message(InputMessage(role: role, content: .text(text))))
            case .contentArray:
                break
            }
        }

        let responsesTools: [Tool] = tools.compactMap { chatTool in
            let function = chatTool.function
            return Tool.function(Tool.FunctionTool(
                name: function.name,
                parameters: function.parameters ?? JSONSchema(type: .object),
                strict: function.strict,
                description: function.description
            ))
        }

        let responsesToolChoice: ToolChoiceMode?
        if let choice = toolChoice {
            switch choice {
            case .auto: responsesToolChoice = .auto
            case .none: responsesToolChoice = ToolChoiceMode.none
            case .required: responsesToolChoice = .required
            case .function(_, let name): responsesToolChoice = .functionTool(FunctionTool(name: name))
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

        let stream = try await specializedAPIs.responseCreateStream(parameters: parameters)
        var finalResponse: ResponseModel?
        for try await event in stream {
            if case .responseCompleted(let completed) = event {
                finalResponse = completed.response
            }
        }
        guard let response = finalResponse else {
            throw LLMError.clientError("No response received from OpenAI")
        }
        return try convertResponseToCompletion(response)
    }

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

        var messageDict: [String: Any] = ["role": "assistant"]
        if let content = content { messageDict["content"] = content }
        if !toolCallsArray.isEmpty { messageDict["tool_calls"] = toolCallsArray }

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
        try await specializedAPIs.executeWithWebSearch(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            reasoningEffort: reasoningEffort,
            webSearchLocation: webSearchLocation,
            onWebSearching: onWebSearching,
            onWebSearchComplete: onWebSearchComplete,
            onTextDelta: onTextDelta
        )
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

    func anthropicListModels() async throws -> AnthropicModelsResponse {
        try await specializedAPIs.anthropicListModels()
    }

    /// Execute a text prompt via direct Anthropic API with prompt caching.
    /// The system content blocks can include cache_control for server-side caching.
    /// - Parameters:
    ///   - systemContent: Array of system content blocks (some may have cache_control)
    ///   - userPrompt: The user's request/prompt
    ///   - modelId: Anthropic model ID (e.g., "claude-sonnet-4-20250514")
    ///   - temperature: Generation temperature
    /// - Returns: The assistant's text response
    func executeTextWithAnthropicCaching(
        systemContent: [AnthropicSystemBlock],
        userPrompt: String,
        modelId: String,
        temperature: Double? = nil
    ) async throws -> String {
        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: [.user(userPrompt)],
            system: .blocks(systemContent),
            maxTokens: 4096,
            stream: false,
            temperature: temperature ?? 0.7
        )

        let stream = try await specializedAPIs.anthropicMessagesStream(parameters: parameters)
        var resultText = ""

        for try await event in stream {
            switch event {
            case .contentBlockDelta(let delta):
                if case .textDelta(let text) = delta.delta {
                    resultText += text
                }
            case .messageStop:
                break
            default:
                break
            }
        }

        Logger.info("✅ Anthropic cached request completed: \(resultText.count) chars", category: .ai)
        return resultText
    }

    /// Execute a structured JSON request via direct Anthropic API with prompt caching and schema enforcement.
    /// Uses Anthropic's structured outputs feature with the output_format parameter.
    /// - Parameters:
    ///   - systemContent: Array of system content blocks (some may have cache_control)
    ///   - userPrompt: The user's request/prompt
    ///   - modelId: Anthropic model ID (e.g., "claude-sonnet-4-20250514")
    ///   - responseType: The expected response type
    ///   - schema: JSON schema dictionary for the structured output
    ///   - schemaName: Name for the schema (used in Anthropic's output_format)
    ///   - temperature: Generation temperature
    /// - Returns: The parsed response of type T
    func executeStructuredWithAnthropicCaching<T: Codable>(
        systemContent: [AnthropicSystemBlock],
        userPrompt: String,
        modelId: String,
        responseType: T.Type,
        schema: [String: Any],
        schemaName: String,
        temperature: Double? = nil
    ) async throws -> T {
        let outputFormat = AnthropicOutputFormat.schema(
            name: schemaName,
            schema: schema
        )

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: [.user(userPrompt)],
            system: .blocks(systemContent),
            maxTokens: 4096,
            stream: false,
            temperature: temperature ?? 0.7,
            outputFormat: outputFormat
        )

        let stream = try await specializedAPIs.anthropicMessagesStream(parameters: parameters)
        var resultText = ""

        for try await event in stream {
            switch event {
            case .contentBlockDelta(let delta):
                if case .textDelta(let text) = delta.delta {
                    resultText += text
                }
            case .messageStop:
                break
            default:
                break
            }
        }

        Logger.info("✅ Anthropic structured request completed: \(resultText.count) chars", category: .ai)

        // Parse the response as the expected type
        guard let data = resultText.data(using: .utf8) else {
            throw LLMError.clientError("Failed to convert Anthropic response to data")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Logger.warning("Failed to parse Anthropic structured response as \(T.self): \(error)", category: .ai)
            Logger.debug("Response was: \(resultText.prefix(500))", category: .ai)
            throw LLMError.clientError("Failed to parse structured response: \(error.localizedDescription)")
        }
    }

    // MARK: - Gemini Document Extraction (Specialized)

    func generateFromPDF(
        pdfData: Data,
        filename: String,
        prompt: String,
        modelId: String? = nil,
        maxOutputTokens: Int = 65536
    ) async throws -> (text: String, tokenUsage: GoogleAIService.GeminiTokenUsage?) {
        try await specializedAPIs.generateFromPDF(
            pdfData: pdfData,
            filename: filename,
            prompt: prompt,
            modelId: modelId,
            maxOutputTokens: maxOutputTokens
        )
    }

    func generateDocumentSummary(
        content: String,
        filename: String,
        modelId: String? = nil
    ) async throws -> DocumentSummary {
        try await specializedAPIs.generateDocumentSummary(
            content: content,
            filename: filename,
            modelId: modelId
        )
    }

    func analyzeImagesWithGemini(
        images: [Data],
        prompt: String,
        modelId: String? = nil
    ) async throws -> String {
        try await specializedAPIs.analyzeImagesWithGemini(
            images: images,
            prompt: prompt,
            modelId: modelId
        )
    }

    func analyzeImagesWithGeminiStructured(
        images: [Data],
        prompt: String,
        jsonSchema: [String: Any],
        modelId: String? = nil
    ) async throws -> String {
        try await specializedAPIs.analyzeImagesWithGeminiStructured(
            images: images,
            prompt: prompt,
            jsonSchema: jsonSchema,
            modelId: modelId
        )
    }

    // MARK: - Text-to-Speech (Specialized)

    func createTTSClient() -> TTSCapable {
        specializedAPIs.createTTSClient()
    }
}
