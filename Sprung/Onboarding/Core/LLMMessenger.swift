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
    private var systemPrompt: String
    private let toolRegistry: ToolRegistry
    private let contextAssembler: ConversationContextAssembler

    // Conversation tracking
    private var conversationId: String?
    private var lastResponseId: String?
    private var currentModelId: String = "gpt-5"
    private var isActive = false

    // Tool continuation tracking

    // Allowed tools from StateCoordinator
    private var allowedToolNames: Set<String> = []

    // Phase 3: Stream cancellation tracking
    private var currentStreamTask: Task<Void, Error>?

    // Request serialization: ensure only one stream runs at a time
    private var isStreaming = false
    private var requestQueue: [() async -> Void] = []
    private var hasStreamedFirstResponse = false  // Track if we've had at least one response

    // MARK: - Initialization

    init(
        service: OpenAIService,
        systemPrompt: String,
        eventBus: EventCoordinator,
        networkRouter: NetworkRouter,
        toolRegistry: ToolRegistry,
        state: StateCoordinator
    ) {
        self.service = service
        self.systemPrompt = systemPrompt
        self.eventBus = eventBus
        self.networkRouter = networkRouter
        self.toolRegistry = toolRegistry
        self.contextAssembler = ConversationContextAssembler(state: state)
        Logger.info("📬 LLMMessenger initialized with ConversationContextAssembler", category: .ai)
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

        Task {
            for await event in await self.eventBus.stream(topic: .state) {
                await self.handleStateEvent(event)
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

    private func handleStateEvent(_ event: OnboardingEvent) async {
        switch event {
        case .stateAllowedToolsUpdated(let tools):
            allowedToolNames = tools
            Logger.info("🔧 LLMMessenger updated allowed tools: \(tools.count) tools", category: .ai)

        default:
            break
        }
    }

    // MARK: - Message Sending

    /// Send user message to LLM
    private func sendUserMessage(_ payload: JSON, isSystemGenerated: Bool = false) async {
        guard isActive else {
            Logger.warning("LLMMessenger not active, ignoring message", category: .ai)
            return
        }

        // Enqueue the request to serialize with other streaming calls
        enqueueRequest { [weak self] in
            guard let self else { return }
            await self.executeUserMessage(payload, isSystemGenerated: isSystemGenerated)
        }
    }

    /// Execute user message (called from queue)
    private func executeUserMessage(_ payload: JSON, isSystemGenerated: Bool) async {
        await emit(.llmStatus(status: .busy))

        let text = payload["text"].stringValue

        do {
            let request = await buildUserMessageRequest(text: text)
            let messageId = UUID().uuidString

            // Emit message sent event
            await emit(.llmUserMessageSent(messageId: messageId, payload: payload, isSystemGenerated: isSystemGenerated))

            // Process stream via NetworkRouter
            currentStreamTask = Task {
                let stream = try await service.responseCreateStream(request)
                for try await streamEvent in stream {
                    await networkRouter.handleResponseEvent(streamEvent)

                    // Track conversation state
                    if case .responseCompleted(let completed) = streamEvent {
                        conversationId = completed.response.id
                        lastResponseId = completed.response.id
                        // Store in conversation context for next request
                        await contextAssembler.storePreviousResponseId(completed.response.id)
                        hasStreamedFirstResponse = true
                    }
                }
                await emit(.llmStatus(status: .idle))
            }

            try await currentStreamTask?.value
            currentStreamTask = nil

        } catch is CancellationError {
            Logger.info("User message stream cancelled", category: .ai)
            // Status already set to idle by cancelCurrentStream()
        } catch {
            Logger.error("❌ Failed to send message: \(error)", category: .ai)
            await emit(.errorOccurred("Failed to send message: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
            // Surface error as visible assistant message
            await surfaceErrorToUI(error: error)
        }
    }

    /// Send developer message (system instructions)
    private func sendDeveloperMessage(_ payload: JSON) async {
        guard isActive else {
            Logger.warning("LLMMessenger not active, ignoring developer message", category: .ai)
            return
        }

        // Enqueue the request to serialize with other streaming calls
        enqueueRequest { [weak self] in
            guard let self else { return }
            await self.executeDeveloperMessage(payload)
        }
    }

    /// Execute developer message (called from queue)
    private func executeDeveloperMessage(_ payload: JSON) async {
        await emit(.llmStatus(status: .busy))

        let text = payload["text"].stringValue
        let forceToolName = payload["forceToolName"].string

        // Add telemetry
        Logger.info("📨 Sending developer message (\(text.prefix(100))...)", category: .ai)

        do {
            let request = await buildDeveloperMessageRequest(text: text, forceToolName: forceToolName)
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
                        conversationId = completed.response.id
                        lastResponseId = completed.response.id
                        // Store in conversation context for next request
                        await contextAssembler.storePreviousResponseId(completed.response.id)
                        hasStreamedFirstResponse = true
                    }
                }
                await emit(.llmStatus(status: .idle))
            }

            try await currentStreamTask?.value
            currentStreamTask = nil

            Logger.info("✅ Developer message completed successfully", category: .ai)

        } catch is CancellationError {
            Logger.info("Developer message stream cancelled", category: .ai)
            // Status already set to idle by cancelCurrentStream()
        } catch {
            Logger.error("❌ Failed to send developer message: \(error)", category: .ai)
            await emit(.errorOccurred("Failed to send developer message: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
            // Surface error as visible assistant message
            await surfaceErrorToUI(error: error)
        }
    }

    /// Send tool response back to LLM
    private func sendToolResponse(_ payload: JSON) async {
        await emit(.llmStatus(status: .busy))

        do {
            let callId = payload["callId"].stringValue
            let output = payload["output"]

            let request = await buildToolResponseRequest(output: output, callId: callId)
            let messageId = UUID().uuidString

            // Emit message sent event
            await emit(.llmSentToolResponseMessage(messageId: messageId, payload: payload))

            // Process stream via NetworkRouter
            currentStreamTask = Task {
                let stream = try await service.responseCreateStream(request)
                for try await streamEvent in stream {
                    await networkRouter.handleResponseEvent(streamEvent)

                    if case .responseCompleted(let completed) = streamEvent {
                        conversationId = completed.response.id
                        lastResponseId = completed.response.id
                    }
                }
                await emit(.llmStatus(status: .idle))
            }

            try await currentStreamTask?.value
            currentStreamTask = nil

        } catch is CancellationError {
            Logger.info("Tool response stream cancelled", category: .ai)
            // Status already set to idle by cancelCurrentStream()
        } catch {
            await emit(.errorOccurred("Failed to send tool response: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
        }
    }

    // MARK: - Request Building

    private func buildUserMessageRequest(text: String) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForUserMessage(
            text: text
        )

        let tools = await getToolSchemas()
        let scratchpad = await contextAssembler.buildScratchpadSummary()
        let metadata = scratchpad.isEmpty ? nil : ["scratchpad": scratchpad]
        let previousResponseId = await contextAssembler.getPreviousResponseId()

        // Determine tool_choice based on context
        let toolChoice = determineToolChoice(for: text)

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            conversation: nil,
            instructions: systemPrompt,
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.metadata = metadata
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = false

        return parameters
    }

    /// Determine appropriate tool_choice for the given message context
    private func determineToolChoice(for text: String) -> ToolChoiceMode {
        // Force .none on the very first request to guarantee a textual greeting before tools
        if !hasStreamedFirstResponse {
            Logger.info("🚫 Forcing toolChoice=.none for first request to ensure greeting", category: .ai)
            return .none
        }

        // After first response, let LLM use tools naturally
        return .auto
    }

    private func buildDeveloperMessageRequest(
        text: String,
        forceToolName: String? = nil
    ) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForDeveloperMessage(
            text: text
        )

        let tools = await getToolSchemas()
        let scratchpad = await contextAssembler.buildScratchpadSummary()
        let metadata = scratchpad.isEmpty ? nil : ["scratchpad": scratchpad]
        let previousResponseId = await contextAssembler.getPreviousResponseId()

        // Determine tool choice - force specific tool if requested
        let toolChoice: ToolChoiceMode
        if let toolName = forceToolName {
            // Use .auto to allow both text and tool calls
            // The developer instruction explicitly tells the LLM which tool to call
            // and that it "MUST" call it, which is sufficient guidance
            toolChoice = .auto
            Logger.debug("Tool choice set to auto (developer instruction specifies: \(toolName))", category: .ai)
        } else {
            toolChoice = .auto
        }

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            conversation: nil,
            instructions: systemPrompt,
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.metadata = metadata
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = false

        return parameters
    }

    private func buildToolResponseRequest(output: JSON, callId: String) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForToolResponse(
            output: output,
            callId: callId
        )

        let tools = await getToolSchemas()
        let scratchpad = await contextAssembler.buildScratchpadSummary()
        let metadata = scratchpad.isEmpty ? nil : ["scratchpad": scratchpad]
        let previousResponseId = await contextAssembler.getPreviousResponseId()

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            conversation: nil,
            instructions: systemPrompt,
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.metadata = metadata
        parameters.stream = true
        parameters.toolChoice = .auto
        parameters.tools = tools
        parameters.parallelToolCalls = false

        return parameters
    }

    /// Get tool schemas from ToolRegistry, filtered by allowed tools
    private func getToolSchemas() async -> [Tool] {
        let allowedNames = allowedToolNames.isEmpty ? nil : allowedToolNames
        return await toolRegistry.toolSchemas(filteredBy: allowedNames)
    }

    // MARK: - Lifecycle

    func activate() {
        isActive = true
        conversationId = nil
        lastResponseId = nil
        Logger.info("✅ LLMMessenger activated", category: .ai)
    }

    func deactivate() {
        isActive = false
        conversationId = nil
        lastResponseId = nil
        Logger.info("⏹️ LLMMessenger deactivated", category: .ai)
    }

    func setModelId(_ modelId: String) {
        currentModelId = modelId
        Logger.info("🔧 LLMMessenger model set to: \(modelId)", category: .ai)
    }

    // MARK: - Dynamic Prompt Update (Phase 3)

    /// Update the system prompt (used when phases transition)
    func updateSystemPrompt(_ text: String) {
        systemPrompt = text
        Logger.info("📝 LLMMessenger system prompt updated (\(text.count) chars)", category: .ai)
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

    // MARK: - Request Queue Management

    /// Enqueue a request to ensure serial processing
    private func enqueueRequest(_ request: @escaping () async -> Void) {
        requestQueue.append(request)
        Logger.debug("📥 Request enqueued (queue size: \(requestQueue.count))", category: .ai)

        // If not currently streaming, process the queue
        if !isStreaming {
            Task {
                await processQueue()
            }
        }
    }

    /// Process the request queue serially
    private func processQueue() async {
        while !requestQueue.isEmpty {
            guard !isStreaming else {
                Logger.debug("⏸️ Queue processing paused (stream in progress)", category: .ai)
                return
            }

            isStreaming = true
            let request = requestQueue.removeFirst()
            Logger.debug("▶️ Processing request from queue (\(requestQueue.count) remaining)", category: .ai)

            await request()

            isStreaming = false
            Logger.debug("✅ Request completed (queue size: \(requestQueue.count))", category: .ai)
        }
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
