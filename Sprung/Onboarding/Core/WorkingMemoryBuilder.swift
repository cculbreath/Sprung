//
//  WorkingMemoryBuilder.swift
//  Sprung
//
//  Builds interview context as XML for inclusion in user messages.
//  Per Anthropic best practices, uses XML tags to delineate app context
//  rather than stuffing into system prompt.
//

import Foundation
import SwiftyJSON

/// Builds interview context XML from StateCoordinator for user messages
struct WorkingMemoryBuilder {
    private let stateCoordinator: StateCoordinator

    init(stateCoordinator: StateCoordinator) {
        self.stateCoordinator = stateCoordinator
    }

    // MARK: - Interview Context (XML for user messages)

    /// Build interview context as XML for inclusion in user messages.
    /// This replaces the old system prompt approach with Anthropic-native XML tags.
    func buildInterviewContext() async -> String? {
        let phase = await stateCoordinator.phase

        var xml: [String] = []
        xml.append("<interview_context>")
        xml.append("  <phase>\(phase.rawValue)</phase>")

        // Current UI state
        let currentPanel = await stateCoordinator.getCurrentToolPaneCard()
        xml.append("  <visible_ui>\(currentPanel == .none ? "none" : currentPanel.rawValue)</visible_ui>")

        // Objectives
        let objectives = await stateCoordinator.getObjectivesForPhase(phase)
        if !objectives.isEmpty {
            xml.append("  <objectives>")
            for obj in objectives {
                xml.append("    <objective id=\"\(obj.id)\" status=\"\(obj.status.rawValue)\"/>")
            }
            xml.append("  </objectives>")
        }

        // Timeline summary
        let artifacts = await stateCoordinator.artifacts
        if let entries = artifacts.skeletonTimeline?["experiences"].array, !entries.isEmpty {
            xml.append("  <timeline count=\"\(entries.count)\">")
            for entry in entries.prefix(6) {
                let org = entry["organization"].stringValue
                let title = entry["title"].stringValue
                let start = entry["start"].stringValue
                let end = entry["end"].stringValue.isEmpty ? "present" : entry["end"].stringValue
                xml.append("    <entry>\(escapeXML(title)) @ \(escapeXML(org)) (\(start)-\(end))</entry>")
            }
            if entries.count > 6 {
                xml.append("    <entry>... and \(entries.count - 6) more</entry>")
            }
            xml.append("  </timeline>")
        }

        // Artifacts summary
        let artifactSummaries = await stateCoordinator.listArtifactSummaries()
        if !artifactSummaries.isEmpty {
            xml.append("  <artifacts count=\"\(artifactSummaries.count)\">")
            for record in artifactSummaries.prefix(6) {
                let filename = record["filename"].stringValue
                let desc = record["briefDescription"].string ?? record["summary"].string ?? ""
                let shortDesc = desc.isEmpty ? "" : ": \(String(desc.prefix(40)))"
                xml.append("    <artifact>\(escapeXML(filename))\(escapeXML(shortDesc))</artifact>")
            }
            if artifactSummaries.count > 6 {
                xml.append("    <artifact>... and \(artifactSummaries.count - 6) more</artifact>")
            }
            xml.append("  </artifacts>")
        }

        // Dossier notes (if any)
        let dossierNotes = await stateCoordinator.getDossierNotes()
        if !dossierNotes.isEmpty {
            let truncatedNotes = String(dossierNotes.prefix(600))
            xml.append("  <dossier_notes>\(escapeXML(truncatedNotes))</dossier_notes>")
        }

        // Running agents (if any)
        if let runningAgents = await stateCoordinator.getRunningAgentStatus(), !runningAgents.isEmpty {
            xml.append("  <running_agents count=\"\(runningAgents.count)\">")
            for agent in runningAgents {
                xml.append("    <agent type=\"\(agent.type)\">\(escapeXML(agent.name)): \(escapeXML(agent.status))</agent>")
            }
            xml.append("  </running_agents>")
            xml.append("  <note>Background agents are processing. Results will be reported when complete.</note>")
        }

        // Recently completed agents (within last 30 seconds)
        if let completedAgents = await stateCoordinator.getRecentlyCompletedAgents(), !completedAgents.isEmpty {
            xml.append("  <completed_agents count=\"\(completedAgents.count)\">")
            for agent in completedAgents {
                let status = agent.succeeded ? "succeeded" : "failed"
                xml.append("    <agent type=\"\(agent.type)\" status=\"\(status)\" duration=\"\(agent.duration)\">\(escapeXML(agent.name))</agent>")
            }
            xml.append("  </completed_agents>")
        }

        xml.append("</interview_context>")

        let context = xml.joined(separator: "\n")
        let maxChars = 2500
        if context.count > maxChars {
            Logger.warning("⚠️ InterviewContext exceeds target (\(context.count) chars)", category: .ai)
        }

        Logger.debug("📋 InterviewContext: \(context.count) chars", category: .ai)
        return context
    }

    /// Legacy method - now delegates to buildInterviewContext for backwards compatibility
    func buildWorkingMemory() async -> String? {
        await buildInterviewContext()
    }

    // MARK: - XML Helpers

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
