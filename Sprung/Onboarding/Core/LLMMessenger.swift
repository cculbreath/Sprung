//
//  LLMMessenger.swift
//  Sprung
//
//  LLM message orchestration (Spec §4.3)
import AppKit
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
        case .llmSendUserMessage(let payload, let isSystemGenerated, let chatboxMessageId, let originalText, let toolChoice):
            await sendUserMessage(payload, isSystemGenerated: isSystemGenerated, chatboxMessageId: chatboxMessageId, originalText: originalText, toolChoice: toolChoice)
        // llmSendDeveloperMessage is now routed through StateCoordinator's queue
        // and comes back as llmExecuteDeveloperMessage
        case .llmToolResponseMessage(let payload):
            await sendToolResponse(payload)
        case .llmExecuteUserMessage(let payload, let isSystemGenerated, let chatboxMessageId, let originalText, let bundledDeveloperMessages, let toolChoice):
            await executeUserMessage(payload, isSystemGenerated: isSystemGenerated, chatboxMessageId: chatboxMessageId, originalText: originalText, bundledDeveloperMessages: bundledDeveloperMessages, toolChoice: toolChoice)
        case .llmExecuteToolResponse(let payload):
            await executeToolResponse(payload)
        case .llmExecuteBatchedToolResponses(let payloads):
            await executeBatchedToolResponses(payloads)
        case .llmExecuteDeveloperMessage(let payload):
            await executeDeveloperMessage(payload)
        case .llmCancelRequested:
            await cancelCurrentStream()
        case .llmBudgetExceeded(let inputTokens, let threshold):
            await handleBudgetExceeded(inputTokens: inputTokens, threshold: threshold)
        default:
            break
        }
    }
    private func handleUserInputEvent(_ event: OnboardingEvent) async {
        Logger.debug("LLMMessenger received user input event", category: .ai)
    }
    /// Send user message to LLM (enqueues via event publication)
    private func sendUserMessage(_ payload: JSON, isSystemGenerated: Bool = false, chatboxMessageId: String? = nil, originalText: String? = nil, toolChoice: String? = nil) async {
        guard isActive else {
            Logger.warning("LLMMessenger not active, ignoring message", category: .ai)
            return
        }
        await emit(.llmEnqueueUserMessage(
            payload: payload,
            isSystemGenerated: isSystemGenerated,
            chatboxMessageId: chatboxMessageId,
            originalText: originalText,
            toolChoice: toolChoice
        ))
    }
    private func executeUserMessage(_ payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String? = nil, originalText: String? = nil, bundledDeveloperMessages: [JSON] = [], toolChoice: String? = nil) async {
        await emit(.llmStatus(status: .busy))
        let text = payload["content"].string ?? payload["text"].stringValue

        // Extract image data if present
        let imageData = payload["image_data"].string
        let imageContentType = payload["content_type"].string

        do {
            let request = await buildUserMessageRequest(text: text, isSystemGenerated: isSystemGenerated, bundledDeveloperMessages: bundledDeveloperMessages, forcedToolChoice: toolChoice, imageBase64: imageData, imageContentType: imageContentType)
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
                                // Check if response had tool calls (affects checkpoint safety)
                                let hadToolCalls = completed.response.output.contains { item in
                                    if case .functionCall = item { return true }
                                    return false
                                }
                                // Update StateCoordinator (single source of truth)
                                await stateCoordinator.updateConversationState(
                                    responseId: completed.response.id,
                                    hadToolCalls: hadToolCalls
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

            // Check for "No tool output found" error - conversation state is out of sync
            let errorDescription = String(describing: error)
            if errorDescription.contains("No tool output found for function call") {
                // Extract call_id from error
                if let callId = extractCallIdFromError(errorDescription) {
                    Logger.warning("🔧 Attempting recovery: sending synthetic tool response for \(callId)", category: .ai)

                    // Try to recover by sending a synthetic tool response
                    let recovered = await attemptToolOutputRecovery(
                        callId: callId,
                        originalPayload: payload,
                        isSystemGenerated: isSystemGenerated,
                        chatboxMessageId: chatboxMessageId,
                        originalText: originalText,
                        bundledDeveloperMessages: bundledDeveloperMessages,
                        toolChoice: toolChoice
                    )

                    if recovered {
                        Logger.info("✅ Recovery successful - conversation unblocked", category: .ai)
                        await stateCoordinator.markStreamCompleted()
                        return
                    }
                }

                // Recovery failed - show alert
                Logger.error("🔧 Recovery failed for pending tool call", category: .ai)
                await showConversationSyncErrorAlert(callId: extractCallIdFromError(errorDescription))
                await emit(.errorOccurred("Conversation sync error: Recovery failed. Use 'Reset Conversation' to recover."))
                await emit(.llmStatus(status: .error))

                if let chatboxMessageId = chatboxMessageId, let originalText = originalText {
                    await emit(.llmUserMessageFailed(
                        messageId: chatboxMessageId,
                        originalText: originalText,
                        error: "Conversation sync error - recovery failed"
                    ))
                }
                await stateCoordinator.markStreamCompleted()
                return
            }

            await emit(.errorOccurred("Failed to send message: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
            // For chatbox messages, emit failure event so UI can restore the message to input box
            if let chatboxMessageId = chatboxMessageId, let originalText = originalText {
                await emit(.llmUserMessageFailed(
                    messageId: chatboxMessageId,
                    originalText: originalText,
                    error: error.localizedDescription
                ))
            } else {
                // Fallback: show error in chat for system-generated messages
                await surfaceErrorToUI(error: error)
            }
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
                                // Check if response had tool calls (affects checkpoint safety)
                                let hadToolCalls = completed.response.output.contains { item in
                                    if case .functionCall = item { return true }
                                    return false
                                }
                                // Update StateCoordinator (single source of truth)
                                await stateCoordinator.updateConversationState(
                                    responseId: completed.response.id,
                                    hadToolCalls: hadToolCalls
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
        // Track pending tool response for retry on stream error
        await stateCoordinator.setPendingToolResponses([payload])
        do {
            let callId = payload["callId"].stringValue
            let output = payload["output"]
            let reasoningEffort = payload["reasoningEffort"].string
            let toolChoice = payload["toolChoice"].string  // For tool chaining
            Logger.debug("📤 Tool response payload: callId=\(callId), output=\(output.rawString() ?? "nil")", category: .ai)
            Logger.info("📤 Sending tool response for callId=\(String(callId.prefix(12)))...", category: .ai)
            let request = await buildToolResponseRequest(output: output, callId: callId, reasoningEffort: reasoningEffort, forcedToolChoice: toolChoice)
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
                                // Tool response acknowledged - clear pending state
                                await stateCoordinator.clearPendingToolResponses()
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
        // Track pending tool responses for retry on stream error
        await stateCoordinator.setPendingToolResponses(payloads)
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
                                // Tool responses acknowledged - clear pending state
                                await stateCoordinator.clearPendingToolResponses()
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
    /// Enabled for Phase 1 (skeleton timeline) and Phase 2 (document collection/KC generation)
    private func shouldEnableParallelToolCalls() async -> Bool {
        let currentPhase = await stateCoordinator.phase

        // Enable parallel tool calls for Phase 1 and Phase 2
        // Phase 1: skeleton timeline extraction and validation
        // Phase 2: document collection and KC generation
        return currentPhase == .phase1CoreFacts || currentPhase == .phase2DeepDive
    }
    private func buildUserMessageRequest(text: String, isSystemGenerated: Bool, bundledDeveloperMessages: [JSON] = [], forcedToolChoice: String? = nil, imageBase64: String? = nil, imageContentType: String? = nil) async -> ModelResponseParameter {
        let previousResponseId = await contextAssembler.getPreviousResponseId()
        var inputItems: [InputItem] = []

        // If no previous response ID, we need to include full context
        // This happens on fresh start or after checkpoint restore
        if previousResponseId == nil {
            // Include base developer message (system prompt)
            inputItems.append(.message(InputMessage(
                role: "developer",
                content: .text(baseDeveloperMessage)
            )))

            // Include conversation history if this is a restore (not first message)
            let hasHistory = await contextAssembler.hasConversationHistory()
            if hasHistory {
                let history = await contextAssembler.buildConversationHistory()
                inputItems.append(contentsOf: history)
                Logger.info("📋 Checkpoint restore: including \(history.count) messages from transcript", category: .ai)
            } else {
                Logger.info("📋 Fresh start: including base developer message", category: .ai)
            }
        }

        // Include bundled developer messages (status updates, etc.) before the user message
        // These are included in the same request to avoid separate LLM turns
        for devPayload in bundledDeveloperMessages {
            let devText = devPayload["text"].stringValue
            if !devText.isEmpty {
                inputItems.append(.message(InputMessage(
                    role: "developer",
                    content: .text(devText)
                )))
            }
        }
        if !bundledDeveloperMessages.isEmpty {
            Logger.info("📦 Included \(bundledDeveloperMessages.count) bundled developer message(s) in request", category: .ai)
        }

        // Build user message - with image if provided
        if let imageData = imageBase64 {
            // Build multimodal message with text + image
            let mimeType = imageContentType ?? "image/jpeg"
            let dataUrl = "data:\(mimeType);base64,\(imageData)"

            var contentItems: [ContentItem] = [.text(TextContent(text: text))]
            contentItems.append(.image(ImageContent(imageUrl: dataUrl)))

            inputItems.append(.message(InputMessage(
                role: "user",
                content: .array(contentItems)
            )))
            Logger.info("🖼️ Including image attachment in user message (\(mimeType))", category: .ai)
        } else {
            inputItems.append(.message(InputMessage(
                role: "user",
                content: .text(text)
            )))
        }

        // Determine tool choice first (needed for tool bundling)
        let toolChoice: ToolChoiceMode
        if let forcedTool = forcedToolChoice {
            toolChoice = .functionTool(FunctionTool(name: forcedTool))
            Logger.info("🎯 Using forced toolChoice: \(forcedTool)", category: .ai)
        } else {
            toolChoice = await determineToolChoice(for: text, isSystemGenerated: isSystemGenerated)
        }

        // Get tools with bundling based on toolChoice
        let tools = await getToolSchemas(for: toolChoice)

        let modelId = await stateCoordinator.getCurrentModelId()
        let useFlexTier = await stateCoordinator.getUseFlexProcessing()

        // Build WorkingMemory for instructions (non-persistent context)
        let workingMemory = await buildWorkingMemory()

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: workingMemory,  // WorkingMemory snapshot (non-persistent, high priority)
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        if useFlexTier {
            parameters.serviceTier = "flex"
        }
        // Apply extended cache retention if enabled in settings
        let useCacheRetention = UserDefaults.standard.bool(forKey: "onboardingInterviewPromptCacheRetention")
        if useCacheRetention {
            parameters.promptCacheRetention = "24h"
        }
        // Apply default reasoning effort from settings, with summary enabled for UI display
        let effectiveReasoning = await stateCoordinator.getDefaultReasoningEffort()
        if effectiveReasoning != "none" {
            parameters.reasoning = Reasoning(effort: effectiveReasoning, summary: .auto)
        }
        Logger.info(
            "📝 Built request: previousResponseId=\(previousResponseId?.description ?? "nil"), inputItems=\(inputItems.count), parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil"), serviceTier=\(parameters.serviceTier ?? "default"), cacheRetention=\(useCacheRetention ? "24h" : "default"), reasoningEffort=\(effectiveReasoning)",
            category: .ai
        )

        // Log telemetry for token budget tracking
        let currentPhase = await stateCoordinator.phase
        RequestTelemetry(
            phase: currentPhase.rawValue,
            substate: nil,
            toolsSentCount: tools.count,
            instructionsChars: workingMemory?.count ?? 0,
            bundledDevMsgsCount: bundledDeveloperMessages.count,
            inputTokens: nil,  // Will be populated after response
            outputTokens: nil,
            cachedTokens: nil,
            isFirstTurn: previousResponseId == nil,
            requestType: .userMessage
        ).log()

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

        // Determine tool choice first (needed for tool bundling)
        let toolChoice: ToolChoiceMode
        if let toolName = toolChoiceName {
            toolChoice = .functionTool(FunctionTool(name: toolName))
        } else {
            toolChoice = .auto
        }

        // Get tools with bundling based on toolChoice
        let tools = await getToolSchemas(for: toolChoice)

        let modelId = await stateCoordinator.getCurrentModelId()
        let useFlexTier = await stateCoordinator.getUseFlexProcessing()

        // Build WorkingMemory for instructions (non-persistent context)
        let workingMemory = await buildWorkingMemory()

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: workingMemory,  // WorkingMemory snapshot (non-persistent, high priority)
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        if useFlexTier {
            parameters.serviceTier = "flex"
        }
        // Apply extended cache retention if enabled in settings
        let useCacheRetention = UserDefaults.standard.bool(forKey: "onboardingInterviewPromptCacheRetention")
        if useCacheRetention {
            parameters.promptCacheRetention = "24h"
        }
        // Set reasoning effort (use provided value or default from settings), with summary enabled
        let defaultReasoning = await stateCoordinator.getDefaultReasoningEffort()
        let effectiveReasoning = reasoningEffort ?? defaultReasoning
        if effectiveReasoning != "none" {
            parameters.reasoning = Reasoning(effort: effectiveReasoning, summary: .auto)
        }
        let toolChoiceDesc: String
        switch toolChoice {
        case .auto:
            toolChoiceDesc = "auto"
        case .none:
            toolChoiceDesc = "none"
        case .required:
            toolChoiceDesc = "required"
        case .functionTool(let ft):
            toolChoiceDesc = "function(\(ft.name))"
        case .allowedTools(let at):
            toolChoiceDesc = "allowedTools(\(at.tools.map { $0.name }.joined(separator: ", ")))"
        case .hostedTool(let ht):
            toolChoiceDesc = "hostedTool(\(ht))"
        case .customTool(let ct):
            toolChoiceDesc = "customTool(\(ct.name))"
        }
        Logger.info(
            """
            📝 Built developer message request: \
            previousResponseId=\(previousResponseId?.description ?? "nil"), \
            inputItems=\(inputItems.count), \
            toolChoice=\(toolChoiceDesc), \
            parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil"), \
            reasoningEffort=\(effectiveReasoning)
            """,
            category: .ai
        )

        // Log telemetry for token budget tracking
        let currentPhase = await stateCoordinator.phase
        RequestTelemetry(
            phase: currentPhase.rawValue,
            substate: nil,
            toolsSentCount: tools.count,
            instructionsChars: workingMemory?.count ?? 0,
            bundledDevMsgsCount: 0,
            inputTokens: nil,
            outputTokens: nil,
            cachedTokens: nil,
            isFirstTurn: previousResponseId == nil,
            requestType: .developerMessage
        ).log()

        return parameters
    }
    private func buildToolResponseRequest(output: JSON, callId: String, reasoningEffort: String? = nil, forcedToolChoice: String? = nil) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForToolResponse(
            output: output,
            callId: callId
        )

        // Determine tool choice first (needed for tool bundling)
        let toolChoice: ToolChoiceMode
        if let forcedTool = forcedToolChoice {
            toolChoice = .functionTool(FunctionTool(name: forcedTool))
            Logger.info("🔗 Forcing toolChoice to: \(forcedTool)", category: .ai)
        } else {
            toolChoice = .auto
        }

        // Get tools with bundling based on toolChoice
        let tools = await getToolSchemas(for: toolChoice)

        let modelId = await stateCoordinator.getCurrentModelId()
        let useFlexTier = await stateCoordinator.getUseFlexProcessing()
        let previousResponseId = await contextAssembler.getPreviousResponseId()

        // Build WorkingMemory for instructions (non-persistent context)
        let workingMemory = await buildWorkingMemory()

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: workingMemory,  // WorkingMemory snapshot (non-persistent, high priority)
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        if useFlexTier {
            parameters.serviceTier = "flex"
        }
        // Apply extended cache retention if enabled in settings
        let useCacheRetention = UserDefaults.standard.bool(forKey: "onboardingInterviewPromptCacheRetention")
        if useCacheRetention {
            parameters.promptCacheRetention = "24h"
        }
        // Set reasoning effort (use provided value or default from settings), with summary enabled
        let defaultReasoning = await stateCoordinator.getDefaultReasoningEffort()
        let effectiveReasoning = reasoningEffort ?? defaultReasoning
        if effectiveReasoning != "none" {
            parameters.reasoning = Reasoning(effort: effectiveReasoning, summary: .auto)
        }
        Logger.info("📝 Built tool response request: parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil"), toolChoice=\(forcedToolChoice ?? "auto"), serviceTier=\(parameters.serviceTier ?? "default"), cacheRetention=\(useCacheRetention ? "24h" : "default"), reasoningEffort=\(effectiveReasoning)", category: .ai)

        // Log telemetry for token budget tracking
        let currentPhase = await stateCoordinator.phase
        RequestTelemetry(
            phase: currentPhase.rawValue,
            substate: nil,
            toolsSentCount: tools.count,
            instructionsChars: workingMemory?.count ?? 0,
            bundledDevMsgsCount: 0,
            inputTokens: nil,
            outputTokens: nil,
            cachedTokens: nil,
            isFirstTurn: false,  // Tool responses are never first turn
            requestType: .toolResponse
        ).log()

        return parameters
    }
    /// Build request for batched tool responses (parallel tool calls)
    private func buildBatchedToolResponseRequest(payloads: [JSON]) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForBatchedToolResponses(payloads: payloads)
        // Batched tool responses use auto toolChoice
        let toolChoice: ToolChoiceMode = .auto
        let tools = await getToolSchemas(for: toolChoice)

        let modelId = await stateCoordinator.getCurrentModelId()
        let useFlexTier = await stateCoordinator.getUseFlexProcessing()
        let previousResponseId = await contextAssembler.getPreviousResponseId()

        // Build WorkingMemory for instructions (non-persistent context)
        let workingMemory = await buildWorkingMemory()

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: workingMemory,  // WorkingMemory snapshot (non-persistent, high priority)
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        if useFlexTier {
            parameters.serviceTier = "flex"
        }
        // Apply extended cache retention if enabled in settings
        let useCacheRetention = UserDefaults.standard.bool(forKey: "onboardingInterviewPromptCacheRetention")
        if useCacheRetention {
            parameters.promptCacheRetention = "24h"
        }
        // Apply default reasoning effort from settings, with summary enabled
        let effectiveReasoning = await stateCoordinator.getDefaultReasoningEffort()
        if effectiveReasoning != "none" {
            parameters.reasoning = Reasoning(effort: effectiveReasoning, summary: .auto)
        }
        Logger.info("📝 Built batched tool response request: \(inputItems.count) tool outputs, parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil"), serviceTier=\(parameters.serviceTier ?? "default"), cacheRetention=\(useCacheRetention ? "24h" : "default"), reasoningEffort=\(effectiveReasoning)", category: .ai)

        // Log telemetry for token budget tracking
        let currentPhase = await stateCoordinator.phase
        RequestTelemetry(
            phase: currentPhase.rawValue,
            substate: nil,
            toolsSentCount: tools.count,
            instructionsChars: workingMemory?.count ?? 0,
            bundledDevMsgsCount: 0,
            inputTokens: nil,
            outputTokens: nil,
            cachedTokens: nil,
            isFirstTurn: false,  // Batched tool responses are never first turn
            requestType: .batchedToolResponse
        ).log()

        return parameters
    }
    /// Get tool schemas from ToolRegistry, filtered by allowed tools using subphase-aware bundling
    /// - Parameter toolChoice: Optional tool choice mode to override bundling
    private func getToolSchemas(for toolChoice: ToolChoiceMode? = nil) async -> [Tool] {
        // Get base allowed tools from state coordinator
        let allowedNames = await stateCoordinator.getAllowedToolNames()

        // Get current state for subphase inference
        let phase = await stateCoordinator.phase
        let toolPaneCard = await stateCoordinator.getCurrentToolPaneCard()
        let objectives = await stateCoordinator.getObjectiveStatusMap()

        // Infer current subphase from objectives + UI state
        let subphase = ToolBundlePolicy.inferSubphase(
            phase: phase,
            toolPaneCard: toolPaneCard,
            objectives: objectives
        )

        // Select tools based on subphase (handles toolChoice internally)
        let bundledNames = ToolBundlePolicy.selectBundleForSubphase(
            subphase,
            allowedTools: allowedNames,
            toolChoice: toolChoice
        )

        // Handle empty bundle case
        if bundledNames.isEmpty {
            Logger.debug("🔧 Tool bundling: subphase=\(subphase.rawValue), sending 0 tools", category: .ai)
            return []
        }

        let schemas = await toolRegistry.toolSchemas(filteredBy: bundledNames)
        Logger.debug("🔧 Tool bundling: subphase=\(subphase.rawValue), toolPane=\(toolPaneCard.rawValue), sending \(schemas.count) tools: \(bundledNames.sorted().joined(separator: ", "))", category: .ai)

        return schemas
    }

    // MARK: - Working Memory

    /// Build a compact WorkingMemory snapshot for the `instructions` parameter
    /// The `instructions` parameter doesn't persist in the PRI thread, making it
    /// ideal for providing rich context on every turn without growing the thread.
    private func buildWorkingMemory() async -> String? {
        let phase = await stateCoordinator.phase

        var parts: [String] = []

        // Phase header
        parts.append("## Working Memory (Phase: \(phase.shortName))")

        // Current visible UI panel (helps LLM know what user sees)
        let currentPanel = await stateCoordinator.getCurrentToolPaneCard()
        if currentPanel != .none {
            parts.append("Visible UI: \(currentPanel.rawValue)")
        } else {
            parts.append("Visible UI: none (call upload/prompt tools to show UI)")
        }

        // Objectives status (filtered to current phase)
        let objectives = await stateCoordinator.getObjectivesForPhase(phase)
        if !objectives.isEmpty {
            let statusList = objectives.map { "\($0.id): \($0.status.rawValue)" }
            parts.append("Objectives: \(statusList.joined(separator: ", "))")
        }

        // Timeline summary
        let artifacts = await stateCoordinator.artifacts
        if let entries = artifacts.skeletonTimeline?["experiences"].array, !entries.isEmpty {
            let timelineSummary = entries.prefix(6).compactMap { entry -> String? in
                guard let org = entry["organization"].string,
                      let title = entry["title"].string else { return nil }
                let dates = [entry["start"].string, entry["end"].string]
                    .compactMap { $0 }
                    .joined(separator: "-")
                return "\(title) @ \(org)" + (dates.isEmpty ? "" : " (\(dates))")
            }
            if !timelineSummary.isEmpty {
                parts.append("Timeline (\(entries.count) entries): \(timelineSummary.joined(separator: "; "))")
            }
        }

        // Artifact summary
        let artifactSummaries = await stateCoordinator.listArtifactSummaries()
        if !artifactSummaries.isEmpty {
            let artifactSummary = artifactSummaries.prefix(6).compactMap { record -> String? in
                guard let filename = record["filename"].string else { return nil }
                let desc = record["brief_description"].string ?? record["summary"].string ?? ""
                let shortDesc = desc.isEmpty ? "" : " - \(String(desc.prefix(40)))"
                return filename + shortDesc
            }
            if !artifactSummary.isEmpty {
                parts.append("Artifacts (\(artifactSummaries.count)): \(artifactSummary.joined(separator: "; "))")
            }
        }

        // Only return if we have meaningful content
        guard parts.count > 1 else { return nil }

        let memory = parts.joined(separator: "\n")

        // Enforce max size (target ~2KB)
        let maxChars = 2500
        if memory.count > maxChars {
            Logger.warning("⚠️ WorkingMemory exceeds target (\(memory.count) chars)", category: .ai)
            return String(memory.prefix(maxChars))
        }

        Logger.debug("📋 WorkingMemory: \(memory.count) chars", category: .ai)
        return memory
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
    // MARK: - Budget Enforcement (Milestone 8)

    /// Handle budget exceeded event by resetting the PRI thread
    /// This starts a fresh conversation thread seeded with base developer message + WorkingMemory
    private func handleBudgetExceeded(inputTokens: Int, threshold: Int) async {
        Logger.warning(
            "🛑 PRI Reset: Input tokens (\(inputTokens)) exceeded hard stop (\(threshold)). Clearing previous_response_id.",
            category: .ai
        )

        // Clear the previous_response_id - this resets the conversation thread
        // The next request will automatically:
        // 1. Include the base developer message (since previousResponseId == nil)
        // 2. Include WorkingMemory in the instructions parameter
        // Note: StateCoordinator.setPreviousResponseId() delegates to ChatTranscriptStore,
        // and ConversationContextAssembler.getPreviousResponseId() reads from the same source
        await stateCoordinator.setPreviousResponseId(nil)

        Logger.info(
            "✅ PRI thread reset complete. Next request will start fresh with base developer message + WorkingMemory.",
            category: .ai
        )
    }

    // MARK: - Stream Cancellation
    /// Cancel the currently running stream
    private func cancelCurrentStream() async {
        guard let task = currentStreamTask else {
            Logger.debug("No active stream to cancel", category: .ai)
            return
        }
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
        // Check for insufficient credits error - show popup alert
        if let llmError = error as? LLMError {
            if case .insufficientCredits(let requested, let available) = llmError {
                await showInsufficientCreditsAlert(requested: requested, available: available)
                return
            }
        }

        let errorMessage: String
        let errorDescription = error.localizedDescription
        if errorDescription.contains("network") || errorDescription.contains("connection") {
            errorMessage = "I'm having trouble connecting to the AI service. Please check your network connection and try again."
        } else if errorDescription.contains("401") || errorDescription.contains("403") {
            errorMessage = "There's an authentication issue with the AI service. Please check your API key and try again."
        } else if errorDescription.contains("402") || errorDescription.lowercased().contains("insufficient credits") {
            // Fallback for 402 if not caught as LLMError
            await showInsufficientCreditsAlert(requested: 0, available: 0)
            return
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

    /// Show a popup alert for insufficient OpenRouter credits
    @MainActor
    private func showInsufficientCreditsAlert(requested: Int, available: Int) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Insufficient OpenRouter Credits"

        if requested > 0 && available > 0 {
            alert.informativeText = """
            This request requires more credits than available.

            Requested: \(requested.formatted()) tokens
            Available: \(available.formatted()) tokens

            Please add credits at OpenRouter to continue using the AI features.
            """
        } else {
            alert.informativeText = """
            Your OpenRouter account has insufficient credits to complete this request.

            Please add credits at OpenRouter to continue using the AI features.
            """
        }

        alert.addButton(withTitle: "Add Credits")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open OpenRouter credits page
            if let url = URL(string: "https://openrouter.ai/settings/credits") {
                NSWorkspace.shared.open(url)
            }
        }

        Logger.warning("💳 Insufficient credits alert shown to user (requested: \(requested), available: \(available))", category: .ai)
    }

    /// Extract call_id from "No tool output found for function call <call_id>" error
    private func extractCallIdFromError(_ errorDescription: String) -> String? {
        // Pattern: "No tool output found for function call call_XXXX"
        guard let range = errorDescription.range(of: "function call ") else { return nil }
        let afterPrefix = errorDescription[range.upperBound...]
        // Find end of call_id (next quote, period, or end)
        if let endRange = afterPrefix.rangeOfCharacter(from: CharacterSet(charactersIn: "\".,} ")) {
            return String(afterPrefix[..<endRange.lowerBound])
        }
        return String(afterPrefix)
    }

    /// Attempt to recover from "No tool output found" error by sending a synthetic tool response
    /// Returns true if recovery was successful
    private func attemptToolOutputRecovery(
        callId: String,
        originalPayload: JSON,
        isSystemGenerated: Bool,
        chatboxMessageId: String?,
        originalText: String?,
        bundledDeveloperMessages: [JSON],
        toolChoice: String?
    ) async -> Bool {
        Logger.info("🔧 Recovery: Sending synthetic tool response for call_id: \(callId)", category: .ai)

        // Build synthetic tool output - acknowledge the error gracefully
        // Note: "status" field is extracted by ConversationContextAssembler and sent to API
        // Valid API statuses are: "in_progress", "completed", "incomplete"
        var toolOutput = JSON()
        toolOutput["status"].string = "incomplete"  // API-level status indicating tool didn't complete normally
        toolOutput["error"].string = "Tool execution was interrupted due to a sync issue. The system has recovered."
        toolOutput["recovered"].bool = true

        // Build tool response request using existing method
        let request = await buildToolResponseRequest(
            output: toolOutput,
            callId: callId,
            reasoningEffort: nil,
            forcedToolChoice: nil
        )

        do {
            // Send the synthetic tool response
            let stream = try await service.responseCreateStream(request)
            for try await streamEvent in stream {
                await networkRouter.handleResponseEvent(streamEvent)

                // Update conversation state when response completes
                if case .responseCompleted(let completed) = streamEvent {
                    let hadToolCalls = completed.response.output.contains { item in
                        if case .functionCall = item { return true }
                        return false
                    }
                    await stateCoordinator.updateConversationState(
                        responseId: completed.response.id,
                        hadToolCalls: hadToolCalls
                    )
                    // Store in conversation context for next request
                    await contextAssembler.storePreviousResponseId(completed.response.id)
                }
            }

            Logger.info("🔧 Recovery: Synthetic tool response sent successfully", category: .ai)

            // Now retry the original user message
            Logger.info("🔧 Recovery: Retrying original user message", category: .ai)

            // Small delay to ensure state is updated
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            // Re-execute the original message
            await executeUserMessage(
                originalPayload,
                isSystemGenerated: isSystemGenerated,
                chatboxMessageId: chatboxMessageId,
                originalText: originalText,
                bundledDeveloperMessages: bundledDeveloperMessages,
                toolChoice: toolChoice
            )

            return true
        } catch {
            Logger.error("🔧 Recovery failed: \(error)", category: .ai)
            return false
        }
    }

    /// Show alert for conversation sync error when auto-recovery fails
    @MainActor
    private func showConversationSyncErrorAlert(callId: String?) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Conversation Recovery Failed"
        alert.informativeText = """
        The AI conversation could not be recovered automatically.

        Your interview data (profile, knowledge cards, timeline) is safely saved.

        You may need to restart the interview. Your collected data will be preserved.
        """

        if let callId = callId {
            alert.informativeText += "\n\nTechnical: call_id: \(callId)"
        }

        alert.addButton(withTitle: "OK")

        _ = alert.runModal()

        Logger.error("🔧 Conversation sync error alert shown - auto-recovery failed (callId: \(callId ?? "unknown"))", category: .ai)
    }
}
