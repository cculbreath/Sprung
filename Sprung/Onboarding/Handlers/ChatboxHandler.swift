//
//  ChatboxHandler.swift
//  Sprung
//
//  Chatbox event handler (Spec §4.9)
//  Handles user input and emits events
//
import Foundation
import SwiftyJSON
/// Handles chat message input
/// Responsibilities (Spec §4.9):
/// - Emit UserInput.chatMessage when user sends messages
/// - Display error messages and status updates
///
/// NOTE: StateCoordinator.messages is the authoritative source with sync caches for UI access.
/// Message state is managed entirely by StateCoordinator.
actor ChatboxHandler: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    private let state: StateCoordinator
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        state: StateCoordinator
    ) {
        self.eventBus = eventBus
        self.state = state
        Logger.info("💬 ChatboxHandler initialized", category: .ai)
    }
    // MARK: - Event Subscriptions
    /// Start listening to chat-related events
    func startEventSubscriptions() async {
        Task {
            for await event in await self.eventBus.stream(topic: .llm) {
                await self.handleLLMEvent(event)
            }
        }
        // Small delay to ensure stream is connected
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        Logger.info("📡 ChatboxHandler subscribed to events", category: .ai)
    }
    // MARK: - Event Handlers
    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .errorOccurred(let message):
            // Log errors
            Logger.error("LLM error: \(message)", category: .ai)
        default:
            break
        }
    }
    // MARK: - User Input
    /// Send user message to LLM
    func sendUserMessage(_ text: String) async {
        // Check if there's a pending UI tool call (validation, upload, etc.)
        // If so, cancel it with an error response before sending the user's message
        // This prevents the conversation from getting stuck waiting for tool output
        if let pendingTool = await state.getPendingUIToolCall() {
            Logger.info("💬 User message while UI tool pending - cancelling \(pendingTool.toolName)", category: .ai)

            // Build cancelled tool response
            var cancelPayload = JSON()
            cancelPayload["callId"].string = pendingTool.callId
            var output = JSON()
            output["status"].string = "cancelled"
            output["reason"].string = "User sent a chat message, overriding the pending UI interaction"
            output["user_message"].string = text
            cancelPayload["output"] = output

            // Clear the pending UI tool state
            await state.clearPendingUIToolCall()

            // Send the cancelled tool response
            await emit(.llmToolResponseMessage(payload: cancelPayload))

            Logger.info("💬 Sent cancelled tool response for \(pendingTool.toolName), proceeding with user message", category: .ai)
        }

        // Add the ORIGINAL message (without tags) to chat transcript IMMEDIATELY so user sees it right away
        let messageId = await state.appendUserMessage(text, isSystemGenerated: false)
        // Emit a custom event so coordinator can sync its messages array
        await emit(.chatboxUserMessageAdded(messageId: messageId.uuidString))
        // Wrap user chatbox messages in <chatbox> tags for LLM context
        var payload = JSON()
        payload["text"].string = "<chatbox>\(text)</chatbox>"
        // Emit processing state change for UI feedback
        await emit(.processingStateChanged(true, statusMessage: "Processing your message..."))
        // Emit event for LLMMessenger to handle (isSystemGenerated defaults to false)
        await emit(.llmSendUserMessage(payload: payload))
    }
}
