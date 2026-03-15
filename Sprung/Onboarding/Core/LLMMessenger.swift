//
//  LLMMessenger.swift
//  Sprung
//
//  LLM message orchestration (Spec §4.3)
//  Uses LLMFacade for all LLM operations while maintaining domain orchestration.
//  Delegates to extracted components for retry, error handling, and recovery.
//

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
    private let llmFacade: LLMFacade
    private let stateCoordinator: StateCoordinator
    private let anthropicRequestBuilder: AnthropicRequestBuilder
    private let toolRegistry: ToolRegistry
    private var isActive = false

    // Extracted components
    private let retryPolicy = LLMRetryPolicy()
    private let errorHandler = LLMErrorHandler()

    // Stream cancellation tracking
    private var currentStreamTask: Task<Void, Error>?

    init(
        llmFacade: LLMFacade,
        baseSystemPrompt: String,
        eventBus: EventCoordinator,
        networkRouter: NetworkRouter,
        toolRegistry: ToolRegistry,
        state: StateCoordinator,
        todoStore: InterviewTodoStore
    ) {
        self.llmFacade = llmFacade
        self.eventBus = eventBus
        self.networkRouter = networkRouter
        self.stateCoordinator = state
        self.toolRegistry = toolRegistry
        self.anthropicRequestBuilder = AnthropicRequestBuilder(
            baseSystemPrompt: baseSystemPrompt,
            toolRegistry: toolRegistry,
            contextAssembler: ConversationContextAssembler(state: state),
            stateCoordinator: state,
            todoStore: todoStore
        )
        Logger.info("📬 LLMMessenger initialized (Anthropic-only)", category: .ai)
    }

    // MARK: - Backend (Anthropic-only)

    // Onboarding interview uses Anthropic Messages API exclusively.
    // OpenAI Responses API support has been removed.
    /// Start listening to message request events
    func startEventSubscriptions() async {
        Task {
            for await event in await self.eventBus.stream(topic: .llm) {
                await self.handleLLMEvent(event)
            }
        }
        // Small delay to ensure streams are connected before returning
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        Logger.verbose("📡 LLMMessenger subscribed to events", category: .ai)
    }
    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llm(.sendUserMessage(let payload, let isSystemGenerated, let chatboxMessageId, let originalText)):
            guard isActive else {
                Logger.warning("LLMMessenger not active, ignoring message", category: .ai)
                return
            }
            await emit(.llm(.enqueueUserMessage(
                payload: payload,
                isSystemGenerated: isSystemGenerated,
                chatboxMessageId: chatboxMessageId,
                originalText: originalText
            )))
        case .llm(.toolResponseMessage(let payload)):
            await emit(.llm(.enqueueToolResponse(payload: payload)))
        case .llm(.executeUserMessage(let payload, let isSystemGenerated, let chatboxMessageId, let originalText, let bundledCoordinatorMessages)):
            await executeUserMessage(payload, isSystemGenerated: isSystemGenerated, chatboxMessageId: chatboxMessageId, originalText: originalText, bundledCoordinatorMessages: bundledCoordinatorMessages)
        case .llm(.executeToolResponse(let payload)):
            await executeToolResponse(payload)
        case .llm(.executeBatchedToolResponses(let payloads)):
            await executeBatchedToolResponses(payloads)
        case .llm(.executeCoordinatorMessage(let payload)):
            await executeCoordinatorMessage(payload)
        case .llm(.cancelRequested):
            await cancelCurrentStream()
        default:
            break
        }
    }

    private func executeUserMessage(_ payload: JSON, isSystemGenerated: Bool, chatboxMessageId: String? = nil, originalText: String? = nil, bundledCoordinatorMessages: [JSON] = []) async {
        // Anthropic-only: directly call Anthropic implementation
        await executeUserMessageViaAnthropic(
            payload,
            isSystemGenerated: isSystemGenerated,
            chatboxMessageId: chatboxMessageId,
            originalText: originalText,
            bundledCoordinatorMessages: bundledCoordinatorMessages
        )
    }
    private func executeCoordinatorMessage(_ payload: JSON) async {
        guard isActive else {
            Logger.warning("LLMMessenger not active, ignoring coordinator message", category: .ai)
            return
        }
        await executeCoordinatorMessageViaAnthropic(payload)
    }

    private func executeToolResponse(_ payload: JSON) async {
        await executeToolResponseViaAnthropic(payload)
    }
    /// Execute batched tool responses (for parallel tool calls)
    private func executeBatchedToolResponses(_ payloads: [JSON]) async {
        await executeBatchedToolResponsesViaAnthropic(payloads)
    }

    func activate() {
        isActive = true
        Logger.info("✅ LLMMessenger activated", category: .ai)
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
        await emit(.llm(.status( .idle)))
        Logger.info("✅ LLM stream cancelled and cleaned up", category: .ai)
    }
    // MARK: - Error Handling (Delegated to LLMErrorHandler)

    private func surfaceErrorToUI(error: Error) async {
        // Check for insufficient credits error - show popup alert
        if errorHandler.isInsufficientCreditsError(error) {
            let creditInfo = errorHandler.extractCreditInfo(from: error)
            await errorHandler.showInsufficientCreditsAlert(
                requested: creditInfo?.requested ?? 0,
                available: creditInfo?.available ?? 0
            )
            return
        }

        let errorMessage = errorHandler.buildUserFriendlyMessage(from: error)
        let payload = JSON(["text": errorMessage])
        await emit(.llm(.userMessageSent(messageId: UUID().uuidString, payload: payload, isSystemGenerated: true)))
        Logger.error("📢 Error surfaced to UI: \(errorMessage)", category: .ai)
    }

    // MARK: - Anthropic Stream Execution

    /// Shared retry/stream loop for all Anthropic API calls.
    /// Handles retry with exponential backoff, stream iteration via AnthropicStreamAdapter,
    /// domain event emission, and tool call dispatch.
    /// - Parameters:
    ///   - request: The Anthropic message parameters to stream
    ///   - errorContext: Label for error logging (e.g. "user message", "tool response")
    ///   - onStreamSuccess: Closure called after the stream completes successfully, before emitting idle status
    private func executeAnthropicStream(
        request: AnthropicMessageParameter,
        errorContext: String,
        onStreamSuccess: @Sendable @escaping () async -> Void = {}
    ) async throws {
        currentStreamTask = Task {
            var retryCount = 0
            var lastError: Error?

            while retryCount <= retryPolicy.maxRetries {
                do {
                    let stream = try await llmFacade.anthropicMessagesStream(parameters: request)
                    var adapter = AnthropicStreamAdapter()

                    for try await event in stream {
                        let domainEvents = adapter.process(event)
                        for domainEvent in domainEvents {
                            await emit(domainEvent)

                            if case .tool(.callRequested(let call, _)) = domainEvent {
                                await executeToolCall(call)
                            }
                        }
                    }

                    await onStreamSuccess()
                    await emit(.llm(.status(.idle)))
                    return
                } catch {
                    lastError = error
                    if retryPolicy.isRetriable(error) && retryPolicy.shouldRetry(attempt: retryCount) {
                        retryCount += 1
                        let delay = retryPolicy.retryDelay(for: retryCount)
                        Logger.warning("Anthropic transient error (attempt \(retryCount)/\(retryPolicy.maxRetries)), retrying in \(delay)s: \(error)", category: .ai)
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    } else {
                        errorHandler.logAnthropicError(error, context: errorContext)
                        throw error
                    }
                }
            }

            if let error = lastError {
                Logger.error("Anthropic \(errorContext) failed after \(retryPolicy.maxRetries) retries: \(error)", category: .ai)
                throw error
            }
        }

        try await currentStreamTask?.value
        currentStreamTask = nil
    }

    // MARK: - Anthropic Execution Methods

    /// Execute user message via Anthropic Messages API
    private func executeUserMessageViaAnthropic(
        _ payload: JSON,
        isSystemGenerated: Bool,
        chatboxMessageId: String? = nil,
        originalText: String? = nil,
        bundledCoordinatorMessages: [JSON] = []
    ) async {
        await emit(.llm(.status(.busy)))
        let text = payload["content"].string ?? payload["text"].stringValue

        // Extract file attachment data if present (image or PDF)
        // PDF data takes precedence if both are present
        let fileData: String?
        let fileContentType: String?
        if let pdfData = payload["pdfData"].string {
            fileData = pdfData
            fileContentType = "application/pdf"
            Logger.info("PDF attachment detected in user message payload", category: .ai)
        } else {
            fileData = payload["imageData"].string
            fileContentType = payload["contentType"].string
        }

        do {
            let request = try await anthropicRequestBuilder.buildUserMessageRequest(
                text: text,
                isSystemGenerated: isSystemGenerated,
                bundledCoordinatorMessages: bundledCoordinatorMessages,
                imageBase64: fileData,
                imageContentType: fileContentType
            )
            let messageId = UUID().uuidString
            await emit(.llm(.userMessageSent(messageId: messageId, payload: payload, isSystemGenerated: isSystemGenerated)))

            try await executeAnthropicStream(request: request, errorContext: "user message")
            await stateCoordinator.markStreamCompleted()
        } catch is CancellationError {
            Logger.verbose("Anthropic user message stream cancelled", category: .ai)
            await stateCoordinator.markStreamCompleted()
        } catch {
            errorHandler.logAnthropicError(error, context: "user message (outer)")
            Logger.error("Anthropic failed to send message: \(error)", category: .ai)
            await emit(.processing(.errorOccurred("Failed to send message: \(error.localizedDescription)")))
            await emit(.llm(.status(.error)))

            if let chatboxMessageId = chatboxMessageId, let originalText = originalText {
                await emit(.llm(.userMessageFailed(
                    messageId: chatboxMessageId,
                    originalText: originalText,
                    error: error.localizedDescription
                )))
            } else {
                await surfaceErrorToUI(error: error)
            }
            await stateCoordinator.markStreamCompleted()
        }
    }

    /// Execute developer message via Anthropic Messages API
    private func executeCoordinatorMessageViaAnthropic(_ payload: JSON) async {
        await emit(.llm(.status(.busy)))
        let text = payload["text"].stringValue
        Logger.info("Sending Anthropic developer message (\(text.prefix(100))...)", category: .ai)

        do {
            let request = try await anthropicRequestBuilder.buildCoordinatorMessageRequest(text: text)
            let messageId = UUID().uuidString
            await emit(.llm(.coordinatorMessageSent(messageId: messageId, payload: payload)))

            try await executeAnthropicStream(request: request, errorContext: "developer message")
            Logger.verbose("Anthropic developer message completed successfully", category: .ai)
            await stateCoordinator.markStreamCompleted()
        } catch is CancellationError {
            Logger.verbose("Anthropic developer message stream cancelled", category: .ai)
            await stateCoordinator.markStreamCompleted()
        } catch {
            errorHandler.logAnthropicError(error, context: "developer message (outer)")
            await emit(.processing(.errorOccurred("Failed to send developer message: \(error.localizedDescription)")))
            await emit(.llm(.status(.error)))
            await surfaceErrorToUI(error: error)
            await stateCoordinator.markStreamCompleted()
        }
    }

    /// Execute tool response via Anthropic Messages API
    private func executeToolResponseViaAnthropic(_ payload: JSON) async {
        await emit(.llm(.status(.busy)))
        await stateCoordinator.setPendingToolResponses([payload])

        do {
            let callId = payload["callId"].stringValue
            let toolName = payload["toolName"].stringValue
            let instruction = payload["instruction"].string
            let pdfBase64 = payload["pdfData"].string
            let pdfFilename = payload["pdfFilename"].string

            Logger.debug("Anthropic tool response: callId=\(callId), tool=\(toolName)", category: .ai)
            if let instruction = instruction {
                Logger.debug("Instruction attached: \(instruction.prefix(50))...", category: .ai)
            }
            if pdfBase64 != nil {
                Logger.info("PDF attachment included: \(pdfFilename ?? "unknown")", category: .ai)
            }
            Logger.verbose("Sending Anthropic tool response for callId=\(String(callId.prefix(12)))...", category: .ai)

            let request = try await anthropicRequestBuilder.buildToolResponseRequest(
                callId: callId,
                instruction: instruction,
                pdfBase64: pdfBase64,
                pdfFilename: pdfFilename
            )

            if let requestData = try? JSONEncoder().encode(request) {
                let requestKB = Double(requestData.count) / 1024.0
                Logger.verbose("Anthropic request size: \(String(format: "%.1f", requestKB)) KB (\(requestData.count) bytes)", category: .ai)
                if requestKB > 100 {
                    Logger.warning("Large Anthropic request (>100KB) - may hit API limits", category: .ai)
                }
            }

            let messageId = UUID().uuidString
            await emit(.llm(.sentToolResponseMessage(messageId: messageId, payload: payload)))

            let stateCoord = stateCoordinator
            try await executeAnthropicStream(
                request: request,
                errorContext: "tool response",
                onStreamSuccess: { await stateCoord.clearPendingToolResponses() }
            )
            await stateCoordinator.markStreamCompleted()
        } catch is CancellationError {
            Logger.verbose("Anthropic tool response stream cancelled", category: .ai)
            await stateCoordinator.markStreamCompleted()
        } catch {
            errorHandler.logAnthropicError(error, context: "tool response (outer)")
            await emit(.processing(.errorOccurred("Failed to send Anthropic tool response: \(error.localizedDescription)")))
            await emit(.llm(.status(.error)))
            await stateCoordinator.markStreamCompleted()
        }
    }

    /// Execute batched tool responses via Anthropic Messages API
    private func executeBatchedToolResponsesViaAnthropic(_ payloads: [JSON]) async {
        await emit(.llm(.status(.busy)))
        await stateCoordinator.setPendingToolResponses(payloads)

        do {
            Logger.info("Sending Anthropic batched tool responses (\(payloads.count) responses)", category: .ai)

            let request = try await anthropicRequestBuilder.buildBatchedToolResponseRequest(payloads: payloads)
            let messageId = UUID().uuidString

            for payload in payloads {
                await emit(.llm(.sentToolResponseMessage(messageId: messageId, payload: payload)))
            }

            let stateCoord = stateCoordinator
            try await executeAnthropicStream(
                request: request,
                errorContext: "batched tool response",
                onStreamSuccess: { await stateCoord.clearPendingToolResponses() }
            )
            await stateCoordinator.markStreamCompleted()
        } catch is CancellationError {
            Logger.verbose("Anthropic batched tool response stream cancelled", category: .ai)
            await stateCoordinator.markStreamCompleted()
        } catch {
            errorHandler.logAnthropicError(error, context: "batched tool response (outer)")
            await emit(.processing(.errorOccurred("Failed to send Anthropic batched tool responses: \(error.localizedDescription)")))
            await emit(.llm(.status(.error)))
            await stateCoordinator.markStreamCompleted()
        }
    }

    /// Execute a tool call received from Anthropic
    /// This dispatches to the tool registry for execution
    private func executeToolCall(_ call: ToolCall) async {
        // The tool call event has already been emitted
        // The tool executor (ToolOrchestrator) will pick it up and execute
        Logger.debug("🔧 Anthropic tool call dispatched: \(call.name)", category: .ai)
    }

}
