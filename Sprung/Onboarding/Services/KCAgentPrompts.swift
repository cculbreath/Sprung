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
    /// Defines the agent's role, available tools, and output format.
    /// - Parameters:
    ///   - cardType: "job" or "skill"
    ///   - title: Card title (e.g., "Senior Engineer at Company X")
    ///   - candidateName: The candidate's first name for prose references
    ///   - pronouns: Pronouns to use (e.g., "he/him", "she/her", "they/them")
    static func systemPrompt(
        cardType: String,
        title: String,
        candidateName: String? = nil,
        pronouns: String? = nil
    ) -> String {
        // Determine pronoun usage
        let pronounGuide: String
        let pronounExample1: String
        let pronounExample2: String

        if let pronouns = pronouns?.lowercased() {
            if pronouns.contains("he") {
                pronounGuide = "he/him/his (e.g., \"He led the team...\", \"His contributions...\")"
                pronounExample1 = "He"
                pronounExample2 = "His"
            } else if pronouns.contains("she") {
                pronounGuide = "she/her/hers (e.g., \"She led the team...\", \"Her contributions...\")"
                pronounExample1 = "She"
                pronounExample2 = "Her"
            } else {
                pronounGuide = "they/them/their (e.g., \"They led the team...\", \"Their contributions...\")"
                pronounExample1 = "They"
                pronounExample2 = "Their"
            }
        } else {
            pronounGuide = "they/them/their (e.g., \"They led the team...\", \"Their contributions...\")"
            pronounExample1 = "They"
            pronounExample2 = "Their"
        }

        let nameRef = candidateName ?? "the candidate"

        return PromptLibrary.substitute(
            template: PromptLibrary.kcAgentSystemPromptTemplate,
            replacements: [
                "TITLE": title,
                "CARD_TYPE": cardType,
                "NAME_REF": nameRef,
                "PRONOUN_GUIDE": pronounGuide,
                "PRONOUN_EXAMPLE_1": pronounExample1,
                "PRONOUN_EXAMPLE_2": pronounExample2
            ]
        )
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
}
