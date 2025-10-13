//
//  LLMFacade.swift
//  Sprung
//
//  A thin facade over LLMClient that centralizes capability gating (future) and
//  exposes a stable surface to callers.
//

import Foundation
import Observation

struct LLMStreamingHandle {
    let conversationId: UUID?
    let stream: AsyncThrowingStream<LLMStreamChunkDTO, Error>
    let cancel: @Sendable () -> Void
}

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
    private let llmService: LLMService // temporary bridge for conversation flows
    private let openRouterService: OpenRouterService
    private let enabledLLMStore: EnabledLLMStore?
    private let modelValidationService: ModelValidationService
    private var activeStreamingTasks: [UUID: Task<Void, Never>] = [:]
    private var backendClients: [Backend: LLMClient] = [:]
    private var conversationServices: [Backend: LLMConversationService] = [:]

    init(
        client: LLMClient,
        llmService: LLMService,
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

    func availableBackends() -> [Backend] {
        Backend.allCases.filter { backendClients[$0] != nil }
    }

    func hasBackend(_ backend: Backend) -> Bool {
        backendClients[backend] != nil
    }

    func supportsConversations(for backend: Backend) -> Bool {
        conversationServices[backend] != nil
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

        let handleId = UUID()
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

        return LLMStreamingHandle(conversationId: conversationId, stream: stream, cancel: cancelClosure)
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
        guard backend == .openRouter else {
            throw LLMError.clientError("Conversations are only supported via OpenRouter at this time")
        }
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

        let handleId = UUID()
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

        return LLMStreamingHandle(conversationId: conversationId, stream: stream, cancel: cancelClosure)
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
}
