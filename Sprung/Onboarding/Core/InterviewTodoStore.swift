//
//  InterviewTodoStore.swift
//  Sprung
//
//  Manages the LLM-visible todo list for tracking interview progress.
//  The LLM can add, remove, and check off items via the update_todo_list tool.
//  Current state is rendered as <todo-list> tags inside the <interview_context>
//  block of the latest user message (NOT the system prompt — the system prompt
//  must stay byte-identical within a phase for prompt caching).
//

import Foundation

// MARK: - Todo Item Model

/// Status of a todo item
enum InterviewTodoStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
}

/// A single todo item in the interview checklist
struct InterviewTodoItem: Codable, Identifiable {
    let id: UUID
    var content: String
    var status: InterviewTodoStatus
    /// Present tense form shown when item is in progress (e.g., "Collecting writing samples")
    var activeForm: String?
    /// If true, this item was pre-populated by the phase script and cannot be removed by the LLM.
    /// The LLM can only change its status, not delete it or modify its content.
    var scriptLocked: Bool

    init(id: UUID = UUID(), content: String, status: InterviewTodoStatus = .pending, activeForm: String? = nil, scriptLocked: Bool = false) {
        self.id = id
        self.content = content
        self.status = status
        self.activeForm = activeForm
        self.scriptLocked = scriptLocked
    }
}

// MARK: - Todo Store

/// Actor that manages the interview todo list state.
/// Provides methods for the LLM to manipulate the list via tool calls.
actor InterviewTodoStore {

    // MARK: - Dependencies

    private weak var eventBus: EventCoordinator?

    // MARK: - State

    private(set) var items: [InterviewTodoItem] = []

    // MARK: - Initialization

    init(eventBus: EventCoordinator? = nil) {
        self.eventBus = eventBus
    }

    /// Set the event bus after initialization (for dependency injection)
    func setEventBus(_ eventBus: EventCoordinator) {
        self.eventBus = eventBus
    }

    // MARK: - Public API (for tool)

    /// Update the todo list from LLM input.
    /// LLM can reorder and update statuses freely.
    /// Any locked items that LLM omits are re-added at the end.
    /// This is the primary method called by the update_todo_list tool.
    func setItems(_ newItems: [InterviewTodoItem]) {
        let lockedItems = items.filter { $0.scriptLocked }

        // Start with what LLM sent (LLM-provided items are never locked)
        var result = newItems.map { item in
            var copy = item
            copy.scriptLocked = false
            return copy
        }

        // Re-add any locked items that LLM omitted
        for lockedItem in lockedItems {
            let wasIncluded = newItems.contains {
                $0.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ==
                lockedItem.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !wasIncluded {
                Logger.info("📋 Re-adding omitted locked todo: \(lockedItem.content)", category: .ai)
                result.append(lockedItem)
            }
        }

        items = result
        Logger.info("📋 Todo list updated: \(items.count) item(s)", category: .ai)
        logCurrentState()
        emitUpdateEvent()
    }

    /// Set items from phase script with scriptLocked = true.
    /// Used during phase transitions to establish required items.
    func setItemsFromScript(_ scriptItems: [InterviewTodoItem]) {
        items = scriptItems.map { item in
            var locked = item
            locked.scriptLocked = true
            return locked
        }
        Logger.info("📋 Todo list set from script: \(items.count) item(s) (all locked)", category: .ai)
        logCurrentState()
        emitUpdateEvent()
    }

    /// Add a single item to the list
    func addItem(content: String, activeForm: String? = nil) {
        let item = InterviewTodoItem(content: content, activeForm: activeForm)
        items.append(item)
        Logger.info("📋 Todo added: \(content)", category: .ai)
    }

    /// Mark an item as in_progress by index (0-based)
    func markInProgress(index: Int) {
        guard index >= 0 && index < items.count else {
            Logger.warning("📋 Invalid todo index for markInProgress: \(index)", category: .ai)
            return
        }
        items[index].status = .inProgress
        Logger.info("📋 Todo in progress: \(items[index].content)", category: .ai)
    }

    /// Mark an item as completed by index (0-based)
    func markCompleted(index: Int) {
        guard index >= 0 && index < items.count else {
            Logger.warning("📋 Invalid todo index for markCompleted: \(index)", category: .ai)
            return
        }
        items[index].status = .completed
        Logger.info("📋 Todo completed: \(items[index].content)", category: .ai)
    }

    /// Remove an item by index (0-based)
    func removeItem(index: Int) {
        guard index >= 0 && index < items.count else {
            Logger.warning("📋 Invalid todo index for remove: \(index)", category: .ai)
            return
        }
        let removed = items.remove(at: index)
        Logger.info("📋 Todo removed: \(removed.content)", category: .ai)
    }

    /// Clear all items
    func clear() {
        items.removeAll()
        Logger.info("📋 Todo list cleared", category: .ai)
    }

    // MARK: - Rendering for Interview Context

    /// Render the current todo list as XML for injection into the
    /// <interview_context> block of the latest user message.
    /// Returns nil if the list is empty (no need to inject).
    /// Items marked with 📌 are required and cannot be removed (only status can change).
    func renderTodoList() -> String? {
        guard !items.isEmpty else { return nil }

        var lines: [String] = ["<todo-list>"]
        lines.append("<!-- 📌 = required item (cannot be removed, only status changes allowed) -->")

        for (index, item) in items.enumerated() {
            let statusIcon: String
            let statusText: String

            switch item.status {
            case .pending:
                statusIcon = "[ ]"
                statusText = item.content
            case .inProgress:
                statusIcon = "[~]"
                statusText = item.activeForm ?? item.content
            case .completed:
                statusIcon = "[x]"
                statusText = item.content
            }

            // Add 📌 prefix for required (scriptLocked) items - before the number to avoid LLM including it in content
            let requiredPrefix = item.scriptLocked ? "📌 " : "   "
            lines.append("\(requiredPrefix)\(index + 1). \(statusIcon) \(statusText)")
        }

        lines.append("</todo-list>")
        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence Support

    /// Get items for persistence
    func getItemsForPersistence() -> [InterviewTodoItem] {
        return items
    }

    /// Restore items from persistence
    func restoreItems(_ savedItems: [InterviewTodoItem]) {
        items = savedItems
        Logger.info("📋 Todo list restored: \(items.count) item(s)", category: .ai)
        logCurrentState()
    }

    // MARK: - Debug

    private func logCurrentState() {
        guard !items.isEmpty else { return }
        for (index, item) in items.enumerated() {
            let icon = item.status == .completed ? "✓" : (item.status == .inProgress ? "→" : "○")
            Logger.debug("   \(icon) \(index + 1). \(item.content) [\(item.status.rawValue)]", category: .ai)
        }
    }

    /// Emit event for persistence
    private func emitUpdateEvent() {
        guard let eventBus else { return }
        // Serialize items to JSON
        if let data = try? JSONEncoder().encode(items),
           let jsonString = String(data: data, encoding: .utf8) {
            Task {
                await eventBus.publish(.tool(.todoListUpdated(todoListJSON: jsonString)))
            }
        }
    }
}
