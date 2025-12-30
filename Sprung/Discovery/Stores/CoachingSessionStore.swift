//
//  CoachingSessionStore.swift
//  Sprung
//
//  Store for managing coaching session history.
//

import SwiftData
import Foundation

@Observable
@MainActor
final class CoachingSessionStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    // MARK: - Queries

    var allSessions: [CoachingSession] {
        (try? modelContext.fetch(
            FetchDescriptor<CoachingSession>(sortBy: [SortDescriptor(\.sessionDate, order: .reverse)])
        )) ?? []
    }

    /// Get today's coaching session if one exists
    func todaysSession() -> CoachingSession? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return allSessions.first {
            calendar.isDate($0.sessionDate, inSameDayAs: startOfDay)
        }
    }

    /// Check if there's a completed session for today
    var hasCompletedSessionToday: Bool {
        todaysSession()?.isComplete ?? false
    }

    /// Get recent sessions (excluding today)
    func recentSessions(count: Int = 5) -> [CoachingSession] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return allSessions
            .filter { !calendar.isDate($0.sessionDate, inSameDayAs: startOfToday) }
            .prefix(count)
            .map { $0 }
    }

    /// Get session by ID
    func session(byId id: UUID) -> CoachingSession? {
        allSessions.first { $0.id == id }
    }

    /// Calculate days since last coaching session
    func daysSinceLastSession() -> Int {
        guard let lastSession = allSessions.first(where: { $0.isComplete }) else {
            return 0
        }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: lastSession.sessionDate, to: Date()).day ?? 0
    }

    /// Get the date of the last completed coaching session
    /// - Parameter before: Optional cutoff date; only returns sessions before this date
    func lastSessionDate(before cutoff: Date? = nil) -> Date? {
        let completed = allSessions.filter { $0.isComplete }
        if let cutoff = cutoff {
            return completed.first(where: { $0.sessionDate < cutoff })?.sessionDate
        }
        return completed.first?.sessionDate
    }

    // MARK: - Mutations

    func add(_ session: CoachingSession) {
        modelContext.insert(session)
        saveContext()
    }

    func update(_ session: CoachingSession) {
        _ = session // Silence unused warning - parameter needed for API consistency
        saveContext()
    }

    func delete(_ session: CoachingSession) {
        modelContext.delete(session)
        saveContext()
    }

    // MARK: - Summary Helpers

    /// Generate a text summary of recent coaching history for the LLM prompt
    func recentHistorySummary(sessionCount: Int = 5) -> String {
        let recent = recentSessions(count: sessionCount)

        if recent.isEmpty {
            return "No previous coaching sessions."
        }

        var parts: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        for session in recent {
            let date = dateFormatter.string(from: session.sessionDate)
            var sessionParts: [String] = ["### \(date)"]

            // Add Q&A summary
            let answers = session.answers
            if !answers.isEmpty {
                for answer in answers {
                    if let question = session.questions.first(where: { $0.id == answer.questionId }) {
                        sessionParts.append("- \(question.questionType.displayName): \(answer.selectedLabel)")
                    }
                }
            }

            // Add a brief excerpt of recommendations (first 200 chars)
            if !session.recommendations.isEmpty {
                let excerpt = String(session.recommendations.prefix(200))
                sessionParts.append("- Advice given: \(excerpt)...")
            }

            parts.append(sessionParts.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n\n")
    }
}
