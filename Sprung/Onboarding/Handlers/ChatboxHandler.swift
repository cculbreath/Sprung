//
//  ChatboxHandler.swift
//  Sprung
//
//  Chatbox event handler (Spec §4.9)
//  Subscribes to LLM message events and updates chat transcript
//

import Foundation
import SwiftyJSON

/// Handles chat message display and user input
/// Responsibilities (Spec §4.9):
/// - Subscribe to LLM message events
/// - Update ChatTranscriptStore with streaming messages
/// - Emit UserInput.chatMessage when user sends messages
/// - Display error messages and status updates
actor ChatboxHandler: OnboardingEventEmitter {
    // MARK: - Properties

    let eventBus: EventCoordinator
    private let transcriptStore: ChatTranscriptStore

    // Track message IDs for updates
    private var streamingMessageIds: [UUID: UUID] = [:]

    // MARK: - Initialization

    init(
        eventBus: EventCoordinator,
        transcriptStore: ChatTranscriptStore
    ) {
        self.eventBus = eventBus
        self.transcriptStore = transcriptStore
        Logger.info("💬 ChatboxHandler initialized", category: .ai)
    }

    // MARK: - Event Subscriptions

    /// Start listening to chat-related events
    func startEventSubscriptions() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                // Subscribe to LLM message events
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .llm) {
                        await self.handleLLMEvent(event)
                    }
                }

                // Subscribe to processing state changes
                group.addTask {
                    for await event in await self.eventBus.stream(topic: .processing) {
                        await self.handleProcessingEvent(event)
                    }
                }
            }
        }

        Logger.info("📡 ChatboxHandler subscribed to events", category: .ai)
    }

    // MARK: - Event Handlers

    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .streamingMessageBegan(let id, let text, let reasoningExpected):
            await handleStreamingMessageBegan(id: id, text: text, reasoningExpected: reasoningExpected)

        case .streamingMessageUpdated(let id, let delta):
            await handleStreamingMessageUpdated(id: id, delta: delta)

        case .streamingMessageFinalized(let id, let finalText):
            await handleStreamingMessageFinalized(id: id, finalText: finalText)

        case .llmUserMessageSent(_, let payload):
            await handleUserMessageSent(payload: payload)

        case .errorOccurred(let message):
            await handleError(message: message)

        default:
            break
        }
    }

    private func handleProcessingEvent(_ event: OnboardingEvent) async {
        // TODO: Handle processing state changes for UI feedback
    }

    // MARK: - Message Streaming

    private func handleStreamingMessageBegan(id: UUID, text: String, reasoningExpected: Bool) async {
        await MainActor.run {
            let messageId = transcriptStore.beginAssistantStream(initialText: text, reasoningExpected: reasoningExpected)
            Task {
                await self.trackMessageId(streamId: id, messageId: messageId)
            }
        }
    }

    private func handleStreamingMessageUpdated(id: UUID, delta: String) async {
        guard let messageId = streamingMessageIds[id] else {
            Logger.warning("No message ID found for stream \(id)", category: .ai)
            return
        }

        // Get current text and append delta
        await MainActor.run {
            // Get current message text
            if let message = transcriptStore.messages.first(where: { $0.id == messageId }) {
                let updatedText = message.text + delta
                transcriptStore.updateAssistantStream(id: messageId, text: updatedText)
            }
        }
    }

    private func handleStreamingMessageFinalized(id: UUID, finalText: String) async {
        guard let messageId = streamingMessageIds.removeValue(forKey: id) else {
            Logger.warning("No message ID found for stream \(id)", category: .ai)
            return
        }

        await MainActor.run {
            let elapsed = transcriptStore.finalizeAssistantStream(id: messageId, text: finalText)
            Logger.info("✅ Message finalized in \(String(format: "%.2f", elapsed))s", category: .ai)
        }
    }

    private func handleUserMessageSent(payload: JSON) async {
        let text = payload["text"].stringValue
        await MainActor.run {
            transcriptStore.appendUserMessage(text)
        }
    }

    private func handleError(message: String) async {
        await MainActor.run {
            transcriptStore.appendSystemMessage("Error: \(message)")
        }
    }

    // MARK: - User Input

    /// Send user message to LLM
    func sendUserMessage(_ text: String) async {
        var payload = JSON()
        payload["text"].string = text

        // Emit event for LLMMessenger to handle
        await emit(.llmSendUserMessage(payload: payload))
    }

    // MARK: - Helpers

    private func trackMessageId(streamId: UUID, messageId: UUID) {
        streamingMessageIds[streamId] = messageId
    }
}
