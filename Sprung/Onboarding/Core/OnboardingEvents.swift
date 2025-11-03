//
//  OnboardingEvents.swift
//  Sprung
//
//  Event-driven architecture for the onboarding system.
//  Replaces the 13+ callback struct with clean, unidirectional events.
//

import Foundation
import SwiftyJSON

/// All events that can occur during the onboarding interview
enum OnboardingEvent {
    // MARK: - Processing State
    case processingStateChanged(Bool)

    // MARK: - Messages
    case assistantMessageEmitted(id: UUID, text: String, reasoningExpected: Bool)
    case streamingMessageBegan(id: UUID, text: String, reasoningExpected: Bool)
    case streamingMessageUpdated(id: UUID, delta: String)
    case streamingMessageFinalized(id: UUID, finalText: String)

    // MARK: - Reasoning
    case reasoningSummaryUpdated(messageId: UUID, summary: String, isFinal: Bool)
    case reasoningSummariesFinalized([UUID])

    // MARK: - Status Updates
    case streamingStatusUpdated(String?)
    case waitingStateChanged(String?)
    case errorOccurred(String)

    // MARK: - Data Storage
    case applicantProfileStored(JSON)
    case skeletonTimelineStored(JSON)
    case enabledSectionsUpdated(Set<String>)
    case checkpointRequested

    // MARK: - Tool Execution
    case toolCallRequested(ToolCall)
    case toolCallCompleted(id: UUID, result: JSON)
    case toolContinuationNeeded(id: UUID, toolName: String)

    // MARK: - Objective Management
    case objectiveStatusRequested(id: String, response: (String?) -> Void)
}

/// Event bus that manages event distribution in the onboarding system
actor OnboardingEventBus {
    typealias EventHandler = (OnboardingEvent) async -> Void

    private var handlers: [UUID: EventHandler] = [:]
    private var eventHistory: [OnboardingEvent] = []
    private let maxHistorySize = 100

    /// Subscribe to events with a handler
    func subscribe(_ handler: @escaping EventHandler) -> UUID {
        let id = UUID()
        handlers[id] = handler
        Logger.debug("[EventBus] Handler \(id) subscribed", category: .ai)
        return id
    }

    /// Unsubscribe a handler
    func unsubscribe(_ id: UUID) {
        handlers.removeValue(forKey: id)
        Logger.debug("[EventBus] Handler \(id) unsubscribed", category: .ai)
    }

    /// Publish an event to all subscribers
    func publish(_ event: OnboardingEvent) async {
        // Log the event
        logEvent(event)

        // Add to history
        eventHistory.append(event)
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst(eventHistory.count - maxHistorySize)
        }

        // Distribute to all handlers
        await withTaskGroup(of: Void.self) { group in
            for handler in handlers.values {
                group.addTask {
                    await handler(event)
                }
            }
        }
    }

    /// Get recent event history
    func getRecentEvents(count: Int = 10) -> [OnboardingEvent] {
        Array(eventHistory.suffix(count))
    }

    /// Clear event history
    func clearHistory() {
        eventHistory.removeAll()
    }

    // MARK: - Private

    private func logEvent(_ event: OnboardingEvent) {
        let description: String
        switch event {
        case .processingStateChanged(let processing):
            description = "Processing: \(processing)"
        case .assistantMessageEmitted:
            description = "Assistant message"
        case .streamingMessageBegan:
            description = "Streaming began"
        case .streamingMessageUpdated:
            description = "Streaming update"
        case .streamingMessageFinalized:
            description = "Streaming finalized"
        case .reasoningSummaryUpdated:
            description = "Reasoning updated"
        case .reasoningSummariesFinalized:
            description = "Reasoning finalized"
        case .streamingStatusUpdated(let status):
            description = "Status: \(status ?? "nil")"
        case .waitingStateChanged(let state):
            description = "Waiting: \(state ?? "nil")"
        case .errorOccurred(let error):
            description = "Error: \(error)"
        case .applicantProfileStored:
            description = "Profile stored"
        case .skeletonTimelineStored:
            description = "Timeline stored"
        case .enabledSectionsUpdated:
            description = "Sections updated"
        case .checkpointRequested:
            description = "Checkpoint requested"
        case .toolCallRequested:
            description = "Tool call requested"
        case .toolCallCompleted:
            description = "Tool call completed"
        case .toolContinuationNeeded:
            description = "Tool continuation needed"
        case .objectiveStatusRequested:
            description = "Objective status requested"
        }

        Logger.debug("[Event] \(description)", category: .ai)
    }
}

/// Protocol for components that can emit events
protocol OnboardingEventEmitter {
    var eventBus: OnboardingEventBus { get }
}

/// Extension to make event emission convenient
extension OnboardingEventEmitter {
    func emit(_ event: OnboardingEvent) async {
        await eventBus.publish(event)
    }
}

/// Protocol for components that handle events
protocol OnboardingEventHandler {
    func handleEvent(_ event: OnboardingEvent) async
}

// Tool call structure now uses the one from ToolProtocol.swift
// Legacy compatibility
struct FunctionCall: Codable {
    let name: String
    let arguments: String
}