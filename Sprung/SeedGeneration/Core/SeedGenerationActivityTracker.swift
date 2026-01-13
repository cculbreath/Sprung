//
//  SeedGenerationActivityTracker.swift
//  Sprung
//
//  Tracks progress and status of seed generation tasks.
//  Simpler than AgentActivityTracker - no transcript, just status.
//

import Foundation
import Observation

/// Status of a tracked generation task
enum GenerationTaskStatus: String {
    case pending
    case running
    case completed
    case failed
}

/// A tracked generation task with status information
struct TrackedGenerationTask: Identifiable {
    let id: String
    let displayName: String
    var status: GenerationTaskStatus
    var statusMessage: String?
    let startTime: Date
    var endTime: Date?
    var error: String?

    /// Duration in seconds (nil if still running)
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    /// Formatted duration string
    var durationString: String {
        guard let duration = duration else { return "Running..." }
        return String(format: "%.1fs", duration)
    }

    init(
        id: String = UUID().uuidString,
        displayName: String,
        status: GenerationTaskStatus = .pending,
        statusMessage: String? = nil,
        startTime: Date = Date(),
        endTime: Date? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.statusMessage = statusMessage
        self.startTime = startTime
        self.endTime = endTime
        self.error = error
    }
}

/// Tracks activity for seed generation tasks
@Observable
@MainActor
final class SeedGenerationActivityTracker {
    // MARK: - State

    /// All tracked tasks
    private(set) var activeTasks: [TrackedGenerationTask] = []

    /// Callback when all tasks complete
    var onAllTasksCompleted: (() -> Void)?

    // MARK: - Computed Properties

    /// Count of running tasks
    var runningCount: Int {
        activeTasks.filter { $0.status == .running }.count
    }

    /// Count of completed tasks
    var completedCount: Int {
        activeTasks.filter { $0.status == .completed }.count
    }

    /// Count of failed tasks
    var failedCount: Int {
        activeTasks.filter { $0.status == .failed }.count
    }

    /// Total number of tasks
    var totalCount: Int {
        activeTasks.count
    }

    /// Whether any task is currently running
    var isAnyRunning: Bool {
        runningCount > 0
    }

    /// Running tasks only
    var runningTasks: [TrackedGenerationTask] {
        activeTasks.filter { $0.status == .running }
    }

    /// Pending tasks only
    var pendingTasks: [TrackedGenerationTask] {
        activeTasks.filter { $0.status == .pending }
    }

    /// Completed tasks only
    var completedTasks: [TrackedGenerationTask] {
        activeTasks.filter { $0.status == .completed }
    }

    /// Failed tasks only
    var failedTasks: [TrackedGenerationTask] {
        activeTasks.filter { $0.status == .failed }
    }

    // MARK: - Task Lifecycle

    /// Track a new task
    @discardableResult
    func trackTask(id: String = UUID().uuidString, displayName: String) -> String {
        let task = TrackedGenerationTask(
            id: id,
            displayName: displayName,
            status: .pending,
            startTime: Date()
        )
        activeTasks.append(task)
        Logger.info("📋 Task tracked: \(displayName) (id: \(id.prefix(8)))", category: .ai)
        return id
    }

    /// Mark a task as running
    func markRunning(id: String, message: String? = nil) {
        guard let index = activeTasks.firstIndex(where: { $0.id == id }) else {
            Logger.warning("⚠️ Cannot mark running: task not found (id: \(id.prefix(8)))", category: .ai)
            return
        }

        activeTasks[index].status = .running
        activeTasks[index].statusMessage = message
        Logger.info("🚀 Task running: \(activeTasks[index].displayName)", category: .ai)
    }

    /// Mark a task as completed
    func markCompleted(id: String) {
        guard let index = activeTasks.firstIndex(where: { $0.id == id }) else {
            Logger.warning("⚠️ Cannot mark completed: task not found (id: \(id.prefix(8)))", category: .ai)
            return
        }

        activeTasks[index].status = .completed
        activeTasks[index].endTime = Date()
        activeTasks[index].statusMessage = nil

        Logger.info(
            "✅ Task completed: \(activeTasks[index].displayName) (\(activeTasks[index].durationString))",
            category: .ai
        )

        checkAllTasksCompleted()
    }

    /// Mark a task as failed
    func markFailed(id: String, error: String) {
        guard let index = activeTasks.firstIndex(where: { $0.id == id }) else {
            Logger.warning("⚠️ Cannot mark failed: task not found (id: \(id.prefix(8)))", category: .ai)
            return
        }

        activeTasks[index].status = .failed
        activeTasks[index].endTime = Date()
        activeTasks[index].error = error
        activeTasks[index].statusMessage = nil

        Logger.error("❌ Task failed: \(activeTasks[index].displayName) - \(error)", category: .ai)

        checkAllTasksCompleted()
    }

    /// Update the status message for a running task
    func updateStatus(id: String, message: String) {
        guard let index = activeTasks.firstIndex(where: { $0.id == id }) else {
            return // Silent fail - status updates are non-critical
        }

        activeTasks[index].statusMessage = message
    }

    /// Get a task by ID
    func task(for id: String) -> TrackedGenerationTask? {
        activeTasks.first { $0.id == id }
    }

    /// Clear all tasks
    func clear() {
        activeTasks.removeAll()
    }

    /// Reset all tasks to pending
    func reset() {
        for index in activeTasks.indices {
            activeTasks[index].status = .pending
            activeTasks[index].statusMessage = nil
            activeTasks[index].error = nil
            activeTasks[index].endTime = nil
        }
    }

    // MARK: - Private Helpers

    private func checkAllTasksCompleted() {
        // Check if all tasks are done (completed or failed)
        let allDone = activeTasks.allSatisfy { task in
            task.status == .completed || task.status == .failed
        }

        if allDone && !activeTasks.isEmpty {
            Logger.info(
                "🏁 All tasks completed (\(completedCount) succeeded, \(failedCount) failed)",
                category: .ai
            )
            onAllTasksCompleted?()
        }
    }
}
