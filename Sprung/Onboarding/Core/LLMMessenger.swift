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
    func startEventSubscriptions() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                // Subscribe to LLM topic for message requests
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .llm) {
                        await self.handleLLMEvent(event)
                    }
                }

                // Subscribe to UserInput for chat messages
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .userInput) {
                        await self.handleUserInputEvent(event)
                    }
                }

                // Subscribe to State for allowed tools
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .state) {
                        await self.handleStateEvent(event)
                    }
                }
            }
        }

        Logger.info("📡 LLMMessenger subscribed to events", category: .ai)
    }

    // MARK: - Event Handlers

    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .llmSendUserMessage(let payload):
            await sendUserMessage(payload)

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
    private func sendUserMessage(_ payload: JSON) async {
        guard isActive else {
            Logger.warning("LLMMessenger not active, ignoring message", category: .ai)
            return
        }

        await emit(.llmStatus(status: .busy))

        let text = payload["text"].stringValue

        do {
            let request = await buildUserMessageRequest(text: text)
            let messageId = UUID().uuidString

            // Emit message sent event
            await emit(.llmUserMessageSent(messageId: messageId, payload: payload))

            // Process stream via NetworkRouter
            currentStreamTask = Task {
                let stream = try await service.responseCreateStream(request)
                for try await streamEvent in stream {
                    await networkRouter.handleResponseEvent(streamEvent)

                    // Track conversation state
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
            Logger.info("User message stream cancelled", category: .ai)
            // Status already set to idle by cancelCurrentStream()
        } catch {
            await emit(.errorOccurred("Failed to send message: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
        }
    }

    /// Send developer message (system instructions)
    private func sendDeveloperMessage(_ payload: JSON) async {
        guard isActive else {
            Logger.warning("LLMMessenger not active, ignoring developer message", category: .ai)
            return
        }

        await emit(.llmStatus(status: .busy))

        let text = payload["text"].stringValue

        do {
            let request = await buildDeveloperMessageRequest(text: text)
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
                    }
                }
                await emit(.llmStatus(status: .idle))
            }

            try await currentStreamTask?.value
            currentStreamTask = nil

        } catch is CancellationError {
            Logger.info("Developer message stream cancelled", category: .ai)
            // Status already set to idle by cancelCurrentStream()
        } catch {
            await emit(.errorOccurred("Failed to send developer message: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
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
            text: text,
            systemPrompt: systemPrompt,
            allowedTools: allowedToolNames
        )

        let tools = await getToolSchemas()

        return ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            stream: true,
            toolChoice: .auto,
            tools: tools
        )
    }

    private func buildDeveloperMessageRequest(text: String) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForDeveloperMessage(
            text: text,
            systemPrompt: systemPrompt,
            allowedTools: allowedToolNames
        )

        let tools = await getToolSchemas()

        return ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            stream: true,
            toolChoice: .auto,
            tools: tools
        )
    }

    private func buildToolResponseRequest(output: JSON, callId: String) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForToolResponse(
            output: output,
            callId: callId,
            systemPrompt: systemPrompt
        )

        let tools = await getToolSchemas()

        return ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            stream: true,
            toolChoice: .auto,
            tools: tools
        )
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

    // MARK: - Stream Cancellation (Phase 3)

    /// Cancel the currently running stream
    private func cancelCurrentStream() async {
        guard let task = currentStreamTask else {
            Logger.debug("No active stream to cancel", category: .ai)
            return
        }

        task.cancel()
        currentStreamTask = nil

        // Emit idle status
        await emit(.llmStatus(status: .idle))

        Logger.info("🛑 LLM stream cancelled", category: .ai)
    }
}

