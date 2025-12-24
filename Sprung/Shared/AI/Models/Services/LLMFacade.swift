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
        var displayName: String {
            switch self {
            case .openRouter: return "OpenRouter"
            case .openAI: return "OpenAI"
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
    func executeTextWithPDF(
        prompt: String,
        modelId: String,
        pdfData: Data,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        backend: Backend = .openRouter
    ) async throws -> String {
        // PDFs are supported natively by OpenRouter for models that support file input
        if backend == .openRouter {
            try await validate(modelId: modelId, requires: [])
            return try await client.executeTextWithPDF(prompt: prompt, modelId: modelId, pdfData: pdfData, temperature: temperature, maxTokens: maxTokens)
        }
        let altClient = try resolveClient(for: backend)
        return try await altClient.executeTextWithPDF(prompt: prompt, modelId: modelId, pdfData: pdfData, temperature: temperature, maxTokens: maxTokens)
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
        temperature: Double? = nil
    ) async throws -> ChatCompletionObject {
        try await validate(modelId: modelId, requires: [])

        let parameters = LLMRequestBuilder.buildToolRequest(
            messages: messages,
            modelId: modelId,
            tools: tools,
            toolChoice: toolChoice,
            temperature: temperature ?? 0.7
        )

        return try await llmService.executeToolRequest(parameters: parameters)
    }
}
