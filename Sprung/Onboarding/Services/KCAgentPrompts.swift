//
//  KCAgentPrompts.swift
//  Sprung
//
//  Centralized prompts for Knowledge Card (KC) generation agents.
//  Uses fact-based extraction that produces structured facts with source attribution.
//

import Foundation
import SwiftyJSON

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

        for artifact in allArtifacts where allAssignedIds.contains(artifact["id"].stringValue) {
            let filename = artifact["filename"].stringValue
            let artifactId = artifact["id"].stringValue
            let summary = artifact["summary"].stringValue
            let docType = artifact["summary_metadata"]["document_type"].stringValue

            let isPrimary = artifactId == primaryId
            let marker = isPrimary ? " (PRIMARY SOURCE)" : ""

            assignedArtifacts += """

            ### \(filename)\(marker)
            **ID**: \(artifactId)
            **Type**: \(docType)

            \(summary)
            """
        }

        // Build other artifacts section
        var otherArtifacts = ""
        for artifact in allArtifacts where !allAssignedIds.contains(artifact["id"].stringValue) {
            let filename = artifact["filename"].stringValue
            let artifactId = artifact["id"].stringValue
            let briefDesc = artifact["brief_description"].string
                ?? artifact["summary_metadata"]["brief_description"].string
                ?? artifact["summary_metadata"]["document_type"].string
                ?? "document"

            otherArtifacts += "\n- **\(filename)** (ID: \(artifactId)): \(briefDesc)"
        }

        // Build card inventory JSON from proposal
        var cardInventory: [String: Any] = [
            "card_id": proposal.cardId,
            "card_type": proposal.cardType,
            "title": proposal.title,
            "assigned_artifact_ids": proposal.assignedArtifactIds
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
}
