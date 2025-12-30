//
//  KCAgentPrompts.swift
//  Sprung
//
//  Centralized prompts for Knowledge Card (KC) generation agents.
//  Each KC agent receives a system prompt defining its role and an initial
//  prompt with the card proposal and relevant artifact summaries.
//

import Foundation
import SwiftyJSON

enum KCAgentPrompts {

    // MARK: - System Prompt

    /// System prompt for a KC agent.
    /// Routes to type-specific extraction prompts for structured output.
    /// - Parameters:
    ///   - cardType: "job", "skill", "project", "achievement", or "education"
    ///   - title: Card title (e.g., "Senior Engineer at Company X")
    ///   - candidateName: The candidate's first name for prose references
    static func systemPrompt(
        cardType: String,
        title: String,
        candidateName: String? = nil
    ) -> String {
        let nameRef = candidateName ?? "the candidate"

        // Select type-specific extraction template
        let template = typeSpecificTemplate(for: cardType)

        return PromptLibrary.substitute(
            template: template,
            replacements: [
                "TITLE": title,
                "CARD_TYPE": cardType,
                "NAME_REF": nameRef
            ]
        )
    }

    /// Returns the type-specific extraction template for a card type
    /// Falls back to generic system prompt for unknown types
    private static func typeSpecificTemplate(for cardType: String) -> String {
        switch cardType.lowercased() {
        case "job", "employment":
            return PromptLibrary.kcExtractionEmployment
        case "skill":
            return PromptLibrary.kcExtractionSkill
        case "project":
            return PromptLibrary.kcExtractionProject
        case "achievement":
            return PromptLibrary.kcExtractionAchievement
        case "education":
            // Education uses employment template with education-specific guidance
            return PromptLibrary.kcExtractionEmployment
        default:
            // Fall back to generic template for unknown types
            return PromptLibrary.kcAgentSystemPromptTemplate
        }
    }

    // MARK: - Initial Prompt

    /// Initial prompt for a KC agent containing the card proposal and artifact summaries.
    /// - Assigned artifacts: Full summaries included for thorough context
    /// - Other artifacts: Brief descriptions only to save tokens (use get_artifact if needed)
    static func initialPrompt(proposal: CardProposal, allSummaries: [JSON]) -> String {
        // Build artifact sections - full summaries for assigned, brief for others
        var assignedSummaries = ""
        var otherArtifactsList = ""

        for summary in allSummaries {
            let artifactId = summary["id"].stringValue
            let filename = summary["filename"].stringValue

            if proposal.assignedArtifactIds.contains(artifactId) {
                // Full summary for assigned artifacts
                let summaryText = summary["summary"].stringValue
                let docType = summary["summary_metadata"]["document_type"].stringValue

                assignedSummaries += """

                ### \(filename) (ID: \(artifactId))
                Type: \(docType)
                \(summaryText)
                """
            } else {
                // Brief description only for other artifacts (token efficient)
                let briefDesc = summary["brief_description"].string
                    ?? summary["summary_metadata"]["brief_description"].string
                    ?? summary["summary_metadata"]["document_type"].string
                    ?? "document"

                otherArtifactsList += "\n- **\(filename)** (ID: \(artifactId)): \(briefDesc)"
            }
        }

        // Build chat excerpts section if any are provided
        var chatExcerptsSection = ""
        if !proposal.chatExcerpts.isEmpty {
            chatExcerptsSection = "\n\n## Conversation Excerpts\n"
            chatExcerptsSection += "The following are relevant quotes from the user's conversation. "
            chatExcerptsSection += "These are PRIMARY SOURCES - include this information in your knowledge card.\n"

            for (index, excerpt) in proposal.chatExcerpts.enumerated() {
                chatExcerptsSection += "\n### Excerpt \(index + 1)"
                if let context = excerpt.context {
                    chatExcerptsSection += " (\(context))"
                }
                chatExcerptsSection += "\n> \"\(excerpt.excerpt)\"\n"
            }
        }

        // Build dynamic content for template
        let timelineEntry = proposal.timelineEntryId.map { "\n**Timeline Entry**: \($0)" } ?? ""
        let notes = proposal.notes.map { "\n**Notes**: \($0)" } ?? ""
        let assignedSummariesText = assignedSummaries.isEmpty ? "\n(No specific artifacts assigned - review available artifacts below)" : assignedSummaries
        let otherArtifactsText = otherArtifactsList.isEmpty ? "\n(No other artifacts available)" : otherArtifactsList

        // Handle chat excerpts in instructions
        let chatInstructions = proposal.chatExcerpts.isEmpty ? "" : "3. Incorporate information from the conversation excerpts above\n"
        let finalStep = proposal.chatExcerpts.isEmpty ? "4. " : "5. "

        // Use template from PromptLibrary
        return PromptLibrary.substitute(
            template: PromptLibrary.kcInitialPromptTemplate,
            replacements: [
                "CARD_TYPE": proposal.cardType,
                "TITLE": proposal.title,
                "TIMELINE_ENTRY": timelineEntry,
                "NOTES": notes,
                "ASSIGNED_SUMMARIES": assignedSummariesText,
                "CHAT_EXCERPTS": chatExcerptsSection,
                "OTHER_ARTIFACTS": otherArtifactsText,
                "CHAT_INSTRUCTIONS": chatInstructions,
                "FINAL_STEP": finalStep
            ]
        )
    }

