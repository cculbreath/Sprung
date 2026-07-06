//
//  CoachingContextBuilder.swift
//  Sprung
//
//  Builds context strings for coaching LLM prompts.
//  Extracted from CoachingService for single responsibility.
//

import Foundation

/// Builds context strings for coaching LLM prompts
@MainActor
struct CoachingContextBuilder {
    private let preferencesStore: SearchPreferencesStore
    private let jobAppStore: JobAppStore
    private let weeklyGoalStore: WeeklyGoalStore

    init(
        preferencesStore: SearchPreferencesStore,
        jobAppStore: JobAppStore,
        weeklyGoalStore: WeeklyGoalStore
    ) {
        self.preferencesStore = preferencesStore
        self.jobAppStore = jobAppStore
        self.weeklyGoalStore = weeklyGoalStore
    }

    /// Build list of available knowledge cards with metadata
    func buildKnowledgeCardsList(from knowledgeCards: [KnowledgeCard]) -> String {
        guard !knowledgeCards.isEmpty else {
            return "No knowledge cards available."
        }

        var lines: [String] = []
        for card in knowledgeCards {
            var line = "- ID: `\(card.id.uuidString)` | **\(card.title)**"
            if let cardType = card.cardType {
                line += " (\(cardType.rawValue))"
            }
            if let organization = card.organization, !organization.isEmpty {
                line += " @ \(organization)"
            }
            if let dateRange = card.dateRange, !dateRange.isEmpty {
                line += " | \(dateRange)"
            }
            let wordCount = card.narrative.split(separator: " ").count
            line += " | \(wordCount) words"
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    /// Build list of active job applications (identified through applying stages)
    func buildActiveJobAppsList() -> String {
        let activeStatuses: [Statuses] = [.new, .queued, .inProgress, .submitted, .interview, .offer]
        let activeApps = jobAppStore.jobApps.filter { activeStatuses.contains($0.status) }

        guard !activeApps.isEmpty else {
            return "No active job applications."
        }

        var lines: [String] = []
        for app in activeApps.prefix(20) {  // Limit to 20 to avoid overwhelming context
            var line = "- ID: `\(app.id.uuidString)` | **\(app.companyName)** - \(app.jobPosition)"
            line += " | Status: \(app.status.displayName)"
            if let appliedDate = app.appliedDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                line += " | Applied: \(formatter.string(from: appliedDate))"
            }
            lines.append(line)
        }

        if activeApps.count > 20 {
            lines.append("... and \(activeApps.count - 20) more active applications")
        }

        return lines.joined(separator: "\n")
    }

    /// Build the system prompt from template with substitutions
    func buildSystemPrompt(
        activitySummary: String,
        recentHistory: String,
        taskDelta: String,
        askedCategories: String,
        dossierContext: String,
        knowledgeCardsList: String,
        activeJobApps: String
    ) -> String {
        let preferences = preferencesStore.current()

        var template = loadPromptTemplate(named: "discovery_coaching_system")

        let substitutions: [String: String] = [
            "{{ACTIVITY_SUMMARY}}": activitySummary,
            "{{RECENT_HISTORY}}": recentHistory,
            "{{TASK_DELTA}}": taskDelta,
            "{{ASKED_CATEGORIES}}": askedCategories,
            "{{TARGET_SECTORS}}": preferences.targetSectors.joined(separator: ", "),
            "{{PRIMARY_LOCATION}}": preferences.primaryLocation,
            "{{REMOTE_ACCEPTABLE}}": preferences.remoteAcceptable ? "Yes" : "No",
            "{{WEEKLY_APPLICATION_TARGET}}": String(preferences.weeklyApplicationTarget),
            "{{WEEKLY_NETWORKING_TARGET}}": String(preferences.weeklyNetworkingTarget),
            "{{COMPANY_SIZE_PREFERENCE}}": preferences.companySizePreference.rawValue,
            "{{LAST_WEEK_REVIEW_NOTES}}": weeklyGoalStore.previousWeekUserNotes()
                ?? "No review notes from last week.",
            "{{DOSSIER_CONTEXT}}": dossierContext,
            "{{KNOWLEDGE_CARDS_LIST}}": knowledgeCardsList,
            "{{ACTIVE_JOB_APPS}}": activeJobApps
        ]

        for (placeholder, value) in substitutions {
            template = template.replacingOccurrences(of: placeholder, with: value)
        }

        return template
    }

    /// Format yesterday's (well, the most recent task day's) list + completion
    /// state, today's list so far, and the completion streak — the delta the
    /// coach opens with.
    func buildTaskDeltaSummary(
        previousDay: (date: Date, tasks: [DailyTask])?,
        todaysTasks: [DailyTask],
        streakDays: Int
    ) -> String {
        var parts: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        if let previousDay {
            let done = previousDay.tasks.filter { $0.isCompleted }
            parts.append("### Last task day (\(dateFormatter.string(from: previousDay.date))): \(done.count) of \(previousDay.tasks.count) completed")
            for task in previousDay.tasks {
                let mark = task.isCompleted ? "[done]" : "[open]"
                parts.append("- \(mark) \(task.taskType.rawValue): \(task.title)")
            }
        } else {
            parts.append("No prior task list — this may be the user's first working day in the app.")
        }

        if !todaysTasks.isEmpty {
            let done = todaysTasks.filter { $0.isCompleted }
            parts.append("")
            parts.append("### Today's list so far: \(done.count) of \(todaysTasks.count) completed")
            for task in todaysTasks {
                let mark = task.isCompleted ? "[done]" : "[open]"
                parts.append("- \(mark) \(task.taskType.rawValue): \(task.title)")
            }
        }

        parts.append("")
        parts.append("Completion streak: \(streakDays) day(s) with at least one task completed.")

        return parts.joined(separator: "\n")
    }

    /// Load a prompt template from bundle
    private func loadPromptTemplate(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("🚨 Failed to load prompt template: \(name)")
            return ""
        }
        return content
    }
}
