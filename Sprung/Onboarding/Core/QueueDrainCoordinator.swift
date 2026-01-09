//
//  QueueDrainCoordinator.swift
//  Sprung
//
//  Coordinates draining the UserActionQueue at safe boundaries.
//  Processes queued actions sequentially when the DrainGate allows.
//

import Foundation
import SwiftyJSON

/// Coordinates queue draining at safe boundaries
actor QueueDrainCoordinator {

    // MARK: - Dependencies

    private let queue: UserActionQueue
    private let gate: DrainGate
    private let eventBus: EventCoordinator

    // MARK: - State

    private var isDraining = false

    // MARK: - Initialization

    init(queue: UserActionQueue, gate: DrainGate, eventBus: EventCoordinator) {
        self.queue = queue
        self.gate = gate
        self.eventBus = eventBus

        // Wire up gate callback to trigger drain checks
        Task { @MainActor in
            gate.onGateOpened = { [weak self] in
                await self?.checkAndDrain()
            }
        }

        Logger.info("QueueDrainCoordinator initialized", category: .ai)
    }

    // MARK: - Drain Operations

    /// Check if we can drain and process queued actions
    func checkAndDrain() async {
        // Prevent concurrent draining
        guard !isDraining else {
            Logger.debug("🔄 QueueDrainCoordinator: Already draining, skipping", category: .ai)
            return
        }

        // Check gate on main actor
        let canDrain = await MainActor.run { gate.canDrain }
        guard canDrain else {
            let reason = await MainActor.run { gate.blockingDescription ?? "unknown" }
            Logger.debug("🚫 QueueDrainCoordinator: Gate blocked (\(reason)), skipping drain", category: .ai)
            return
        }

        isDraining = true
        defer { isDraining = false }

        Logger.info("🚰 QueueDrainCoordinator: Starting drain", category: .ai)

        var processedCount = 0

        while true {
            // Check gate before each action (processing might trigger new blocks)
            let stillCanDrain = await MainActor.run { gate.canDrain }
            guard stillCanDrain else {
                Logger.info("🚫 QueueDrainCoordinator: Gate closed mid-drain, pausing", category: .ai)
                break
            }

            // Dequeue next action on main actor
            let action = await MainActor.run { queue.dequeue() }
            guard let action = action else {
                break // Queue empty
            }

            await processAction(action)
            processedCount += 1
        }

        if processedCount > 0 {
            Logger.info("🚰 QueueDrainCoordinator: Drained \(processedCount) action(s)", category: .ai)
        }
    }

    /// Process a single queued action
    private func processAction(_ action: QueuedUserAction) async {
        Logger.info("▶️ QueueDrainCoordinator: Processing \(action.type.description)", category: .ai)

        switch action.type {
        case .chatboxMessage(let text, let id):
            // Emit queue count update for reactive UI
            let remainingCount = await MainActor.run { queue.pendingChatMessageIds().count }
            await eventBus.publish(.processing(.queuedMessageCountChanged(count: remainingCount)))
            await processChatMessage(text: text, id: id)

        case .phaseAdvance(let from, let to):
            await processPhaseAdvance(from: from, to: to)

        case .objectiveCompleted(let objectiveId):
            await processObjectiveCompleted(objectiveId: objectiveId)
        }
    }

    // MARK: - Action Processing

    private func processChatMessage(text: String, id: UUID) async {
        // Block gate while awaiting LLM response
        await MainActor.run { gate.blockForLLMResponse() }

        // Build payload for sendUserMessage event with <chatbox> wrapper
        var payload = JSON()
        payload["text"].string = "<chatbox>\(text)</chatbox>"

        // Emit processing state change for UI feedback
        await eventBus.publish(.processing(.stateChanged(isProcessing: true, statusMessage: "Processing your message...")))

        // Emit event to send message
        await eventBus.publish(.llm(.sendUserMessage(
            payload: payload,
            isSystemGenerated: false,
            chatboxMessageId: id.uuidString,
            originalText: text
        )))
    }

    private func processPhaseAdvance(from: InterviewPhase, to: InterviewPhase) async {
        // Block gate while awaiting LLM response to phase notification
        await MainActor.run { gate.blockForLLMResponse() }

        // Emit phase transition event with phase names
        await eventBus.publish(.phase(.transitionRequested(
            from: from.rawValue,
            to: to.rawValue,
            reason: "User action queue"
        )))

        // Send LLM notification about the phase change
        var payload = JSON()
        if to == .complete {
            payload["text"].string = "<system>User has completed the interview.</system>"
        } else {
            payload["text"].string = """
                <system>User has advanced to \(to.rawValue). \
                Continue the interview in the new phase.</system>
                """
        }
        await eventBus.publish(.llm(.sendUserMessage(payload: payload, isSystemGenerated: true)))
    }

    private func processObjectiveCompleted(objectiveId: String) async {
        // Emit objective status update
        await eventBus.publish(.objective(.statusUpdateRequested(
            id: objectiveId,
            status: "completed",
            source: "user_action_queue",
            notes: nil,
            details: nil
        )))
    }

    // MARK: - Session Management

    /// Reset coordinator state (e.g., on session end)
    func reset() async {
        isDraining = false
        await MainActor.run {
            queue.clear()
            gate.clearAllBlocks()
        }
        Logger.info("QueueDrainCoordinator: Reset", category: .ai)
    }
}
