//
//  UserActionQueue.swift
//  Sprung
//
//  Queue for user actions that need to be processed at safe boundaries.
//  Actions are held until the DrainGate allows processing.
//

import Foundation

/// Types of user actions that can be queued
///
/// Note: Upload/option dismissals are NOT queued here because they are
/// responses to active UI tools, not independent user actions. The tool
/// is already executing and waiting for user input, and the DrainGate
/// blocks until the UI tool is dismissed anyway.
enum UserActionType: Sendable {
    /// User typed a message in the chatbox
    case chatboxMessage(text: String, id: UUID)

    /// User clicked "done with..." or phase advance button
    case phaseAdvance(from: InterviewPhase, to: InterviewPhase)

    /// User completed an objective via button click
    case objectiveCompleted(objectiveId: String)
}

/// Priority levels for queued actions
enum UserActionPriority: Int, Comparable, Sendable {
    case background = 0  // Coordinator messages
    case normal = 1      // Chatbox messages
    case high = 2        // Phase advances, done buttons

    static func < (lhs: UserActionPriority, rhs: UserActionPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A queued user action with metadata
struct QueuedUserAction: Identifiable, Sendable {
    let id: UUID
    let type: UserActionType
    let timestamp: Date
    let priority: UserActionPriority

    init(type: UserActionType, priority: UserActionPriority = .normal) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.priority = priority
    }
}

/// Queue for user actions awaiting processing at safe boundaries
@Observable
@MainActor
final class UserActionQueue {

    // MARK: - State

    private(set) var queue: [QueuedUserAction] = []

    // MARK: - Queue Operations

    /// Enqueue a user action for later processing
    /// Returns the action ID for tracking
    @discardableResult
    func enqueue(_ actionType: UserActionType, priority: UserActionPriority = .normal) -> UUID {
        let action = QueuedUserAction(type: actionType, priority: priority)
        queue.append(action)

        // Sort by priority (higher priority first), then by timestamp (FIFO within priority)
        queue.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.timestamp < rhs.timestamp
        }

        Logger.info("📥 UserActionQueue: Enqueued \(actionType.description) (priority: \(priority), total: \(queue.count))", category: .ai)
        return action.id
    }

    /// Dequeue the next action for processing
    func dequeue() -> QueuedUserAction? {
        guard !queue.isEmpty else { return nil }
        let action = queue.removeFirst()
        Logger.debug("📤 UserActionQueue: Dequeued \(action.type.description) (remaining: \(queue.count))", category: .ai)
        return action
    }

    /// Clear all queued actions
    func clear() {
        let count = queue.count
        queue.removeAll()
        if count > 0 {
            Logger.info("🧹 UserActionQueue: Cleared \(count) action(s)", category: .ai)
        }
    }

    /// Get all pending chatbox message IDs (for UI display)
    func pendingChatMessageIds() -> [UUID] {
        queue.compactMap { action in
            if case .chatboxMessage(_, let id) = action.type {
                return id
            }
            return nil
        }
    }
}

// MARK: - UserActionType Description

extension UserActionType {
    var description: String {
        switch self {
        case .chatboxMessage(let text, _):
            let preview = text.prefix(30)
            return "chatboxMessage(\"\(preview)\(text.count > 30 ? "..." : "")\")"
        case .phaseAdvance(let from, let to):
            return "phaseAdvance(\(from) → \(to))"
        case .objectiveCompleted(let objectiveId):
            return "objectiveCompleted(\(objectiveId))"
        }
    }
}
