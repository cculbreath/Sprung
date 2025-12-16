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
        if let pronouns = pronouns?.lowercased() {
            if pronouns.contains("he") {
                pronounGuide = "he/him/his (e.g., \"He led the team...\", \"His contributions...\")"
            } else if pronouns.contains("she") {
                pronounGuide = "she/her/hers (e.g., \"She led the team...\", \"Her contributions...\")"
            } else {
                pronounGuide = "they/them/their (e.g., \"They led the team...\", \"Their contributions...\")"
            }
        } else {
            pronounGuide = "they/them/their (e.g., \"They led the team...\", \"Their contributions...\")"
        }

        let nameRef = candidateName ?? "the candidate"

        return """
        You are a specialized Knowledge Card generation agent. Your task is to create a COMPREHENSIVE knowledge card titled "\(title)" (type: \(cardType)) for \(nameRef).

        ## Your Role
        You are one of several parallel agents, each responsible for generating a single knowledge card. You have access to document artifacts that contain source material for the card.

        **CRITICAL: You are a TRANSCRIBER, not a SUMMARIZER.**

        Your job is to TRANSFER information from source documents to the knowledge card, preserving ALL relevant detail:
        1. Read the FULL TEXT of all relevant artifacts assigned to this card
        2. Extract and PRESERVE all important information — do not summarize or compress
        3. Generate a detailed, comprehensive knowledge card

        ## Writing Style: Third Person with Pronouns

        Write in third person using \(pronounGuide).
        - ✅ "\(pronouns?.contains("she") == true ? "She" : pronouns?.contains("he") == true ? "He" : "They") developed a microservices architecture that reduced latency by 40%"
        - ✅ "\(pronouns?.contains("her") == true ? "Her" : pronouns?.contains("his") == true ? "His" : "Their") leadership of the 12-person team resulted in on-time delivery"
        - ❌ "I developed..." (first person)
        - ❌ "The candidate developed..." (impersonal)

        ## Available Tools
        - `get_artifact`: Retrieve the FULL TEXT content of an artifact by ID. ALWAYS use this for assigned artifacts.
        - `get_artifact_summary`: Get a quick summary of an artifact (only use for initial exploration of OTHER artifacts)
        - `return_result`: Submit your completed knowledge card

        ## Source Types
        You may receive two types of source material:
        1. **Artifacts**: Uploaded documents (resumes, performance reviews, etc.) - retrieve with `get_artifact`
        2. **Conversation Excerpts**: Direct quotes from the user provided in your initial prompt - use as-is

        When listing sources in your output, include BOTH artifact IDs and any conversation excerpts you used.

        ## CRITICAL: Verbatim Preservation Mandate

        The `prose` field must be a COMPREHENSIVE NARRATIVE of **500-2000+ words**. This prose will be the ONLY SOURCE for resume customization and cover letter writing — **the original documents will NOT be re-read at that time**.

        **Think of yourself as creating a detailed briefing document. EVERYTHING relevant must be captured.**

        If a document says:
        - "Led migration of 47 microservices over 8 months" → include those EXACT numbers
        - "Reduced deployment time from 4 hours to 15 minutes" → preserve the specific metrics
        - "Project Nexus" or "Operation Sunrise" → include the project names
        - Technical details about architecture → preserve them

        **What gets omitted is LOST FOREVER.** Err heavily on the side of inclusion.

        ## Prose Content Requirements

        **For Job Cards:**
        - Role scope, responsibilities, team size, reporting structure
        - EVERY specific project mentioned, with technical details and contributions
        - ALL quantified achievements (revenue, users, efficiency, cost savings)
        - Technologies, tools, frameworks, and methodologies used
        - Team dynamics, leadership responsibilities, collaboration patterns
        - Challenges overcome and complex problems solved
        - Skills demonstrated (technical and interpersonal)
        - Career progression or growth during the tenure
        - Timeline details (start/end dates, project durations)

        **For Skill Cards:**
        - How the skill was developed and refined over time
        - EVERY project or context where the skill was applied
        - Proficiency level with concrete evidence
        - Related technologies or complementary skills
        - ALL notable outcomes achieved using this skill
        - Certifications, training, or formal recognition

        ## DO NOT:
        - ❌ Summarize or compress — PRESERVE all relevant detail
        - ❌ Write terse bullet-point lists — write flowing narrative prose
        - ❌ Omit specific details like project names, metrics, or technologies
        - ❌ Use generic descriptions — be specific to THIS role/skill
        - ❌ Add information not in the source documents

        ## Knowledge Card Structure
        Your output must include:
        - **prose**: COMPREHENSIVE narrative (500-2000+ words). This is the most important field.
        - **highlights**: 5-8 bullet points of standout achievements (specific, with metrics)
        - **skills**: Technical skills, tools, or competencies demonstrated
        - **metrics**: ALL quantifiable achievements (percentages, numbers, dollars, team sizes, timelines)
        - **sources**: List of artifact IDs you used

        ## Output Format
        When ready, call `return_result` with your card wrapped in a `result` object:
        ```json
        {
          "result": {
            "card_type": "\(cardType)",
            "title": "\(title)",
            "prose": "Comprehensive 500-2000+ word narrative...",
            "highlights": ["Specific achievement with metrics", "Another specific achievement"],
            "skills": ["Skill 1", "Skill 2"],
            "metrics": ["Increased revenue by 40%", "Led team of 12", "Shipped in 6 months"],
            "sources": ["artifact-id-1", "artifact-id-2"],
            "chat_sources": [
              {"excerpt": "I led the migration project...", "context": "User describing project leadership"}
            ]
          }
        }
        ```
        Note: `chat_sources` is optional - only include if conversation excerpts were provided and used.

        ## Quality Check Before Submitting
        Before calling return_result, verify:
        1. Prose is at least 500 words (aim for 1000+ for substantial roles)
        2. ALL specific projects, metrics, and technologies from source docs are included
        3. No information from the source documents was omitted or summarized away
        4. The narrative could stand alone to write a resume bullet or cover letter paragraph
        """
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

        // Build the initial prompt
        var prompt = """
        ## Card Assignment

        **Card Type**: \(proposal.cardType)
        **Title**: \(proposal.title)
        """

        if let timelineEntryId = proposal.timelineEntryId {
            prompt += "\n**Timeline Entry**: \(timelineEntryId)"
        }

        if let notes = proposal.notes {
            prompt += "\n**Notes**: \(notes)"
        }

        prompt += """


        ## Assigned Artifacts (Full Summaries)
        These artifacts have been specifically assigned to this card. Read them thoroughly using `get_artifact`.
        \(assignedSummaries.isEmpty ? "\n(No specific artifacts assigned - review available artifacts below)" : assignedSummaries)
        \(chatExcerptsSection)
        ## Other Available Artifacts
        Brief descriptions only. Use `get_artifact` if you need more detail from any of these.
        \(otherArtifactsList.isEmpty ? "\n(No other artifacts available)" : otherArtifactsList)

        ## Instructions
        1. Start by reading the full content of your assigned artifacts using `get_artifact`
        2. If assigned artifacts are insufficient, review other artifacts that might be relevant
        3. \(proposal.chatExcerpts.isEmpty ? "" : "Incorporate information from the conversation excerpts above\n        4. ")Synthesize the information into a cohesive knowledge card
        \(proposal.chatExcerpts.isEmpty ? "4" : "5"). Call `return_result` with your completed card

        Begin by reading your assigned artifacts.
        """

        return prompt
    }

    // MARK: - Error Recovery Prompt

    /// Prompt sent when an agent encounters an error and needs to retry.
    static func errorRecoveryPrompt(error: String) -> String {
        """
        An error occurred: \(error)

        Please try a different approach:
        1. If you couldn't read an artifact, try the summary instead
        2. If no artifacts are available, create the card based on the title and any context provided
        3. Call `return_result` with whatever information you can provide

        Continue with your card generation.
        """
    }

    // MARK: - Skill Card Specific

    /// Additional guidance for skill-type cards.
    static func skillCardGuidance(skillName: String) -> String {
        """
        ## Skill Card Guidance

        For skill "\(skillName)", focus on:
        - **Proficiency level**: beginner, intermediate, advanced, expert
        - **Years of experience** with this skill
        - **Projects or contexts** where this skill was applied
        - **Related technologies** or complementary skills
        - **Certifications or training** related to this skill
        - **Notable outcomes** achieved using this skill

        The prose should explain how the applicant developed and applied this skill, with specific examples.
        """
    }

    // MARK: - Job Card Specific

    /// Additional guidance for job-type cards.
    static func jobCardGuidance(jobTitle: String, company: String?) -> String {
        var guidance = """
        ## Job Card Guidance

        For the "\(jobTitle)" role
        """

        if let company = company {
            guidance += " at \(company)"
        }

        guidance += """
        , focus on:
        - **Key responsibilities** and scope of the role
        - **Team size and structure** (reports, peers, leadership)
        - **Major projects or initiatives** led or contributed to
        - **Measurable impact** (revenue, efficiency, user growth, etc.)
        - **Technologies and methodologies** used
        - **Career progression** or promotions during the tenure

        The prose should read like a compelling story of the applicant's time in this role, emphasizing growth and impact.
        """

        return guidance
    }
}
