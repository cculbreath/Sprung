//
//  WorkingMemoryBuilder.swift
//  Sprung
//
//  Builds working memory context for LLM system prompts.
//  Extracted from AnthropicRequestBuilder for single responsibility.
//

import Foundation
import SwiftyJSON

/// Builds working memory context from StateCoordinator for LLM system prompts
struct WorkingMemoryBuilder {
    private let stateCoordinator: StateCoordinator

    init(stateCoordinator: StateCoordinator) {
        self.stateCoordinator = stateCoordinator
    }

    // MARK: - Working Memory

    /// Build working memory string for system prompt
    func buildWorkingMemory() async -> String? {
        let phase = await stateCoordinator.phase

        var parts: [String] = []
        parts.append("## Working Memory (Phase: \(phase.shortName))")

        let currentPanel = await stateCoordinator.getCurrentToolPaneCard()
        if currentPanel != .none {
            parts.append("Visible UI: \(currentPanel.rawValue)")
        } else {
            parts.append("Visible UI: none (call upload/prompt tools to show UI)")
        }

        let objectives = await stateCoordinator.getObjectivesForPhase(phase)
        if !objectives.isEmpty {
            let statusList = objectives.map { "\($0.id): \($0.status.rawValue)" }
            parts.append("Objectives: \(statusList.joined(separator: ", "))")
        }

        let artifacts = await stateCoordinator.artifacts
        if let entries = artifacts.skeletonTimeline?["experiences"].array, !entries.isEmpty {
            let timelineSummary = entries.prefix(6).compactMap { entry -> String? in
                guard let org = entry["organization"].string,
                      let title = entry["title"].string else { return nil }
                let dates = [entry["start"].string, entry["end"].string]
                    .compactMap { $0 }
                    .joined(separator: "-")
                return "\(title) @ \(org)" + (dates.isEmpty ? "" : " (\(dates))")
            }
            if !timelineSummary.isEmpty {
                parts.append("Timeline (\(entries.count) entries): \(timelineSummary.joined(separator: "; "))")
            }
        }

        let artifactSummaries = await stateCoordinator.listArtifactSummaries()
        if !artifactSummaries.isEmpty {
            let artifactSummary = artifactSummaries.prefix(6).compactMap { record -> String? in
                guard let filename = record["filename"].string else { return nil }
                let desc = record["brief_description"].string ?? record["summary"].string ?? ""
                let shortDesc = desc.isEmpty ? "" : " - \(String(desc.prefix(40)))"
                return filename + shortDesc
            }
            if !artifactSummary.isEmpty {
                parts.append("Artifacts (\(artifactSummaries.count)): \(artifactSummary.joined(separator: "; "))")
            }
        }

        let dossierNotes = await stateCoordinator.getDossierNotes()
        if !dossierNotes.isEmpty {
            let truncatedNotes = String(dossierNotes.prefix(800))
            parts.append("Dossier Notes:\n\(truncatedNotes)")
        }

        guard parts.count > 1 else { return nil }

        let memory = parts.joined(separator: "\n")
        let maxChars = 2500
        if memory.count > maxChars {
            Logger.warning("⚠️ WorkingMemory exceeds target (\(memory.count) chars)", category: .ai)
            return String(memory.prefix(maxChars))
        }

        Logger.debug("📋 WorkingMemory: \(memory.count) chars", category: .ai)
        return memory
    }
}
