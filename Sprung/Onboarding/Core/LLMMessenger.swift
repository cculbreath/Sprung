//
//  LLMMessenger.swift
//  Sprung
//
//  LLM message orchestration (Spec §4.3)
import Foundation
import SwiftOpenAI
import SwiftyJSON
/// Orchestrates LLM message sending and status emission
/// Responsibilities (Spec §4.3):
/// - Subscribe to message request events
/// - Build API requests with context
/// - Emit message sent/status events
/// - Coordinate with NetworkRouter for stream processing
actor LLMMessenger: OnboardingEventEmitter {
    let eventBus: EventCoordinator
    private let networkRouter: NetworkRouter
    private let service: OpenAIService
    private let baseDeveloperMessage: String  // Sent once as developer message on first request, persists via previous_response_id
    private let toolRegistry: ToolRegistry
    private let contextAssembler: ConversationContextAssembler
    private let stateCoordinator: StateCoordinator
    private var isActive = false
    // Stream cancellation tracking
    private var currentStreamTask: Task<Void, Error>?

    init(
        service: OpenAIService,
        baseDeveloperMessage: String,
        eventBus: EventCoordinator,
        networkRouter: NetworkRouter,
        toolRegistry: ToolRegistry,
        state: StateCoordinator
    ) {
        self.service = service
        self.baseDeveloperMessage = baseDeveloperMessage
        self.eventBus = eventBus
        self.networkRouter = networkRouter
        self.toolRegistry = toolRegistry
        self.stateCoordinator = state
        self.contextAssembler = ConversationContextAssembler(state: state)
        Logger.info("📬 LLMMessenger initialized", category: .ai)
    }
    /// Start listening to message request events
    func startEventSubscriptions() async {
        // Use unstructured tasks so they run independently but ensure streams are ready
        Task {
            for await event in await self.eventBus.stream(topic: .llm) {
                await self.handleLLMEvent(event)
            }
        }
        Task {
            for await event in await self.eventBus.stream(topic: .userInput) {
                await self.handleUserInputEvent(event)
            }
        }
        // Small delay to ensure streams are connected before returning
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        Logger.info("📡 LLMMessenger subscribed to events", category: .ai)
    }

    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmSendUserMessage(let payload, let isSystemGenerated):
            await sendUserMessage(payload, isSystemGenerated: isSystemGenerated)
        // llmSendDeveloperMessage is now routed through StateCoordinator's queue
        // and comes back as llmExecuteDeveloperMessage
        case .llmToolResponseMessage(let payload):
            await sendToolResponse(payload)
        case .llmExecuteUserMessage(let payload, let isSystemGenerated):
            await executeUserMessage(payload, isSystemGenerated: isSystemGenerated)
        case .llmExecuteToolResponse(let payload):
            await executeToolResponse(payload)
        case .llmExecuteBatchedToolResponses(let payloads):
            await executeBatchedToolResponses(payloads)
        case .llmExecuteDeveloperMessage(let payload):
            await executeDeveloperMessage(payload)
        case .llmCancelRequested:
            await cancelCurrentStream()
        default:
            break
        }
    }
    private func handleUserInputEvent(_ event: OnboardingEvent) async {
        Logger.debug("LLMMessenger received user input event", category: .ai)
    }
    /// Send user message to LLM (enqueues via event publication)
    private func sendUserMessage(_ payload: JSON, isSystemGenerated: Bool = false) async {
        guard isActive else {
            Logger.warning("LLMMessenger not active, ignoring message", category: .ai)
            return
        }
        await emit(.llmEnqueueUserMessage(payload: payload, isSystemGenerated: isSystemGenerated))
    }
    private func executeUserMessage(_ payload: JSON, isSystemGenerated: Bool) async {
        await emit(.llmStatus(status: .busy))
        let text = payload["content"].string ?? payload["text"].stringValue
        do {
            let request = await buildUserMessageRequest(text: text, isSystemGenerated: isSystemGenerated)
            let messageId = UUID().uuidString
            await emit(.llmUserMessageSent(messageId: messageId, payload: payload, isSystemGenerated: isSystemGenerated))
            currentStreamTask = Task {
                var retryCount = 0
                let maxRetries = 3
                var lastError: Error?
                while retryCount <= maxRetries {
                    do {
                        Logger.info("🔍 About to call service.responseCreateStream, service type: \(type(of: service))", category: .ai)
                        Logger.debug("📋 Request model: \(request.model), prevId: \(request.previousResponseId != nil), store: \(String(describing: request.store))", category: .ai)
                        let stream = try await service.responseCreateStream(request)
                        for try await streamEvent in stream {
                            await networkRouter.handleResponseEvent(streamEvent)
                            // Track conversation state
                            if case .responseCompleted(let completed) = streamEvent {
                                // Update StateCoordinator (single source of truth)
                                await stateCoordinator.updateConversationState(
                                    responseId: completed.response.id
                                )
                                // Store in conversation context for next request
                                await contextAssembler.storePreviousResponseId(completed.response.id)
                            }
                        }
                        await emit(.llmStatus(status: .idle))
                        return // Success - exit retry loop
                    } catch {
                        lastError = error
                        let isRetriableError = isRetriable(error)
                        if isRetriableError && retryCount < maxRetries {
                            retryCount += 1
                            let delay = Double(retryCount) * 2.0 // Exponential backoff: 2s, 4s, 6s
                            Logger.warning("⚠️ Transient error (attempt \(retryCount)/\(maxRetries)), retrying in \(delay)s: \(error)", category: .ai)
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        } else {
                            if let apiError = error as? APIError {
                                Logger.error("❌ API Error details: \(apiError)", category: .ai)
                            }
                            throw error
                        }
                    }
                }

                if let error = lastError {
                    Logger.error("❌ User message failed after \(maxRetries) retries: \(error)", category: .ai)
                    throw error
                }
            }
            try await currentStreamTask?.value
            currentStreamTask = nil
            await stateCoordinator.markStreamCompleted()
        } catch is CancellationError {
            Logger.info("User message stream cancelled", category: .ai)
            await stateCoordinator.markStreamCompleted()
        } catch {
            Logger.error("❌ Failed to send message: \(error)", category: .ai)
            await emit(.errorOccurred("Failed to send message: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
            await surfaceErrorToUI(error: error)
            await stateCoordinator.markStreamCompleted()
        }
    }
    private func executeDeveloperMessage(_ payload: JSON) async {
        guard isActive else {
            Logger.warning("LLMMessenger not active, ignoring developer message", category: .ai)
            return
        }
        await emit(.llmStatus(status: .busy))
        let text = payload["text"].stringValue
        let toolChoiceName = payload["toolChoice"].string
        let reasoningEffort = payload["reasoningEffort"].string
        Logger.info("📨 Sending developer message (\(text.prefix(100))...)", category: .ai)
        do {
            let request = await buildDeveloperMessageRequest(text: text, toolChoice: toolChoiceName, reasoningEffort: reasoningEffort)
            let messageId = UUID().uuidString
            // Emit message sent event
            await emit(.llmDeveloperMessageSent(messageId: messageId, payload: payload))
            // Process stream via NetworkRouter with retry logic
            currentStreamTask = Task {
                var retryCount = 0
                let maxRetries = 3
                var lastError: Error?
                while retryCount <= maxRetries {
                    do {
                        let stream = try await service.responseCreateStream(request)
                        for try await streamEvent in stream {
                            await networkRouter.handleResponseEvent(streamEvent)
                            // Track conversation state
                            if case .responseCompleted(let completed) = streamEvent {
                                // Update StateCoordinator (single source of truth)
                                await stateCoordinator.updateConversationState(
                                    responseId: completed.response.id
                                )
                                // Store in conversation context for next request
                                await contextAssembler.storePreviousResponseId(completed.response.id)
                            }
                        }
                        await emit(.llmStatus(status: .idle))
                        return // Success - exit retry loop
                    } catch {
                        lastError = error
                        // Check if this is a retriable error
                        let isRetriableError = isRetriable(error)
                        if isRetriableError && retryCount < maxRetries {
                            retryCount += 1
                            let delay = Double(retryCount) * 2.0 // Exponential backoff: 2s, 4s, 6s
                            Logger.warning("⚠️ Transient error (attempt \(retryCount)/\(maxRetries)), retrying in \(delay)s: \(error)", category: .ai)
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        } else {
                            // Non-retriable error or max retries reached
                            Logger.error("❌ Developer message stream failed: \(error)", category: .ai)
                            if let apiError = error as? APIError {
                                Logger.error("❌ API Error details: \(apiError)", category: .ai)
                            }
                            throw error
                        }
                    }
                }
                // If we get here, we've exhausted all retries
                if let error = lastError {
                    Logger.error("❌ Developer message failed after \(maxRetries) retries: \(error)", category: .ai)
                    throw error
                }
            }
            try await currentStreamTask?.value
            currentStreamTask = nil
            Logger.info("✅ Developer message completed successfully", category: .ai)
            // Notify StateCoordinator that stream completed
            await stateCoordinator.markStreamCompleted()
        } catch is CancellationError {
            Logger.info("Developer message stream cancelled", category: .ai)
            // Notify StateCoordinator even on cancellation
            await stateCoordinator.markStreamCompleted()
        } catch {
            Logger.error("❌ Failed to send developer message: \(error)", category: .ai)
            await emit(.errorOccurred("Failed to send developer message: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
            // Surface error as visible assistant message
            await surfaceErrorToUI(error: error)
            // Notify StateCoordinator even on error
            await stateCoordinator.markStreamCompleted()
        }
    }
    /// Send tool response back to LLM - enqueues via event publication
    private func sendToolResponse(_ payload: JSON) async {
        await emit(.llmEnqueueToolResponse(payload: payload))
    }
    private func executeToolResponse(_ payload: JSON) async {
        await emit(.llmStatus(status: .busy))
        do {
            let callId = payload["callId"].stringValue
            let output = payload["output"]
            let reasoningEffort = payload["reasoningEffort"].string
            Logger.debug("📤 Tool response payload: callId=\(callId), output=\(output.rawString() ?? "nil")", category: .ai)
            Logger.info("📤 Sending tool response for callId=\(String(callId.prefix(12)))...", category: .ai)
            let request = await buildToolResponseRequest(output: output, callId: callId, reasoningEffort: reasoningEffort)
            Logger.debug("📦 Tool response request: previousResponseId=\(request.previousResponseId ?? "nil")", category: .ai)
            let messageId = UUID().uuidString
            // Emit message sent event
            await emit(.llmSentToolResponseMessage(messageId: messageId, payload: payload))

            // Process stream via NetworkRouter with retry logic
            currentStreamTask = Task {
                var retryCount = 0
                let maxRetries = 3
                var lastError: Error?
                while retryCount <= maxRetries {
                    do {
                        let stream = try await service.responseCreateStream(request)
                        for try await streamEvent in stream {
                            await networkRouter.handleResponseEvent(streamEvent)
                            if case .responseCompleted(let completed) = streamEvent {
                                // Update StateCoordinator (single source of truth)
                                await stateCoordinator.updateConversationState(
                                    responseId: completed.response.id
                                )
                                // Store in conversation context for next request
                                await contextAssembler.storePreviousResponseId(completed.response.id)
                            }
                        }
                        await emit(.llmStatus(status: .idle))
                        return // Success - exit retry loop
                    } catch {
                        lastError = error
                        // Check if this is a retriable error
                        let isRetriableError = isRetriable(error)
                        if isRetriableError && retryCount < maxRetries {
                            retryCount += 1
                            let delay = Double(retryCount) * 2.0 // Exponential backoff: 2s, 4s, 6s
                            Logger.warning("⚠️ Transient error (attempt \(retryCount)/\(maxRetries)), retrying in \(delay)s: \(error)", category: .ai)
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        } else {
                            // Non-retriable error or max retries reached
                            Logger.error("❌ Tool response stream failed: \(error)", category: .ai)
                            if let apiError = error as? APIError {
                                Logger.error("❌ API Error details: \(apiError)", category: .ai)
                            }
                            throw error
                        }
                    }
                }
                // If we get here, we've exhausted all retries
                if let error = lastError {
                    Logger.error("❌ Tool response failed after \(maxRetries) retries: \(error)", category: .ai)
                    throw error
                }
            }
            try await currentStreamTask?.value
            currentStreamTask = nil
            // Notify StateCoordinator that stream completed
            await stateCoordinator.markStreamCompleted()
        } catch is CancellationError {
            Logger.info("Tool response stream cancelled", category: .ai)
            // Notify StateCoordinator even on cancellation
            await stateCoordinator.markStreamCompleted()
        } catch {
            await emit(.errorOccurred("Failed to send tool response: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
            // Notify StateCoordinator even on error
            await stateCoordinator.markStreamCompleted()
        }
    }
    /// Execute batched tool responses (for parallel tool calls)
    /// OpenAI API requires all tool outputs from parallel calls to be sent together in one request
    private func executeBatchedToolResponses(_ payloads: [JSON]) async {
        await emit(.llmStatus(status: .busy))
        do {
            Logger.info("📤 Sending batched tool responses (\(payloads.count) responses)", category: .ai)
            let request = await buildBatchedToolResponseRequest(payloads: payloads)
            Logger.debug("📦 Batched tool response request: previousResponseId=\(request.previousResponseId ?? "nil")", category: .ai)
            let messageId = UUID().uuidString
            // Emit message sent event for each response in the batch
            for payload in payloads {
                await emit(.llmSentToolResponseMessage(messageId: messageId, payload: payload))
            }
            // Process stream via NetworkRouter with retry logic
            currentStreamTask = Task {
                var retryCount = 0
                let maxRetries = 3
                var lastError: Error?
                while retryCount <= maxRetries {
                    do {
                        let stream = try await service.responseCreateStream(request)
                        for try await streamEvent in stream {
                            await networkRouter.handleResponseEvent(streamEvent)
                            if case .responseCompleted(let completed) = streamEvent {
                                await stateCoordinator.updateConversationState(
                                    responseId: completed.response.id
                                )
                                await contextAssembler.storePreviousResponseId(completed.response.id)
                            }
                        }
                        await emit(.llmStatus(status: .idle))
                        return // Success - exit retry loop
                    } catch {
                        lastError = error
                        let isRetriableError = isRetriable(error)
                        if isRetriableError && retryCount < maxRetries {
                            retryCount += 1
                            let delay = Double(retryCount) * 2.0
                            Logger.warning("⚠️ Transient error (attempt \(retryCount)/\(maxRetries)), retrying in \(delay)s: \(error)", category: .ai)
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        } else {
                            Logger.error("❌ Batched tool response stream failed: \(error)", category: .ai)
                            if let apiError = error as? APIError {
                                Logger.error("❌ API Error details: \(apiError)", category: .ai)
                            }
                            throw error
                        }
                    }
                }
                if let error = lastError {
                    Logger.error("❌ Batched tool response failed after \(maxRetries) retries: \(error)", category: .ai)
                    throw error
                }
            }
            try await currentStreamTask?.value
            currentStreamTask = nil
            await stateCoordinator.markStreamCompleted()
        } catch is CancellationError {
            Logger.info("Batched tool response stream cancelled", category: .ai)
            await stateCoordinator.markStreamCompleted()
        } catch {
            await emit(.errorOccurred("Failed to send batched tool responses: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
            await stateCoordinator.markStreamCompleted()
        }
    }
    /// Determine if parallel tool calls should be enabled based on current state
    private func shouldEnableParallelToolCalls() async -> Bool {
        let validation = await stateCoordinator.pendingValidationPrompt
        return validation?.dataType == "skeleton_timeline"
    }
    private func buildUserMessageRequest(text: String, isSystemGenerated: Bool) async -> ModelResponseParameter {
        let previousResponseId = await contextAssembler.getPreviousResponseId()

        let inputItems: [InputItem] = [
            .message(InputMessage(
                role: "user",
                content: .text(text)
            ))
        ]
        let tools = await getToolSchemas()
        let toolChoice = await determineToolChoice(for: text, isSystemGenerated: isSystemGenerated)
        let modelId = await stateCoordinator.getCurrentModelId()
        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: nil,  // No instructions - using developer messages for persistent behavior
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        Logger.info(
            "📝 Built request: previousResponseId=\(previousResponseId?.description ?? "nil"), inputItems=\(inputItems.count), parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil")",
            category: .ai
        )
        return parameters
    }
    /// Determine appropriate tool_choice for the given message context
    private func determineToolChoice(for text: String, isSystemGenerated: Bool) async -> ToolChoiceMode {
        if isSystemGenerated {
            return .auto
        }
        let hasStreamed = await stateCoordinator.getHasStreamedFirstResponse()
        if !hasStreamed {
            Logger.info("🚫 Forcing toolChoice=.none for first user request to ensure greeting", category: .ai)
            return .none
        }
        return .auto
    }
    private func buildDeveloperMessageRequest(
        text: String,
        toolChoice toolChoiceName: String? = nil,
        reasoningEffort: String? = nil
    ) async -> ModelResponseParameter {
        let previousResponseId = await contextAssembler.getPreviousResponseId()
        var inputItems: [InputItem] = []
        if previousResponseId == nil {
            inputItems.append(.message(InputMessage(
                role: "developer",
                content: .text(baseDeveloperMessage)
            )))
            Logger.info("📋 Including base developer message (first request)", category: .ai)
        }
        inputItems.append(.message(InputMessage(
            role: "developer",
            content: .text(text)
        )))
        let tools = await getToolSchemas()
        let toolChoice: ToolChoiceMode
        if let toolName = toolChoiceName {
            toolChoice = .functionTool(FunctionTool(name: toolName))
        } else {
            toolChoice = .auto
        }
        let modelId = await stateCoordinator.getCurrentModelId()
        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: nil,  // Base developer message sent in first request, persists via previous_response_id
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        // Set reasoning effort if provided
        if let effort = reasoningEffort {
            parameters.reasoning = Reasoning(effort: effort)
        }
        Logger.info(
            """
            📝 Built developer message request: \
            previousResponseId=\(previousResponseId?.description ?? "nil"), \
            inputItems=\(inputItems.count), \
            parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil"), \
            reasoningEffort=\(reasoningEffort ?? "default")
            """,
            category: .ai
        )
        return parameters
    }
    private func buildToolResponseRequest(output: JSON, callId: String, reasoningEffort: String? = nil) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForToolResponse(
            output: output,
            callId: callId
        )
        let tools = await getToolSchemas()
        let modelId = await stateCoordinator.getCurrentModelId()
        let previousResponseId = await contextAssembler.getPreviousResponseId()
        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: nil,  // Base developer message already sent on first request, persists via previous_response_id
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = .auto
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        // Set reasoning effort if provided
        if let effort = reasoningEffort {
            parameters.reasoning = Reasoning(effort: effort)
        }
        Logger.info("📝 Built tool response request: parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil")", category: .ai)
        return parameters
    }
    /// Build request for batched tool responses (parallel tool calls)
    private func buildBatchedToolResponseRequest(payloads: [JSON]) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForBatchedToolResponses(payloads: payloads)
        let tools = await getToolSchemas()
        let modelId = await stateCoordinator.getCurrentModelId()
        let previousResponseId = await contextAssembler.getPreviousResponseId()
        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: nil,
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = .auto
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        Logger.info("📝 Built batched tool response request: \(inputItems.count) tool outputs, parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil")", category: .ai)
        return parameters
    }
    /// Get tool schemas from ToolRegistry, filtered by allowed tools from StateCoordinator
    private func getToolSchemas() async -> [Tool] {
        let allowedNames = await stateCoordinator.getAllowedToolNames()
        let filterNames = allowedNames.isEmpty ? nil : allowedNames
        return await toolRegistry.toolSchemas(filteredBy: filterNames)
    }

    func activate() {
        isActive = true
        Logger.info("✅ LLMMessenger activated", category: .ai)
    }
    func deactivate() {
        isActive = false
        Logger.info("⏹️ LLMMessenger deactivated", category: .ai)
    }
    func setModelId(_ modelId: String) async {
        await stateCoordinator.setModelId(modelId)
    }
    // MARK: - Stream Cancellation
    /// Cancel the currently running stream
    private func cancelCurrentStream() async {
        guard let task = currentStreamTask else {
            Logger.debug("No active stream to cancel", category: .ai)
            return
        }
        Logger.info("🛑 Cancelling LLM stream...", category: .ai)
        Logger.info("🛑 Cancelling LLM stream...", category: .ai)
        task.cancel()
        currentStreamTask = nil
        await networkRouter.cancelPendingStreams()
        await emit(.llmStatus(status: .idle))
        Logger.info("✅ LLM stream cancelled and cleaned up", category: .ai)
    }
    // MARK: - Error Handling
    private func isRetriable(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .responseUnsuccessful(_, let statusCode, _):
                return statusCode == 503 || statusCode == 502 || statusCode == 504 || statusCode >= 500
            case .jsonDecodingFailure, .bothDecodingStrategiesFailed:
                return true
            case .timeOutError:
                return true
            case .requestFailed, .invalidData, .dataCouldNotBeReadMissingData:
                return false
            }
        }
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("network") ||
           errorDescription.contains("connection") ||
           errorDescription.contains("timeout") ||
           errorDescription.contains("lost connection") {
            return true
        }
        if error is CancellationError {
            return false
        }
        return false
    }
    private func surfaceErrorToUI(error: Error) async {
        let errorMessage: String
        let errorDescription = error.localizedDescription
        if errorDescription.contains("network") || errorDescription.contains("connection") {
            errorMessage = "I'm having trouble connecting to the AI service. Please check your network connection and try again."
        } else if errorDescription.contains("401") || errorDescription.contains("403") {
            errorMessage = "There's an authentication issue with the AI service. Please check your API key and try again."
        } else if errorDescription.contains("429") {
            errorMessage = "The AI service is currently rate-limited. Please wait a moment and try again."
        } else if errorDescription.contains("500") || errorDescription.contains("503") {
            errorMessage = "The AI service is temporarily unavailable. Please try again in a few moments."
        } else {
            errorMessage = "I encountered an error while processing your request: \(errorDescription). Please try again, or contact support if this persists."
        }
        let payload = JSON(["text": errorMessage])
        await emit(.llmUserMessageSent(messageId: UUID().uuidString, payload: payload, isSystemGenerated: true))
        Logger.error("📢 Error surfaced to UI: \(errorMessage)", category: .ai)
    }
}
