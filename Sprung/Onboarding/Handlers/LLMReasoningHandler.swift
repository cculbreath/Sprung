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
    ///
    /// NOTE: Reasoning summaries ARE supported in the OpenAI Responses API and are wired up.
    /// NetworkRouter handles reasoningSummaryTextDelta events and emits llmReasoningSummary events.
    /// StateCoordinator stores these summaries in message objects.
    ///
    /// This handler is currently unused - NetworkRouter emits summaries directly.
    /// The handler could be used for additional processing (analytics, logging, etc.) in the future.
    func startEventSubscriptions() {
        Task {
            for await event in await eventBus.stream(topic: .llm) {
                await handleLLMEvent(event)
            }
        }

        Logger.info("📡 LLMReasoningHandler subscribed to events", category: .ai)
    }

    // MARK: - Event Handlers

    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        // Reasoning summaries are currently handled directly by NetworkRouter → StateCoordinator
        // This handler could be activated for additional processing if needed
        //
        // case .llmReasoningSummary(let messageId, let summary, let isFinal):
        //     // Additional processing could go here
        //     Logger.debug("Reasoning summary: \(summary.prefix(50))...", category: .ai)

        default:
            break
        }
    }

    // MARK: - Reasoning Processing

    // MARK: - Legacy Methods (Unused)
    // These methods are not currently used - NetworkRouter emits reasoning summaries directly
    // to StateCoordinator. Keeping for reference but not connected to events.
}
