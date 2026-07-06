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

    /// The most recent day before today that has tasks, with its tasks.
    /// The delta base for coaching openers and task carry-over.
    func previousTaskDay() -> (date: Date, tasks: [DailyTask])? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let priorTasks = allTasks.filter { $0.createdAt < today }
        guard let latest = priorTasks.map({ calendar.startOfDay(for: $0.createdAt) }).max() else {
            return nil
        }
        let dayTasks = priorTasks.filter { calendar.isDate($0.createdAt, inSameDayAs: latest) }
        return (date: latest, tasks: dayTasks)
    }

    /// Consecutive days (ending today or yesterday) with at least one completed
    /// task. 0 when neither today nor yesterday has a completion.
    func completionStreakDays() -> Int {
        let calendar = Calendar.current
        let completedDays = Set(
            allTasks.compactMap { task -> Date? in
                guard task.isCompleted, let completedAt = task.completedAt else { return nil }
                return calendar.startOfDay(for: completedAt)
            }
        )
        guard !completedDays.isEmpty else { return 0 }

        var day = calendar.startOfDay(for: Date())
        if !completedDays.contains(day) {
            // A streak that ended yesterday still counts until today is over.
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  completedDays.contains(yesterday) else {
                return 0
            }
            day = yesterday
        }

        var streak = 0
        while completedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
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
