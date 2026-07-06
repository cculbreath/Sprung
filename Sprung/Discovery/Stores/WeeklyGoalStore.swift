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
    private let jobAppStore: JobAppStore
    /// Live read of the user's search preferences — the single source of
    /// truth for the weekly application and events targets. New week rows
    /// snapshot these at mint time; target edits (Weekly Review editor,
    /// Discovery onboarding) write preferences first, then re-snapshot the
    /// current row via `applyTargetsToCurrentWeek`.
    private let currentPreferences: @MainActor () -> SearchPreferences

    init(
        context: ModelContext,
        jobAppStore: JobAppStore,
        currentPreferences: @escaping @MainActor () -> SearchPreferences
    ) {
        modelContext = context
        self.jobAppStore = jobAppStore
        self.currentPreferences = currentPreferences
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

        // Create new goal for this week, seeded from search preferences —
        // the source of truth for application/events targets. The contacts
        // target has no preferences field; it carries forward from the most
        // recent prior week's row (the model's initial value only applies to
        // the very first week ever minted).
        let newGoal = WeeklyGoal(weekStartDate: weekStart)
        let prefs = currentPreferences()
        newGoal.applicationTarget = prefs.weeklyApplicationTarget
        newGoal.eventsAttendedTarget = prefs.weeklyNetworkingTarget
        if let previous = allGoals.first(where: { $0.weekStartDate < weekStart }) {
            newGoal.newContactsTarget = previous.newContactsTarget
        }
        modelContext.insert(newGoal)
        saveContext()
        return newGoal
    }

    /// Snapshot edited targets onto the current week's row (minting it if
    /// needed). Callers update `SearchPreferences` first — preferences are
    /// what future weeks are seeded from; this call makes the edit visible
    /// in the current week too. Pass `nil` contacts to leave the row's
    /// contacts target unchanged (onboarding doesn't collect one).
    func applyTargetsToCurrentWeek(applications: Int, events: Int, contacts: Int?) {
        let goal = currentWeek()
        goal.applicationTarget = applications
        goal.eventsAttendedTarget = events
        if let contacts {
            goal.newContactsTarget = contacts
        }
        saveContext()
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

    // MARK: - Application Count (Data-Driven)

    /// Count applications submitted during the current ISO week by querying JobApp.appliedDate
    func applicationsSubmittedThisWeek() -> Int {
        let (weekStart, weekEnd) = currentWeekRange()
        return jobAppStore.jobApps.filter { jobApp in
            guard let appliedDate = jobApp.appliedDate else { return false }
            return appliedDate >= weekStart && appliedDate < weekEnd
        }.count
    }

    /// Count applications submitted during a specific week (for historical queries)
    func applicationsSubmittedInWeek(_ weekStart: Date) -> Int {
        let calendar = Calendar.current
        guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { return 0 }
        return jobAppStore.jobApps.filter { jobApp in
            guard let appliedDate = jobApp.appliedDate else { return false }
            return appliedDate >= weekStart && appliedDate < weekEnd
        }.count
    }

    /// Current week's start and end dates (ISO calendar)
    private func currentWeekRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? Date()
        return (weekStart, weekEnd)
    }

    // MARK: - Progress Updates

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

    // MARK: - Reflection

    func setReflection(_ reflection: String) {
        let goal = currentWeek()
        goal.llmReflection = reflection
        goal.reflectionGeneratedAt = Date()
        saveContext()
    }

    /// The user's saved Weekly Review notes from the most recent week before
    /// the current one. Fed into the weekly-reflection generation context and
    /// the coaching system prompt so reflection compounds week over week
    /// instead of vanishing into a write-only field.
    func previousWeekUserNotes() -> String? {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        return allGoals.first(where: { goal in
            guard goal.weekStartDate < weekStart else { return false }
            let notes = goal.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !notes.isEmpty
        })?.userNotes
    }

    // MARK: - Statistics

    /// Get previous N weeks of goals for trend analysis
    func recentGoals(count: Int = 4) -> [WeeklyGoal] {
        Array(allGoals.prefix(count))
    }

    /// Average application rate over recent weeks (data-driven from JobApp.appliedDate)
    func averageApplicationRate(weeks: Int = 4) -> Double {
        let recent = recentGoals(count: weeks)
        guard !recent.isEmpty else { return 0 }
        let total = recent.reduce(0) { $0 + applicationsSubmittedInWeek($1.weekStartDate) }
        return Double(total) / Double(recent.count)
    }

    /// Reset current week's progress (keeps targets)
    /// Note: applicationActual is no longer stored — it's computed from JobApp.appliedDate
    func resetCurrentWeek() {
        let goal = currentWeek()
        goal.eventsAttendedActual = 0
        goal.newContactsActual = 0
        goal.userNotes = nil
        goal.llmReflection = nil
        goal.reflectionGeneratedAt = nil
        saveContext()
    }
}
