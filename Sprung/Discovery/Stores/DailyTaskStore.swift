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
final class DailyTaskStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    /// Incremented on mutations to trigger SwiftUI observation
    private(set) var changeCounter: Int = 0

    init(context: ModelContext) {
        modelContext = context
    }

    private func notifyChanged() {
        changeCounter += 1
    }

    var allTasks: [DailyTask] {
        _ = changeCounter  // Establish observation dependency
        (try? modelContext.fetch(
            FetchDescriptor<DailyTask>(sortBy: [SortDescriptor(\.priority, order: .reverse)])
        )) ?? []
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

    func add(_ task: DailyTask) {
        modelContext.insert(task)
        saveContext()
        notifyChanged()
    }

    func addMultiple(_ tasks: [DailyTask]) {
        for task in tasks {
            modelContext.insert(task)
        }
        saveContext()
        notifyChanged()
    }

    func complete(_ task: DailyTask) {
        task.isCompleted = true
        task.completedAt = Date()
        saveContext()
        notifyChanged()
    }

    func delete(_ task: DailyTask) {
        modelContext.delete(task)
        saveContext()
        notifyChanged()
    }

    /// Clear old tasks (older than specified days)
    func clearOldTasks(olderThan days: Int = 7) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let oldTasks = allTasks.filter { $0.createdAt < cutoff }
        for task in oldTasks {
            modelContext.delete(task)
        }
        saveContext()
        notifyChanged()
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
