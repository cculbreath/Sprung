//
//  WeeklyGoalStore.swift
//  Sprung
//
//  Store for managing weekly goals.
//

import SwiftData
import Foundation

@Observable
@MainActor
final class WeeklyGoalStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    var allGoals: [WeeklyGoal] {
        (try? modelContext.fetch(
            FetchDescriptor<WeeklyGoal>(sortBy: [SortDescriptor(\.weekStartDate, order: .reverse)])
        )) ?? []
    }

    /// Get current week's goal if it exists (nil if not created yet)
    func currentWeekGoal() -> WeeklyGoal? {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        return allGoals.first(where: {
            calendar.isDate($0.weekStartDate, equalTo: weekStart, toGranularity: .weekOfYear)
        })
    }

    /// Get or create current week's goal
    func currentWeek() -> WeeklyGoal {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        // Check if we have a goal for this week
        if let existing = allGoals.first(where: {
            calendar.isDate($0.weekStartDate, equalTo: weekStart, toGranularity: .weekOfYear)
        }) {
            return existing
        }

        // Create new goal for this week
        let newGoal = WeeklyGoal(weekStartDate: weekStart)
        modelContext.insert(newGoal)
        saveContext()
        return newGoal
    }

    func add(_ goal: WeeklyGoal) {
        modelContext.insert(goal)
        saveContext()
    }

    func update(_ goal: WeeklyGoal) {
        saveContext()
    }

    func delete(_ goal: WeeklyGoal) {
        modelContext.delete(goal)
        saveContext()
    }

    func goal(byId id: UUID) -> WeeklyGoal? {
        allGoals.first { $0.id == id }
    }

    func goal(forWeekStarting date: Date) -> WeeklyGoal? {
        let calendar = Calendar.current
        return allGoals.first {
            calendar.isDate($0.weekStartDate, equalTo: date, toGranularity: .weekOfYear)
        }
    }

    // MARK: - Progress Updates

    func incrementApplications() {
        let goal = currentWeek()
        goal.applicationActual += 1
        saveContext()
    }

    func incrementEventsAttended() {
        let goal = currentWeek()
        goal.eventsAttendedActual += 1
        saveContext()
    }

    func incrementNewContacts(count: Int = 1) {
        let goal = currentWeek()
        goal.newContactsActual += count
        saveContext()
    }

    func incrementFollowUpsSent() {
        let goal = currentWeek()
        goal.followUpsSentActual += 1
        saveContext()
    }

    func addTimeMinutes(_ minutes: Int) {
        let goal = currentWeek()
        goal.actualMinutes += minutes
        saveContext()
    }

    // MARK: - Reflection

    func setReflection(_ reflection: String) {
        let goal = currentWeek()
        goal.llmReflection = reflection
        goal.reflectionGeneratedAt = Date()
        saveContext()
    }

    // MARK: - Statistics

    /// Get previous N weeks of goals for trend analysis
    func recentGoals(count: Int = 4) -> [WeeklyGoal] {
        Array(allGoals.prefix(count))
    }

    /// Average application rate over recent weeks
    func averageApplicationRate(weeks: Int = 4) -> Double {
        let recent = recentGoals(count: weeks)
        guard !recent.isEmpty else { return 0 }
        let total = recent.reduce(0) { $0 + $1.applicationActual }
        return Double(total) / Double(recent.count)
    }

    /// Average time per week over recent weeks
    func averageTimePerWeek(weeks: Int = 4) -> Int {
        let recent = recentGoals(count: weeks)
        guard !recent.isEmpty else { return 0 }
        let total = recent.reduce(0) { $0 + $1.actualMinutes }
        return total / recent.count
    }

    /// Reset current week's progress (keeps targets)
    func resetCurrentWeek() {
        let goal = currentWeek()
        goal.applicationActual = 0
        goal.eventsAttendedActual = 0
        goal.newContactsActual = 0
        goal.followUpsSentActual = 0
        goal.actualMinutes = 0
        goal.userNotes = nil
        goal.llmReflection = nil
        goal.reflectionGeneratedAt = nil
        saveContext()
    }
}
