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
        let jsonString = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: result)
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
        let jsonString = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: result)
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
        let jsonString = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: result)
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
        backend: Backend = .openRouter,
        thinkingLevel: String? = nil
    ) async throws -> T {
        let start = ContinuousClock.now
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = keyDecodingStrategy

        let result: T
        switch backend {
        case .gemini:
            let jsonString = try await specializedAPIs.generateStructuredJSON(
                prompt: prompt,
                modelId: modelId,
                maxOutputTokens: maxOutputTokens,
                jsonSchema: schema,
                thinkingLevel: thinkingLevel
            )
            guard let data = jsonString.data(using: .utf8) else {
                throw LLMError.clientError("Failed to convert Gemini response to data")
            }
            result = try decoder.decode(T.self, from: data)

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
        let jsonString = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: result)
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
        let jsonString = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: result)
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
            reasoning: reasoning,
            jsonSchema: jsonSchema
        )
        LLMTranscriptLogger.logStreamingRequest(
            method: "executeStructuredStreaming", modelId: modelId,
            backend: backend.displayName, prompt: prompt
        )
        return streamingManager.makeStreamingHandle(conversationId: nil, sourceStream: sourceStream)
    }
    // MARK: - Conversation Streaming

    func startConversationStreaming(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil
    ) async throws -> LLMStreamingHandle {
        try await startConversationStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            reasoning: reasoning,
            jsonSchema: jsonSchema,
            backend: .openRouter
        )
    }

    func startConversationStreaming(
        systemPrompt: String? = nil,
        userMessage: String,
        modelId: String,
        reasoning: OpenRouterReasoning? = nil,
        jsonSchema: JSONSchema? = nil,
        backend: Backend,
        images: [Data] = []
    ) async throws -> LLMStreamingHandle {
        let handle: LLMStreamingHandle
        if backend == .openRouter {
            var required: [ModelCapability] = []
            if reasoning != nil { required.append(.reasoning) }
            if jsonSchema != nil { required.append(.structuredOutput) }
            try await capabilityValidator.validate(modelId: modelId, requires: required)
            let (conversationId, sourceStream) = try await llmService.startConversationStreaming(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                reasoning: reasoning,
                jsonSchema: jsonSchema
            )
            handle = streamingManager.makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        } else if backend == .openAI {
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
                images: images
            )
            handle = streamingManager.makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        } else {
            throw LLMError.clientError("Streaming conversations are not supported for backend \(backend.displayName)")
        }
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
        let handle: LLMStreamingHandle
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
                reasoning: reasoning,
                jsonSchema: jsonSchema
            )
            handle = streamingManager.makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        } else if backend == .openAI {
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
                images: images
            )
            handle = streamingManager.makeStreamingHandle(conversationId: conversationId, sourceStream: sourceStream)
        } else {
            throw LLMError.clientError("Streaming conversations are not supported for backend \(backend.displayName)")
        }
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
        let result: String
        if backend == .openRouter {
            let required: [ModelCapability] = images.isEmpty ? [] : [.vision]
            try await capabilityValidator.validate(modelId: modelId, requires: required)
            result = try await llmService.continueConversation(
                userMessage: userMessage,
                modelId: modelId,
                conversationId: conversationId,
                images: images
            )
        } else {
            guard let service = conversationServices[backend] else {
                throw LLMError.clientError("Selected backend does not support conversations")
            }
            result = try await service.continueConversation(
                userMessage: userMessage,
                modelId: modelId,
                conversationId: conversationId,
                images: images
            )
        }
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
        let jsonString = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: result)
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
        let result: (UUID, String)
        if backend == .openRouter {
            try await capabilityValidator.validate(modelId: modelId, requires: [])
            result = try await llmService.startConversation(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId
            )
        } else {
            guard let service = conversationServices[backend] else {
                throw LLMError.clientError("Selected backend does not support conversations")
            }
            result = try await service.startConversation(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId
            )
        }
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

    // MARK: - Tool Calling (for Agent Workflows)

    func executeWithTools(
        messages: [ChatCompletionParameters.Message],
        tools: [ChatCompletionParameters.Tool],
        toolChoice: ToolChoice? = .auto,
        modelId: String,
        reasoningEffort: String? = nil,
        maxTokens: Int? = nil,
        useFullContextLength: Bool = false,
        responseFormat: ResponseFormat? = nil,
        backend: Backend = .openRouter
    ) async throws -> ChatCompletionObject {
        let start = ContinuousClock.now
        let result: ChatCompletionObject
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
                reasoningEffort: reasoningEffort,
                maxTokens: resolvedMaxTokens,
                responseFormat: responseFormat
            )
            result = try await llmService.executeToolRequest(parameters: parameters)
        } else {
            // For OpenAI backend, delegate to specialized handler
            result = try await executeToolsViaOpenAI(
                messages: messages,
                tools: tools,
                toolChoice: toolChoice,
                modelId: modelId,
                reasoningEffort: reasoningEffort
            )
        }
        let toolNames = tools.map { $0.function.name }
        let firstChoice = result.choices?.first
        let content = firstChoice?.message?.content
        let responseToolCalls = firstChoice?.message?.toolCalls?.map {
            "\($0.function.name)(\($0.function.arguments.prefix(200)))"
        } ?? []
        LLMTranscriptLogger.logToolCall(
            method: "executeWithTools", modelId: modelId, backend: backend.displayName,
            messageCount: messages.count, toolNames: toolNames,
            responseContent: content, responseToolCalls: responseToolCalls, durationMs: elapsedMs(from: start)
        )
        return result
    }

    private func executeToolsViaOpenAI(
        messages: [ChatCompletionParameters.Message],
        tools: [ChatCompletionParameters.Tool],
        toolChoice: ToolChoice?,
        modelId: String,
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

    func anthropicListModels() async throws -> AnthropicModelsResponse {
        try await specializedAPIs.anthropicListModels()
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
        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: [.user(userPrompt)],
            system: .blocks(systemContent),
            maxTokens: 4096,
            stream: false
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
        LLMTranscriptLogger.logAnthropicCall(
            method: "executeTextWithAnthropicCaching", modelId: modelId,
            systemBlockCount: systemContent.count, userPrompt: userPrompt,
            response: resultText, durationMs: elapsedMs(from: start)
        )
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
    /// - Returns: The parsed response of type T
    func executeStructuredWithAnthropicCaching<T: Codable>(
        systemContent: [AnthropicSystemBlock],
        userPrompt: String,
        modelId: String,
        responseType: T.Type,
        schema: [String: Any]
    ) async throws -> T {
        let start = ContinuousClock.now
        let outputFormat = AnthropicOutputFormat.schema(
            schema: schema
        )

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: [.user(userPrompt)],
            system: .blocks(systemContent),
            maxTokens: 4096,
            stream: false,
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
        LLMTranscriptLogger.logAnthropicCall(
            method: "executeStructuredWithAnthropicCaching", modelId: modelId,
            systemBlockCount: systemContent.count, userPrompt: userPrompt,
            response: resultText, durationMs: elapsedMs(from: start)
        )

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
        let start = ContinuousClock.now
        let result = try await specializedAPIs.generateFromPDF(
            pdfData: pdfData,
            filename: filename,
            prompt: prompt,
            modelId: modelId,
            maxOutputTokens: maxOutputTokens
        )
        LLMTranscriptLogger.logGeminiCall(
            method: "generateFromPDF", modelId: modelId ?? "(default)",
            prompt: prompt, attachmentInfo: "PDF: \(filename) (\(pdfData.count) bytes)",
            response: result.text, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func generateDocumentSummary(
        content: String,
        filename: String,
        modelId: String? = nil
    ) async throws -> DocumentSummary {
        let start = ContinuousClock.now
        let result = try await specializedAPIs.generateDocumentSummary(
            content: content,
            filename: filename,
            modelId: modelId
        )
        let jsonString = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: result)
        LLMTranscriptLogger.logGeminiCall(
            method: "generateDocumentSummary", modelId: modelId ?? "(default)",
            prompt: "Summarize: \(filename)", attachmentInfo: "Text content: \(content.count) chars",
            response: jsonString, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func analyzeImagesWithGemini(
        images: [Data],
        prompt: String,
        modelId: String? = nil
    ) async throws -> String {
        let start = ContinuousClock.now
        let result = try await specializedAPIs.analyzeImagesWithGemini(
            images: images,
            prompt: prompt,
            modelId: modelId
        )
        LLMTranscriptLogger.logGeminiCall(
            method: "analyzeImagesWithGemini", modelId: modelId ?? "(default)",
            prompt: prompt, attachmentInfo: "\(images.count) images",
            response: result, durationMs: elapsedMs(from: start)
        )
        return result
    }

    func analyzeImagesWithGeminiStructured(
        images: [Data],
        prompt: String,
        jsonSchema: [String: Any],
        modelId: String? = nil
    ) async throws -> String {
        let start = ContinuousClock.now
        let result = try await specializedAPIs.analyzeImagesWithGeminiStructured(
            images: images,
            prompt: prompt,
            jsonSchema: jsonSchema,
            modelId: modelId
        )
        LLMTranscriptLogger.logGeminiCall(
            method: "analyzeImagesWithGeminiStructured", modelId: modelId ?? "(default)",
            prompt: prompt, attachmentInfo: "\(images.count) images (structured)",
            response: result, durationMs: elapsedMs(from: start)
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
