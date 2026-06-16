//
//  DailyTaskStore.swift
//  Sprung
//
//  Store for managing daily tasks.
//

import SwiftData
import Foundation

@Observable
@MainActor
final class DailyTaskStore: EntityStore {
    typealias Entity = DailyTask

    unowned let modelContext: ModelContext

    /// `@Observable`-tracked refresh counter; the EntityStore extension bumps it on mutation.
    var changeVersion: Int = 0

    init(context: ModelContext) {
        modelContext = context
    }

    var allTasks: [DailyTask] {
        fetchAll(sortBy: [SortDescriptor(\.priority, order: .reverse)])
    }

    var todaysTasks: [DailyTask] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return allTasks.filter { calendar.isDate($0.createdAt, inSameDayAs: today) }
    }

    /// Get tasks for a specific type
    func tasks(ofType type: DailyTaskType) -> [DailyTask] {
        todaysTasks.filter { $0.taskType == type }
    }

    /// Today's tasks belonging to a section category, grouped in the category's
    /// declared type order (each type's tasks stay priority-sorted). Owns the
    /// "which task types compose this section" mapping so views don't re-spell it.
    func tasks(in category: TaskCategory) -> [DailyTask] {
        category.dailyTaskTypes.flatMap { tasks(ofType: $0) }
    }

    func complete(_ task: DailyTask) {
        task.isCompleted = true
        task.completedAt = Date()
        update(task)
    }

    /// Clear old tasks (older than specified days)
    func clearOldTasks(olderThan days: Int = 7) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let oldTasks = allTasks.filter { $0.createdAt < cutoff }
        deleteAll(oldTasks)
    }

    /// Get completed tasks this week
    func completedThisWeek() -> [DailyTask] {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        return allTasks.filter { task in
            task.isCompleted && task.createdAt >= weekStart
        }
    }
}
