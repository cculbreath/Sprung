//
//  StartPhaseTwoTool.swift
//  Sprung
//
//  Bootstrap tool for Phase 2 that returns timeline entries and provides
//  explicit instructions for generating the knowledge card plan.
//  Similar to agent_ready for Phase 1, this tool guides the LLM's first actions.
//
import Foundation
import SwiftyJSON

/// Bootstrap tool for Phase 2 that:
/// 1. Returns all timeline entries from Phase 1
/// 2. Provides explicit instructions for knowledge card generation
/// 3. Mandates calling open_document_collection next (via toolChoice chaining)
struct StartPhaseTwoTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Bootstrap tool for Phase 2. Call this FIRST after receiving Phase 2 instructions.
                RETURNS: Timeline entries from Phase 1 + explicit instructions for knowledge card generation.
                IMPORTANT: After receiving this tool's response, you MUST call open_document_collection.
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

    var name: String { OnboardingToolName.startPhaseTwo.rawValue }

    var description: String {
        "Bootstrap Phase 2. Returns timeline entries and instructions. MUST be followed by open_document_collection."
    }

    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Get timeline entries from Phase 1
        let timeline = await coordinator.state.artifacts.skeletonTimeline
        let entries = timeline?["experiences"].arrayValue ?? []

        var result = JSON()
        result["status"].string = "completed"
        result["timeline_entry_count"].int = entries.count
        result["timeline_entries"] = JSON(entries)

        // Include explicit instructions for next steps
        result["instructions"].string = buildInstructions(entryCount: entries.count)

        // Signal that this tool should be disabled after use
        result["disable_after_use"].bool = true

        // Signal the required next tool (used by ToolExecutionCoordinator for toolChoice chaining)
        result["next_required_tool"].string = OnboardingToolName.openDocumentCollection.rawValue

        return .immediate(result)
    }

    private func buildInstructions(entryCount: Int) -> String {
        """
        Phase 2 initialized.
        - \(entryCount) timeline entries from Phase 1

        ## WORKFLOW OVERVIEW

        ```
        STEP 1: open_document_collection     →  Show upload UI, collect supporting documents
        STEP 2: (optional) gap check         →  Ask about missing docs if significant gaps
        STEP 3: propose_card_assignments     →  Map uploaded docs to cards
        STEP 4: dispatch_kc_agents           →  Parallel agents generate cards
        STEP 5: submit_knowledge_card        →  Persist each returned card
        STEP 6: next_phase                   →  Advance to Phase 3
        ```

        ## STEP 1: Open Document Collection

        Call `open_document_collection` to show the document upload UI.

        Before calling, briefly describe in chat what knowledge cards you plan to create:
        - A card for each significant position in the timeline
        - Cards for cross-cutting competencies (Technical Leadership, etc.)

        Example chat message:
        "Based on your timeline, I'll create knowledge cards for:
        • Senior Engineer at Company X (2019-2022)
        • Tech Lead at StartupY (2022-2024)
        • Technical Leadership (cross-cutting)

        Please upload any supporting documents like performance reviews, project docs,
        or portfolio materials. When ready, click 'Done with Uploads'."

        The UI will show a dropzone for uploads. Wait for user to click "Done with Uploads".

        ## STEP 2: Optional Gap Check

        After user clicks "Done with Uploads", review what they uploaded vs. timeline positions.
        If significant gaps exist, ask about specific missing documents:

        "I notice we don't have any documents yet for your role at [Company] (2019-2022).
        Do you have any performance reviews, project documentation, or job descriptions from that time?"

        If coverage looks reasonable, or they say "that's all I have", proceed to step 3.

        ## STEP 3: Propose Card Assignments

        Call `propose_card_assignments` to:
        - Map uploaded artifact IDs to each card based on relevance
        - Identify cards with insufficient documentation (gaps)

        If gaps are found, describe SPECIFIC documents that would help:

        **For Senior Engineer at Acme (2019-2022):**
        - Performance reviews — most companies do annual reviews
        - Project documentation — design docs, architecture decisions

        **Commonly overlooked sources:**
        - Promotion announcement emails
        - LinkedIn recommendations (copy-paste)
        - Slack/Teams kudos messages

        **Document types by role category:**
        - Engineering: performance reviews, design docs, code repos, tech specs
        - Management: team reviews, org charts, budget docs, hiring plans
        - Sales/BD: quota attainment, deal lists, client testimonials

        ## STEP 4: Generate Knowledge Cards

        Call `dispatch_kc_agents` with the card proposals.
        - Parallel agents read full artifact text
        - Each agent generates a comprehensive 500-2000+ word knowledge card

        ## STEP 5: Persist Cards

        For EACH card in the returned array:
        - Review for quality and completeness
        - Call `submit_knowledge_card` to persist

        ## STEP 6: Complete Phase

        When all cards are persisted, call `next_phase` to advance to Phase 3.

        ---
        DO NOT skip open_document_collection. Users need to upload supporting docs first.
        """
    }
}
