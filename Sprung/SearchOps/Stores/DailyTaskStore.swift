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

    init(context: ModelContext) {
        modelContext = context
    }

    var allTasks: [DailyTask] {
        (try? modelContext.fetch(
            FetchDescriptor<DailyTask>(sortBy: [SortDescriptor(\.priority, order: .reverse)])
        )) ?? []
    }

    var todaysTasks: [DailyTask] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return allTasks.filter { calendar.isDate($0.createdAt, inSameDayAs: today) }
    }

    var incompleteTasks: [DailyTask] {
        todaysTasks.filter { !$0.isCompleted }
    }

    var completedTasks: [DailyTask] {
        todaysTasks.filter { $0.isCompleted }
    }

    /// Group today's tasks by type
    var tasksByType: [DailyTaskType: [DailyTask]] {
        Dictionary(grouping: todaysTasks) { $0.taskType }
    }

    /// Get tasks for a specific type
    func tasks(ofType type: DailyTaskType) -> [DailyTask] {
        todaysTasks.filter { $0.taskType == type }
    }

    func add(_ task: DailyTask) {
        modelContext.insert(task)
        saveContext()
    }

    func addMultiple(_ tasks: [DailyTask]) {
        for task in tasks {
            modelContext.insert(task)
        }
        saveContext()
    }

    func complete(_ task: DailyTask) {
        task.isCompleted = true
        task.completedAt = Date()
        saveContext()
    }

    func uncomplete(_ task: DailyTask) {
        task.isCompleted = false
        task.completedAt = nil
        saveContext()
    }

    func delete(_ task: DailyTask) {
        modelContext.delete(task)
        saveContext()
    }

    func task(byId id: UUID) -> DailyTask? {
        allTasks.first { $0.id == id }
    }

    /// Clear old tasks (older than specified days)
    func clearOldTasks(olderThan days: Int = 7) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let oldTasks = allTasks.filter { $0.createdAt < cutoff }
        for task in oldTasks {
            modelContext.delete(task)
        }
        saveContext()
    }

    /// Clear all tasks for today (useful before regenerating)
    func clearTodaysTasks() {
        for task in todaysTasks {
            modelContext.delete(task)
        }
        saveContext()
    }

    /// Get completion rate for today
    var todayCompletionRate: Double {
        guard !todaysTasks.isEmpty else { return 0 }
        return Double(completedTasks.count) / Double(todaysTasks.count)
    }

    /// Get tasks related to a specific job source
    func tasks(forSourceId sourceId: UUID) -> [DailyTask] {
        todaysTasks.filter { $0.relatedJobSourceId == sourceId }
    }

    /// Get tasks related to a specific job application
    func tasks(forJobAppId jobAppId: UUID) -> [DailyTask] {
        todaysTasks.filter { $0.relatedJobAppId == jobAppId }
    }

    /// Get tasks related to a specific contact
    func tasks(forContactId contactId: UUID) -> [DailyTask] {
        todaysTasks.filter { $0.relatedContactId == contactId }
    }

    /// Get tasks related to a specific event
    func tasks(forEventId eventId: UUID) -> [DailyTask] {
        todaysTasks.filter { $0.relatedEventId == eventId }
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
