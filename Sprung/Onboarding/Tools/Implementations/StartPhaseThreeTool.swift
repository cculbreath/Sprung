//
//  StartPhaseThreeTool.swift
//  Sprung
//
//  Bootstrap tool for Phase 3 that returns knowledge cards and dossier context,
//  providing explicit instructions for writing sample collection and dossier finalization.
//
import Foundation
import SwiftyJSON

/// Bootstrap tool for Phase 3 that:
/// 1. Returns all confirmed knowledge cards from Phase 2
/// 2. Returns applicant profile and timeline summary
/// 3. Provides explicit instructions for writing corpus collection
struct StartPhaseThreeTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Bootstrap tool for Phase 3. Call this FIRST after receiving Phase 3 instructions.
                RETURNS: Knowledge cards from Phase 2, applicant profile, and instructions for writing corpus collection.
                After receiving this tool's response, begin collecting writing samples and finalizing the dossier.
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.startPhaseThree.rawValue }

    var description: String {
        "Bootstrap Phase 3. Returns knowledge cards, profile, and instructions for writing sample collection."
    }

    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Get knowledge cards from Phase 2
        let knowledgeCards = await coordinator.state.artifacts.knowledgeCards
        let cardCount = knowledgeCards.count

        // Get applicant profile
        let profile = await coordinator.state.artifacts.applicantProfile

        // Get timeline summary
        let timeline = await coordinator.state.artifacts.skeletonTimeline
        let timelineCount = timeline?["experiences"].arrayValue.count ?? 0

        // Build card summaries for context
        var cardSummaries: [JSON] = []
        for card in knowledgeCards {
            var summary = JSON()
            summary["id"].string = card["id"].stringValue
            summary["title"].string = card["title"].stringValue
            summary["type"].string = card["type"].stringValue
            summary["organization"].string = card["organization"].stringValue
            summary["time_period"].string = card["time_period"].stringValue
            // Include word count for reference
            let wordCount = card["content"].stringValue.split(separator: " ").count
            summary["word_count"].int = wordCount
            cardSummaries.append(summary)
        }

        var result = JSON()
        result["status"].string = "completed"
        result["knowledge_card_count"].int = cardCount
        result["knowledge_card_summaries"] = JSON(cardSummaries)
        result["timeline_entry_count"].int = timelineCount

        // Include profile name for personalization
        if let name = profile?["name"].string {
            result["applicant_name"].string = name
        }

        // Include explicit instructions for Phase 3
        result["instructions"].string = buildInstructions(
            cardCount: cardCount,
            applicantName: profile?["name"].string ?? "the applicant"
        )

        // Signal that this tool should be disabled after use
        result["disable_after_use"].bool = true

        return .immediate(result)
    }

    private func buildInstructions(cardCount: Int, applicantName: String) -> String {
        """
        Phase 3 initialized. You have \(cardCount) confirmed knowledge cards from Phase 2.

        PHASE 3 GOALS:
        This phase focuses on KNOWLEDGE GATHERING for the writing corpus and dossier:
        1. Collect writing samples (cover letters, emails, proposals, etc.)
        2. Analyze writing style (if user consents)
        3. Compile and validate the candidate dossier

        IMPORTANT REMINDERS:
        - This is still KNOWLEDGE GATHERING, not resume/cover letter creation
        - Resume generation happens LATER, after the interview is complete
        - Focus on collecting raw materials and understanding \(applicantName)'s voice

        WORKFLOW:
        1. Ask what type of writing sample they can provide
        2. Use `get_user_upload` to collect samples
        3. If consented, analyze writing style (tone, structure, vocabulary)
        4. Use `persist_data` to save the writing sample and style notes
        5. Compile the dossier by referencing all Phase 1-3 artifacts
        6. Use `submit_for_validation` for final dossier review
        7. Mark objectives complete and call `next_phase` to finish

        AVAILABLE DATA:
        - \(cardCount) knowledge cards covering jobs and skills
        - Validated applicant profile
        - Skeleton timeline from Phase 1
        - All uploaded artifacts (PDFs, git repos, etc.)

        DO NOT:
        - Offer to write resumes or cover letters now
        - Skip the writing sample collection
        - Rush through dossier validation
        """
    }
}
