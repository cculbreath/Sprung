//
//  KCAgentPrompts.swift
//  Sprung
//
//  Centralized prompts for Knowledge Card (KC) generation agents.
//  Uses fact-based extraction that produces structured facts with source attribution.
//

import Foundation
import SwiftyJSON

// MARK: - JSON Artifact Extension

extension JSON {
    /// Computed folder name for an artifact (matches OnboardingArtifactRecord.artifactFolderName)
    var artifactFolderName: String {
        let filename = self["filename"].stringValue
        let id = self["id"].stringValue

        let baseName: String
        if !filename.isEmpty {
            let nameWithoutExt = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            baseName = nameWithoutExt.isEmpty ? filename : nameWithoutExt
        } else {
            baseName = id
        }

        // Sanitize for filesystem
        return baseName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - KC Agent Prompts

enum KCAgentPrompts {

    // MARK: - System Prompt

    /// System prompt for fact-based KC extraction.
    /// Uses strict schema output for guaranteed valid JSON.
    static func systemPrompt(
        cardId: String,
        cardType: String,
        title: String
    ) -> String {
        PromptLibrary.substitute(
            template: PromptLibrary.kcFactExtractionSystem,
            replacements: [
                "CARD_ID": cardId,
                "CARD_TYPE": cardType,
                "TITLE": title
            ]
        )
    }

    // MARK: - Initial Prompt

    /// Initial prompt for fact-based KC extraction with card proposal data.
    /// - Parameters:
    ///   - proposal: The CardProposal from dispatch
    ///   - allArtifacts: All artifact summaries for context
    /// - Returns: Formatted initial prompt
    static func initialPrompt(
        proposal: CardProposal,
        allArtifacts: [JSON]
    ) -> String {
        // Build assigned artifacts section (first assigned is primary)
        var assignedArtifacts = ""
        let allAssignedIds = proposal.assignedArtifactIds
        let primaryId = allAssignedIds.first
        var assignedFolders: [String] = []

        for artifact in allArtifacts where allAssignedIds.contains(artifact["id"].stringValue) {
            let filename = artifact["filename"].stringValue
            let artifactId = artifact["id"].stringValue
            let folder = artifact.artifactFolderName
            let summary = artifact["summary"].stringValue
            let docType = artifact["summary_metadata"]["document_type"].stringValue

            let isPrimary = artifactId == primaryId
            let marker = isPrimary ? " (PRIMARY SOURCE)" : ""
            assignedFolders.append(folder)

            assignedArtifacts += """

            ### \(filename)\(marker)
            **Folder**: `\(folder)/`
            **Type**: \(docType)
            **Files**:
            - `\(folder)/extracted_text.txt` - Full document text
            - `\(folder)/summary.txt` - Document summary
            - `\(folder)/card_inventory.json` - Card proposals (if exists)

            **Summary**: \(summary)
            """
        }

        // Build other artifacts section
        var otherArtifacts = ""
        for artifact in allArtifacts where !allAssignedIds.contains(artifact["id"].stringValue) {
            let filename = artifact["filename"].stringValue
            let folder = artifact.artifactFolderName
            let briefDesc = artifact["brief_description"].string
                ?? artifact["summary_metadata"]["brief_description"].string
                ?? artifact["summary_metadata"]["document_type"].string
                ?? "document"

            otherArtifacts += "\n- **\(filename)** (`\(folder)/`): \(briefDesc)"
        }

        // Build card inventory JSON from proposal
        var cardInventory: [String: Any] = [
            "card_id": proposal.cardId,
            "card_type": proposal.cardType,
            "title": proposal.title,
            "assigned_folders": assignedFolders
        ]
        if let timelineId = proposal.timelineEntryId {
            cardInventory["timeline_entry_id"] = timelineId
        }
        if let notes = proposal.notes {
            cardInventory["notes"] = notes
        }
        let cardInventoryJSON = (try? JSONSerialization.data(withJSONObject: cardInventory))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        // Build extraction checklist based on card type
        let checklist = extractionChecklist(for: proposal.cardType)

        // Optional fields
        let timelineEntry = proposal.timelineEntryId.map { "\n**Timeline Entry**: \($0)" } ?? ""
        let notes = proposal.notes ?? ""

        // Build chat excerpts section if any
        var chatExcerptsSection = ""
        if !proposal.chatExcerpts.isEmpty {
            chatExcerptsSection = "\n\n## Conversation Excerpts\n"
            for (index, excerpt) in proposal.chatExcerpts.enumerated() {
                chatExcerptsSection += "\n### Excerpt \(index + 1)"
                if let context = excerpt.context {
                    chatExcerptsSection += " (\(context))"
                }
                chatExcerptsSection += "\n> \"\(excerpt.excerpt)\"\n"
            }
        }

        return PromptLibrary.substitute(
            template: PromptLibrary.kcFactExtractionInitial,
            replacements: [
                "CARD_ID": proposal.cardId,
                "CARD_TYPE": proposal.cardType,
                "TITLE": proposal.title,
                "TIMELINE_ENTRY": timelineEntry,
                "NOTES": notes + chatExcerptsSection,
                "CARD_INVENTORY_JSON": cardInventoryJSON,
                "ASSIGNED_ARTIFACTS": assignedArtifacts.isEmpty ? "\n(No artifacts assigned)" : assignedArtifacts,
                "OTHER_ARTIFACTS": otherArtifacts.isEmpty ? "\n(No other artifacts)" : otherArtifacts,
                "EXTRACTION_CHECKLIST": checklist
            ]
        )
    }

    /// Type-specific extraction checklist
    private static func extractionChecklist(for cardType: String) -> String {
        switch cardType.lowercased() {
        case "employment", "job":
            return """
            - [ ] Role title and level
            - [ ] Organization name
            - [ ] Start/end dates
            - [ ] Team size and reporting structure
            - [ ] Key responsibilities (each as separate fact)
            - [ ] Projects led or contributed to
            - [ ] Technologies used
            - [ ] Quantified achievements (revenue, users, efficiency)
            - [ ] Promotions or scope changes
            """
        case "project":
            return """
            - [ ] Project name
            - [ ] Organization/employer context
            - [ ] Timeline (start, end, duration)
            - [ ] Role in project
            - [ ] Team size
            - [ ] Technologies and tools
            - [ ] Problem solved or goal achieved
            - [ ] Quantified outcomes
            - [ ] Stakeholders or users impacted
            """
        case "skill":
            return """
            - [ ] Skill name and category
            - [ ] Years of experience
            - [ ] Proficiency level with evidence
            - [ ] Projects where skill was applied
            - [ ] Specific tools or frameworks within skill
            - [ ] Certifications or training
            - [ ] Notable outcomes using this skill
            """
        case "achievement":
            return """
            - [ ] Achievement title
            - [ ] Date or time period
            - [ ] Context (role, project, organization)
            - [ ] Quantified impact
            - [ ] Recognition received (awards, promotions)
            - [ ] Skills demonstrated
            """
        case "education":
            return """
            - [ ] Degree or certification name
            - [ ] Institution
            - [ ] Dates attended
            - [ ] Major/concentration
            - [ ] GPA if notable
            - [ ] Relevant coursework
            - [ ] Academic achievements
            - [ ] Extracurricular activities
            """
        default:
            return """
            - [ ] Title and type
            - [ ] Time period
            - [ ] Key details
            - [ ] Quantified outcomes
            - [ ] Skills demonstrated
            """
        }
    }

    // MARK: - Expand KC Prompts

    /// System prompt for KC expansion agent.
    static func expandSystemPrompt(
        cardId: String,
        cardType: String,
        title: String
    ) -> String {
        PromptLibrary.substitute(
            template: PromptLibrary.kcExpandSystem,
            replacements: [
                "CARD_ID": cardId,
                "CARD_TYPE": cardType,
                "TITLE": title
            ]
        )
    }

    /// Initial prompt for expanding an existing KC with new evidence.
    /// - Parameters:
    ///   - existingCard: The ResRef to expand
    ///   - newArtifacts: New artifact JSON objects containing additional evidence
    /// - Returns: Formatted expand prompt
    static func expandInitialPrompt(
        existingCard: ResRef,
        newArtifacts: [JSON]
    ) -> String {
        // Get existing facts count
        var factCount = 0
        var existingFactsJSON = "[]"
        if let factsJSON = existingCard.factsJSON,
           let data = factsJSON.data(using: .utf8),
           let facts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            factCount = facts.count
            if let prettyData = try? JSONSerialization.data(withJSONObject: facts, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                existingFactsJSON = prettyString
            }
        }

        // Get existing bullets
        var existingBulletsJSON = "[]"
        if let bulletsJSON = existingCard.suggestedBulletsJSON,
           let data = bulletsJSON.data(using: .utf8),
           let bullets = try? JSONSerialization.jsonObject(with: data) as? [String] {
            if let prettyData = try? JSONSerialization.data(withJSONObject: bullets, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                existingBulletsJSON = prettyString
            }
        }

        // Get existing technologies
        var existingTechnologies = "(none)"
        if let techJSON = existingCard.technologiesJSON,
           let data = techJSON.data(using: .utf8),
           let techs = try? JSONSerialization.jsonObject(with: data) as? [String],
           !techs.isEmpty {
            existingTechnologies = techs.joined(separator: ", ")
        }

        // Get existing sources
        var existingSources = "(none)"
        if let sourcesJSON = existingCard.sourcesJSON,
           let data = sourcesJSON.data(using: .utf8),
           let sources = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            let ids = sources.compactMap { $0["artifact_id"] }
            if !ids.isEmpty {
                existingSources = ids.joined(separator: ", ")
            }
        }

        // Build new artifacts section
        var newArtifactsSection = ""
        for artifact in newArtifacts {
            let filename = artifact["filename"].stringValue
            let folder = artifact.artifactFolderName
            let summary = artifact["summary"].stringValue
            let docType = artifact["summary_metadata"]["document_type"].stringValue

            newArtifactsSection += """

            ### \(filename)
            **Folder**: `\(folder)/`
            **Type**: \(docType)
            **Files**:
            - `\(folder)/extracted_text.txt` - Full document text
            - `\(folder)/summary.txt` - Document summary

            **Summary**: \(summary)
            """
        }

        return PromptLibrary.substitute(
            template: PromptLibrary.kcExpandInitial,
            replacements: [
                "CARD_ID": existingCard.id.uuidString,
                "CARD_TYPE": existingCard.cardType ?? "employment",
                "TITLE": existingCard.name,
                "ORGANIZATION": existingCard.organization ?? "(not specified)",
                "TIME_PERIOD": existingCard.timePeriod ?? "(not specified)",
                "FACT_COUNT": String(factCount),
                "EXISTING_FACTS_JSON": existingFactsJSON,
                "EXISTING_BULLETS_JSON": existingBulletsJSON,
                "EXISTING_TECHNOLOGIES": existingTechnologies,
                "EXISTING_SOURCES": existingSources,
                "NEW_ARTIFACTS": newArtifactsSection.isEmpty ? "(No new artifacts)" : newArtifactsSection
            ]
        )
    }
}
