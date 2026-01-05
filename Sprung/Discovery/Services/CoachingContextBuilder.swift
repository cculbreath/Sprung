//
//  CoachingContextBuilder.swift
//  Sprung
//
//  Builds context strings for coaching LLM prompts.
//  Extracted from CoachingService for single responsibility.
//

import Foundation
import SwiftyJSON

/// Builds context strings for coaching LLM prompts
@MainActor
struct CoachingContextBuilder {
    private let preferencesStore: SearchPreferencesStore
    private let jobAppStore: JobAppStore

    init(preferencesStore: SearchPreferencesStore, jobAppStore: JobAppStore) {
        self.preferencesStore = preferencesStore
        self.jobAppStore = jobAppStore
    }

    /// Build formatted dossier context from dossier entries
    func buildDossierContext(from dossierEntries: [JSON]) -> String {
        guard !dossierEntries.isEmpty else {
            return "No dossier entries available yet."
        }

        var sections: [String] = []
        for entry in dossierEntries {
            let section = entry["section"].stringValue
            let value = entry["value"].stringValue
            if !section.isEmpty && !value.isEmpty {
                sections.append("**\(section)**: \(value)")
            }
        }

        return sections.isEmpty ? "No dossier entries available yet." : sections.joined(separator: "\n")
    }

    /// Build list of available knowledge cards with metadata
    func buildKnowledgeCardsList(from knowledgeCards: [KnowledgeCardDraft]) -> String {
        guard !knowledgeCards.isEmpty else {
            return "No knowledge cards available."
        }

        var lines: [String] = []
        for card in knowledgeCards {
            var line = "- ID: `\(card.id.uuidString)` | **\(card.title)**"
            if let cardType = card.cardType, !cardType.isEmpty {
                line += " (\(cardType))"
            }
            if let organization = card.organization, !organization.isEmpty {
                line += " @ \(organization)"
            }
            if let timePeriod = card.timePeriod, !timePeriod.isEmpty {
                line += " | \(timePeriod)"
            }
            line += " | \(card.wordCount) words"
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
        dossierContext: String,
        knowledgeCardsList: String,
        activeJobApps: String
    ) -> String {
        let preferences = preferencesStore.current()

        var template = loadPromptTemplate(named: "discovery_coaching_system")

        let substitutions: [String: String] = [
            "{{ACTIVITY_SUMMARY}}": activitySummary,
            "{{RECENT_HISTORY}}": recentHistory,
            "{{TARGET_SECTORS}}": preferences.targetSectors.joined(separator: ", "),
            "{{PRIMARY_LOCATION}}": preferences.primaryLocation,
            "{{REMOTE_ACCEPTABLE}}": preferences.remoteAcceptable ? "Yes" : "No",
            "{{WEEKLY_APPLICATION_TARGET}}": String(preferences.weeklyApplicationTarget),
            "{{WEEKLY_NETWORKING_TARGET}}": String(preferences.weeklyNetworkingTarget),
            "{{COMPANY_SIZE_PREFERENCE}}": preferences.companySizePreference.rawValue,
            "{{DOSSIER_CONTEXT}}": dossierContext,
            "{{KNOWLEDGE_CARDS_LIST}}": knowledgeCardsList,
            "{{ACTIVE_JOB_APPS}}": activeJobApps
        ]

        for (placeholder, value) in substitutions {
            template = template.replacingOccurrences(of: placeholder, with: value)
        }

        return template
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
