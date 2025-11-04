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
    private let systemPrompt: String

    // Conversation tracking
    private var conversationId: String?
    private var lastResponseId: String?
    private var currentModelId: String = "gpt-5"
    private var isActive = false

    // Tool continuation tracking
    private var continuationCallIds: [UUID: String] = [:]

    // MARK: - Initialization

    init(
        service: OpenAIService,
        systemPrompt: String,
        eventBus: EventCoordinator,
        networkRouter: NetworkRouter
    ) {
        self.service = service
        self.systemPrompt = systemPrompt
        self.eventBus = eventBus
        self.networkRouter = networkRouter
        Logger.info("📬 LLMMessenger initialized", category: .ai)
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

        default:
            break
        }
    }

    private func handleUserInputEvent(_ event: OnboardingEvent) async {
        // TODO: Wire up UserInput.chatMessage when UI handlers are implemented
        Logger.debug("LLMMessenger received user input event", category: .ai)
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
            let request = buildUserMessageRequest(text: text)
            let messageId = UUID().uuidString

            // Emit message sent event
            await emit(.llmUserMessageSent(messageId: messageId, payload: payload))

            // Process stream via NetworkRouter
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

        } catch {
            await emit(.errorOccurred("Failed to send message: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
        }
    }

    /// Send developer message (system instructions)
    private func sendDeveloperMessage(_ payload: JSON) async {
        // TODO: Implement developer message sending
        Logger.debug("LLMMessenger developer message: \(payload)", category: .ai)
    }

    /// Send tool response back to LLM
    private func sendToolResponse(_ payload: JSON) async {
        await emit(.llmStatus(status: .busy))

        do {
            let callId = payload["callId"].stringValue
            let output = payload["output"]

            let request = buildToolResponseRequest(output: output, callId: callId)
            let messageId = UUID().uuidString

            // Emit message sent event
            await emit(.llmSentToolResponseMessage(messageId: messageId, payload: payload))

            // Process stream via NetworkRouter
            let stream = try await service.responseCreateStream(request)
            for try await streamEvent in stream {
                await networkRouter.handleResponseEvent(streamEvent)

                if case .responseCompleted(let completed) = streamEvent {
                    conversationId = completed.response.id
                    lastResponseId = completed.response.id
                }
            }

            await emit(.llmStatus(status: .idle))

        } catch {
            await emit(.errorOccurred("Failed to send tool response: \(error.localizedDescription)"))
            await emit(.llmStatus(status: .error))
        }
    }

    // MARK: - Request Building
    // TODO: Implement proper Responses API request building
    // For now, this is a placeholder - actual implementation will come
    // when we wire up the full message flow

    private func buildUserMessageRequest(text: String) -> ModelResponseParameter {
        let inputItems: [InputItem] = [
            .message(InputMessage(
                role: "developer",
                content: .text(systemPrompt)
            )),
            .message(InputMessage(
                role: "user",
                content: .text(text)
            ))
        ]

        return ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            stream: true,
            toolChoice: .auto,
            tools: [] // TODO: Get from StateCoordinator
        )
    }

    private func buildToolResponseRequest(output: JSON, callId: String) -> ModelResponseParameter {
        let outputString = output.rawString() ?? "{}"

        let inputItems: [InputItem] = [
            .functionToolCallOutput(FunctionToolCallOutput(
                callId: callId,
                output: outputString
            ))
        ]

        return ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            stream: true,
            toolChoice: .auto,
            tools: [] // TODO: Get from StateCoordinator
        )
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
        continuationCallIds.removeAll()
        Logger.info("⏹️ LLMMessenger deactivated", category: .ai)
    }

    func setModelId(_ modelId: String) {
        currentModelId = modelId
        Logger.info("🔧 LLMMessenger model set to: \(modelId)", category: .ai)
    }
}
