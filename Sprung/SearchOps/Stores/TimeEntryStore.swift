//
//  TimeEntryStore.swift
//  Sprung
//
//  Store for managing time tracking entries.
//

import SwiftData
import Foundation

@Observable
@MainActor
final class TimeEntryStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    var allEntries: [TimeEntry] {
        (try? modelContext.fetch(
            FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        )) ?? []
    }

    func add(_ entry: TimeEntry) {
        modelContext.insert(entry)
        saveContext()
    }

    func delete(_ entry: TimeEntry) {
        modelContext.delete(entry)
        saveContext()
    }

    func update(_ entry: TimeEntry) {
        saveContext()
    }

    func entry(byId id: UUID) -> TimeEntry? {
        allEntries.first { $0.id == id }
    }

    // MARK: - Date-based Queries

    func entriesForDate(_ date: Date) -> [TimeEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        return allEntries.filter {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
    }

    func entriesInRange(from startDate: Date, to endDate: Date) -> [TimeEntry] {
        allEntries.filter {
            $0.startTime >= startDate && $0.startTime <= endDate
        }
    }

    func entriesForCurrentWeek() -> [TimeEntry] {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        return entriesInRange(from: weekStart, to: Date())
    }

    // MARK: - Time Summaries

    func totalMinutesForDate(_ date: Date) -> Int {
        entriesForDate(date).reduce(0) { $0 + $1.durationMinutes }
    }

    func totalMinutesForCurrentWeek() -> Int {
        entriesForCurrentWeek().reduce(0) { $0 + $1.durationMinutes }
    }

    /// Convenience computed property for this week's total
    var totalMinutesThisWeek: Int {
        totalMinutesForCurrentWeek()
    }

    func breakdownByActivity(for entries: [TimeEntry]) -> [ActivityType: Int] {
        var breakdown: [ActivityType: Int] = [:]
        for entry in entries {
            breakdown[entry.activityType, default: 0] += entry.durationMinutes
        }
        return breakdown
    }

    var todaysBreakdown: [ActivityType: Int] {
        breakdownByActivity(for: entriesForDate(Date()))
    }

    var thisWeeksBreakdown: [ActivityType: Int] {
        breakdownByActivity(for: entriesForCurrentWeek())
    }

    // MARK: - Formatted Outputs

    func formattedTotalForDate(_ date: Date) -> String {
        formatMinutes(totalMinutesForDate(date))
    }

    func formattedTotalForCurrentWeek() -> String {
        formatMinutes(totalMinutesForCurrentWeek())
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    // MARK: - Weekly Summary

    func weeklySummary() -> WeeklyTimeSummary {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        let entries = entriesInRange(from: weekStart, to: Date())

        var dailyTotals: [Date: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.startTime)
            dailyTotals[day, default: 0] += entry.durationMinutes
        }

        let totalMinutes = entries.reduce(0) { $0 + $1.durationMinutes }
        let daysWithActivity = max(1, dailyTotals.count)

        return WeeklyTimeSummary(
            weekStart: weekStart,
            totalMinutes: totalMinutes,
            dailyTotals: dailyTotals,
            averageMinutesPerDay: totalMinutes / daysWithActivity
        )
    }
}

// MARK: - Summary Types

struct DailyTimeSummary {
    let date: Date
    let totalMinutes: Int
    let breakdown: [ActivityType: Int]

    var formattedTotal: String {
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

struct WeeklyTimeSummary {
    let weekStart: Date
    let totalMinutes: Int
    let dailyTotals: [Date: Int]
    let averageMinutesPerDay: Int

    var formattedTotal: String {
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    var formattedAverage: String {
        let hours = averageMinutesPerDay / 60
        let mins = averageMinutesPerDay % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}