    // MARK: - Error Recovery Prompt

    /// Prompt sent when an agent encounters an error and needs to retry.
    static func errorRecoveryPrompt(error: String) -> String {
        PromptLibrary.substitute(
            template: PromptLibrary.kcErrorRecovery,
            replacements: ["ERROR": error]
        )
    }

    // MARK: - Skill Card Specific

    /// Additional guidance for skill-type cards.
    static func skillCardGuidance(skillName: String) -> String {
        PromptLibrary.substitute(
            template: PromptLibrary.kcSkillCardGuidance,
            replacements: ["SKILL_NAME": skillName]
        )
    }

    // MARK: - Job Card Specific

    /// Additional guidance for job-type cards.
    static func jobCardGuidance(jobTitle: String, company: String?) -> String {
        let companySuffix = company.map { " at \($0)" } ?? ""
        return PromptLibrary.substitute(
            template: PromptLibrary.kcJobCardGuidance,
            replacements: [
                "JOB_TITLE": jobTitle,
                "COMPANY_SUFFIX": companySuffix
            ]
        )
    }

    // MARK: - Fact-Based Extraction Prompts

    /// System prompt for fact-based KC extraction.
    /// Uses strict schema output for guaranteed valid JSON.
    static func factBasedSystemPrompt(
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

    /// Initial prompt for fact-based KC extraction with card inventory data.
    /// - Parameters:
    ///   - mergedCard: The MergedCard from cross-document merge
    ///   - allArtifacts: All artifact summaries for context
    /// - Returns: Formatted initial prompt
    static func factBasedInitialPrompt(
        mergedCard: MergedCardInventory.MergedCard,
        allArtifacts: [JSON]
    ) -> String {
        // Build assigned artifacts section
        var assignedArtifacts = ""
        let primaryId = mergedCard.primarySource.documentId
        let supportingIds = mergedCard.supportingSources.map { $0.documentId }
        let allAssignedIds = [primaryId] + supportingIds

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

        // Build card inventory JSON
        let cardInventoryJSON: String
        if let data = try? JSONEncoder().encode(mergedCard),
           let jsonString = String(data: data, encoding: .utf8) {
            cardInventoryJSON = jsonString
        } else {
            cardInventoryJSON = "{}"
        }

        // Build extraction checklist based on card type
        let checklist = extractionChecklist(for: mergedCard.cardType)

        // Optional fields
        let timelineEntry: String
        if let dateRange = mergedCard.dateRange, !dateRange.isEmpty {
            timelineEntry = "\n**Date Range**: \(dateRange)"
        } else {
            timelineEntry = ""
        }
        let notes = ""  // Notes would come from user feedback if any

        return PromptLibrary.substitute(
            template: PromptLibrary.kcFactExtractionInitial,
            replacements: [
                "CARD_ID": mergedCard.cardId,
                "CARD_TYPE": mergedCard.cardType,
                "TITLE": mergedCard.title,
                "TIMELINE_ENTRY": timelineEntry,
                "NOTES": notes,
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
