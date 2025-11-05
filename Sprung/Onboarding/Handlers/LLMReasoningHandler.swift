//
//  LLMReasoningHandler.swift
//  Sprung
//
//  LLM Reasoning event handler (Spec §4.5)
//  Aggregates reasoning deltas and emits summaries
//

import Foundation
import SwiftyJSON

/// Handles LLM reasoning display
/// Responsibilities (Spec §4.5):
/// - Subscribe to LLM.reasoningDelta and LLM.reasoningDone
/// - Aggregate reasoning text
/// - Emit LLM.reasoningSummary (throttled)
/// - Emit LLM.reasoningStatus (incoming|none)
actor LLMReasoningHandler: OnboardingEventEmitter {
    // MARK: - Properties

    let eventBus: EventCoordinator

    // Reasoning accumulation
    private var currentReasoningBuffer: String = ""
    private var currentReasoningMessageId: UUID?
    private var lastSummaryEmitTime: Date?
    private let summaryThrottleInterval: TimeInterval = 0.5 // 500ms throttle

    // MARK: - Initialization

    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
        Logger.info("🧠 LLMReasoningHandler initialized", category: .ai)
    }

    // MARK: - Event Subscriptions

    /// Start listening to reasoning events
    /// NOTE: OpenAI Responses API doesn't currently expose reasoning in streaming mode
    /// This is prepared for future API support
    func startEventSubscriptions() {
        Task {
            for await event in await eventBus.stream(topic: .llm) {
                await handleLLMEvent(event)
            }
        }

        Logger.info("📡 LLMReasoningHandler subscribed to events (waiting for API support)", category: .ai)
    }

    // MARK: - Event Handlers

    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        // EXTERNAL BLOCKER: Waiting for OpenAI Responses API to expose reasoning
        // The handler methods are implemented below but not connected to events yet.
        // Uncomment these cases when OpenAI adds reasoning support to their Responses API.
        //
        // case .llmReasoningDelta(let messageId, let delta):
        //     await handleReasoningDelta(messageId: messageId, delta: delta)
        //
        // case .llmReasoningDone(let messageId):
        //     await handleReasoningDone(messageId: messageId)

        default:
            break
        }
    }

    // MARK: - Reasoning Processing

    /// Handle incoming reasoning delta
    /// Aggregates deltas and emits throttled summaries
    private func handleReasoningDelta(messageId: UUID, delta: String) async {
        // Initialize or validate message ID
        if currentReasoningMessageId != messageId {
            // New reasoning stream
            currentReasoningBuffer = ""
            currentReasoningMessageId = messageId
            await emit(.llmReasoningStatus("incoming"))
        }

        // Append delta to buffer
        currentReasoningBuffer += delta

        // Emit throttled summary
        let now = Date()
        if let lastEmit = lastSummaryEmitTime {
            guard now.timeIntervalSince(lastEmit) >= summaryThrottleInterval else {
                return // Throttled
            }
        }

        lastSummaryEmitTime = now
        await emitReasoningSummary(messageId: messageId, text: currentReasoningBuffer, isFinal: false)
    }

    /// Handle reasoning completion
    private func handleReasoningDone(messageId: UUID) async {
        guard currentReasoningMessageId == messageId else {
            Logger.warning("Reasoning done for unexpected message ID", category: .ai)
            return
        }

        // Emit final summary
        await emitReasoningSummary(messageId: messageId, text: currentReasoningBuffer, isFinal: true)

        // Reset state
        currentReasoningBuffer = ""
        currentReasoningMessageId = nil
        await emit(.llmReasoningStatus("none"))

        Logger.info("🧠 Reasoning complete for message \(messageId.uuidString)", category: .ai)
    }

    /// Emit reasoning summary event
    private func emitReasoningSummary(messageId: UUID, text: String, isFinal: Bool) async {
        var payload = JSON()
        payload["messageId"].string = messageId.uuidString
        payload["text"].string = text
        payload["isFinal"].bool = isFinal

        await emit(.llmReasoningSummary(messageId: messageId, summary: text, isFinal: isFinal))
    }
}
