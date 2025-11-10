//
//  LLMMessenger.swift
//  Sprung
//
//  LLM message orchestration (Spec §4.3)
//  Handles sending messages to LLM and emitting status events
//

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
    // MARK: - Properties

    let eventBus: EventCoordinator
    private let networkRouter: NetworkRouter
    private let service: OpenAIService
    private let baseDeveloperMessage: String  // Sent once as developer message on first request, persists via previous_response_id
    private let toolRegistry: ToolRegistry
    private let contextAssembler: ConversationContextAssembler
    private let stateCoordinator: StateCoordinator

    // Active state
    private var isActive = false

    // Phase 3: Stream cancellation tracking
    private var currentStreamTask: Task<Void, Error>?

    // MARK: - Initialization

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

    // MARK: - Event Subscription

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

    // MARK: - Event Handlers

    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmSendUserMessage(let payload, let isSystemGenerated):
            await sendUserMessage(payload, isSystemGenerated: isSystemGenerated)

        case .llmSendDeveloperMessage(let payload):
            await sendDeveloperMessage(payload)

        case .llmToolResponseMessage(let payload):
            await sendToolResponse(payload)

        case .llmExecuteUserMessage(let payload, let isSystemGenerated):
            // Execute stream directly (called from StateCoordinator queue)
            await executeUserMessage(payload, isSystemGenerated: isSystemGenerated)

        case .llmExecuteDeveloperMessage(let payload):
            // Execute stream directly (called from StateCoordinator queue)
            await executeDeveloperMessage(payload)

        case .llmExecuteToolResponse(let payload):
            // Execute stream directly (called from StateCoordinator queue)
            await executeToolResponse(payload)

        case .llmCancelRequested:
            // Phase 3: Cancel current stream
            await cancelCurrentStream()

        default:
            break
        }
    }

    private func handleUserInputEvent(_ event: OnboardingEvent) async {
        // UserInput events are currently handled through .llmSendUserMessage
        // This handler is reserved for future direct user input events
        Logger.debug("LLMMessenger received user input event", category: .ai)
    }

    // MARK: - Message Sending

    /// Send user message to LLM (enqueues via event publication)
    private func sendUserMessage(_ payload: JSON, isSystemGenerated: Bool = false) async {
        guard isActive else {
            Logger.warning("LLMMessenger not active, ignoring message", category: .ai)
            return
        }

        // Publish enqueue event for StateCoordinator to handle
        await emit(.llmEnqueueUserMessage(payload: payload, isSystemGenerated: isSystemGenerated))
    }

    /// Execute user message (called from StateCoordinator queue via event)
    private func executeUserMessage(_ payload: JSON, isSystemGenerated: Bool) async {
        await emit(.llmStatus(status: .busy))

        let text = payload["text"].stringValue

        do {
            let request = await buildUserMessageRequest(text: text, isSystemGenerated: isSystemGenerated)
            let messageId = UUID().uuidString

            // Emit message sent event
            await emit(.llmUserMessageSent(messageId: messageId, payload: payload, isSystemGenerated: isSystemGenerated))

            // Process stream via NetworkRouter
            currentStreamTask = Task {
                Logger.info("🔍 About to call service.responseCreateStream, service type: \(type(of: service))", category: .ai)

                // Debug: Log request details
                Logger.debug("📋 Request model: \(request.model)", category: .ai)
                Logger.debug("📋 Request has previousResponseId: \(request.previousResponseId != nil)", category: .ai)
                Logger.debug("📋 Request store: \(String(describing: request.store))", category: .ai)

                let stream = try await service.responseCreateStream(request)
                for try await streamEvent in stream {
                    await networkRouter.handleResponseEvent(streamEvent)

                    // Track conversation state
                    if case .responseCompleted(let completed) = streamEvent {
                        // Update StateCoordinator (single source of truth)
                        await stateCoordinator.updateConversationState(
                            conversationId: completed.response.id,
                            responseId: completed.response.id
                        )
                        // Store in conversation context for next request
                        await contextAssembler.storePreviousResponseId(completed.response.id)
                    }
                }
                await emit(.llmStatus(status: .idle))
            }

            try await currentStreamTask?.value
            currentStreamTask = nil

            // Notify StateCoordinator that stream completed
            await stateCoordinator.markStreamCompleted()

        } catch is CancellationError {
            Logger.info("User message stream cancelled", category: .ai)
            // Notify StateCoordinator even on cancellation
            await stateCoordinator.markStreamCompleted()
        } catch {
            Logger.error("❌ Failed to send message: \(error)", category: .ai)
            await emit(.errorOccurred("Failed to send message: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
            // Surface error as visible assistant message
            await surfaceErrorToUI(error: error)
            // Notify StateCoordinator even on error
            await stateCoordinator.markStreamCompleted()
        }
    }

    /// Send developer message (system instructions) - enqueues via event publication
    private func sendDeveloperMessage(_ payload: JSON) async {
        guard isActive else {
            Logger.warning("LLMMessenger not active, ignoring developer message", category: .ai)
            return
        }

        // Publish enqueue event for StateCoordinator to handle
        await emit(.llmEnqueueDeveloperMessage(payload: payload))
    }

    /// Execute developer message (called from StateCoordinator queue via event)
    private func executeDeveloperMessage(_ payload: JSON) async {
        await emit(.llmStatus(status: .busy))

        let text = payload["text"].stringValue
        let toolChoiceName = payload["toolChoice"].string

        // Add telemetry
        Logger.info("📨 Sending developer message (\(text.prefix(100))...)", category: .ai)

        do {
            let request = await buildDeveloperMessageRequest(text: text, toolChoice: toolChoiceName)
            let messageId = UUID().uuidString

            // Emit message sent event
            await emit(.llmDeveloperMessageSent(messageId: messageId, payload: payload))

            // Process stream via NetworkRouter
            currentStreamTask = Task {
                let stream = try await service.responseCreateStream(request)
                for try await streamEvent in stream {
                    await networkRouter.handleResponseEvent(streamEvent)

                    // Track conversation state
                    if case .responseCompleted(let completed) = streamEvent {
                        // Update StateCoordinator (single source of truth)
                        await stateCoordinator.updateConversationState(
                            conversationId: completed.response.id,
                            responseId: completed.response.id
                        )
                        // Store in conversation context for next request
                        await contextAssembler.storePreviousResponseId(completed.response.id)
                    }
                }
                await emit(.llmStatus(status: .idle))
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
        // Publish enqueue event for StateCoordinator to handle
        await emit(.llmEnqueueToolResponse(payload: payload))
    }

    /// Execute tool response (called from StateCoordinator queue via event)
    private func executeToolResponse(_ payload: JSON) async {
        await emit(.llmStatus(status: .busy))

        do {
            let callId = payload["callId"].stringValue
            let output = payload["output"]

            // Log the tool response at appropriate levels
            Logger.debug("📤 Tool response payload: callId=\(callId), output=\(output.rawString() ?? "nil")", category: .ai)
            Logger.info("📤 Sending tool response for callId=\(String(callId.prefix(12)))...", category: .ai)

            let request = await buildToolResponseRequest(output: output, callId: callId)

            // Log request details
            Logger.debug("📦 Tool response request: previousResponseId=\(request.previousResponseId ?? "nil")", category: .ai)

            let messageId = UUID().uuidString

            // Emit message sent event
            await emit(.llmSentToolResponseMessage(messageId: messageId, payload: payload))
            
            // Process stream via NetworkRouter
            currentStreamTask = Task {
                do {
                    let stream = try await service.responseCreateStream(request)
                    for try await streamEvent in stream {
                        await networkRouter.handleResponseEvent(streamEvent)

                        if case .responseCompleted(let completed) = streamEvent {
                            // Update StateCoordinator (single source of truth)
                            await stateCoordinator.updateConversationState(
                                conversationId: completed.response.id,
                                responseId: completed.response.id
                            )
                            // Store in conversation context for next request
                            await contextAssembler.storePreviousResponseId(completed.response.id)
                        }
                    }
                    await emit(.llmStatus(status: .idle))
                } catch {
                    // Log detailed error for debugging
                    Logger.error("❌ Tool response stream failed: \(error)", category: .ai)
                    if let apiError = error as? APIError {
                        Logger.error("❌ API Error details: \(apiError)", category: .ai)
                    }
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

    // MARK: - Request Building

    private func buildUserMessageRequest(text: String, isSystemGenerated: Bool) async -> ModelResponseParameter {
        // Use previous_response_id for context management (OpenAI manages conversation history)
        let previousResponseId = await contextAssembler.getPreviousResponseId()

        // Current user message
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
        parameters.parallelToolCalls = false

        Logger.info("📝 Built request: previousResponseId=\(previousResponseId ?? "nil"), inputItems=\(inputItems.count)", category: .ai)
        return parameters
    }

    /// Determine appropriate tool_choice for the given message context
    private func determineToolChoice(for text: String, isSystemGenerated: Bool) async -> ToolChoiceMode {
        // For system-generated messages (like phase prompts), always allow tools
        // The phase prompt itself will guide the LLM on what tools to use
        if isSystemGenerated {
            Logger.info("✅ Allowing tools for system-generated message (phase prompt)", category: .ai)
            return .auto
        }

        // For user-generated messages: Force .none on the very first request to guarantee a textual greeting
        let hasStreamed = await stateCoordinator.getHasStreamedFirstResponse()
        if !hasStreamed {
            Logger.info("🚫 Forcing toolChoice=.none for first user request to ensure greeting", category: .ai)
            return .none
        }

        // After first response, let LLM use tools naturally
        return .auto
    }

    private func buildDeveloperMessageRequest(
        text: String,
        toolChoice toolChoiceName: String? = nil
    ) async -> ModelResponseParameter {
        let previousResponseId = await contextAssembler.getPreviousResponseId()

        var inputItems: [InputItem] = []

        // On FIRST request only: prepend base developer message before phase instructions
        if previousResponseId == nil {
            inputItems.append(.message(InputMessage(
                role: "developer",
                content: .text(baseDeveloperMessage)
            )))
            Logger.info("📋 Including base developer message (first request)", category: .ai)
        }

        // Current developer message (phase instructions)
        inputItems.append(.message(InputMessage(
            role: "developer",
            content: .text(text)
        )))

        let tools = await getToolSchemas()

        // Determine tool choice - force specific tool if requested
        let toolChoice: ToolChoiceMode
        if let toolName = toolChoiceName {
            // Force the model to call this specific function using the tool_choice parameter
            toolChoice = .functionTool(FunctionTool(name: toolName))
            Logger.debug("Tool choice set to force function: \(toolName)", category: .ai)
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
        parameters.parallelToolCalls = false

        Logger.info("📝 Built developer message request: previousResponseId=\(previousResponseId ?? "nil"), inputItems=\(inputItems.count)", category: .ai)
        return parameters
    }

    private func buildToolResponseRequest(output: JSON, callId: String) async -> ModelResponseParameter {
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
        parameters.parallelToolCalls = false

        return parameters
    }

    /// Get tool schemas from ToolRegistry, filtered by allowed tools from StateCoordinator
    private func getToolSchemas() async -> [Tool] {
        let allowedNames = await stateCoordinator.getAllowedToolNames()
        let filterNames = allowedNames.isEmpty ? nil : allowedNames
        return await toolRegistry.toolSchemas(filteredBy: filterNames)
    }

    // MARK: - Lifecycle

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


    // MARK: - Stream Cancellation (Phase 2)

    /// Cancel the currently running stream
    ///
    /// This method handles immediate cancellation of LLM streaming responses:
    /// - Cancels the active network stream task
    /// - Finalizes partial messages (displayed in chat as-is or marked cancelled)
    /// - Updates UI state to idle
    ///
    /// Note on tool execution: If tool calls were emitted before cancellation,
    /// they will continue executing. This is intentional - cancellation stops
    /// the LLM from generating more output, not already-started tool operations.
    private func cancelCurrentStream() async {
        guard let task = currentStreamTask else {
            Logger.debug("No active stream to cancel", category: .ai)
            return
        }

        Logger.info("🛑 Cancelling LLM stream...", category: .ai)

        // Cancel the stream task
        task.cancel()
        currentStreamTask = nil

        // Clean up partial messages in NetworkRouter
        await networkRouter.cancelPendingStreams()

        // Emit idle status to update UI
        await emit(.llmStatus(status: .idle))

        Logger.info("✅ LLM stream cancelled and cleaned up", category: .ai)
    }

    // MARK: - Error Handling

    /// Surface bootstrap and API errors as visible assistant messages
    private func surfaceErrorToUI(error: Error) async {
        let errorMessage: String

        // Provide user-friendly error messages based on error type
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

        // Emit a system-generated user message with the error
        let payload = JSON(["text": errorMessage])
        await emit(.llmUserMessageSent(messageId: UUID().uuidString, payload: payload, isSystemGenerated: true))

        Logger.error("📢 Error surfaced to UI: \(errorMessage)", category: .ai)
    }
}
