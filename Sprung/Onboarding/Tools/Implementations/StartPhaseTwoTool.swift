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
/// 2. Provides explicit instructions to generate a knowledge card plan
/// 3. Mandates calling display_knowledge_card_plan next (via toolChoice chaining)
struct StartPhaseTwoTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Bootstrap tool for Phase 2. Call this FIRST after receiving Phase 2 instructions.
                RETURNS: Timeline entries from Phase 1 + explicit instructions for knowledge card generation.
                IMPORTANT: After receiving this tool's response, you MUST call display_knowledge_card_plan.
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
        "Bootstrap Phase 2. Returns timeline entries and instructions. MUST be followed by display_knowledge_card_plan."
    }

    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Get timeline entries from Phase 1
        let timeline = await coordinator.state.artifacts.skeletonTimeline
        let entries = timeline?["experiences"].arrayValue ?? []

        // Get artifact summaries (lightweight view of all uploaded docs)
        let artifactSummaries = await coordinator.listArtifactSummaries()

        var result = JSON()
        result["status"].string = "completed"
        result["timeline_entry_count"].int = entries.count
        result["timeline_entries"] = JSON(entries)

        // Include artifact summaries for doc-to-card mapping
        result["artifact_count"].int = artifactSummaries.count
        result["artifact_summaries"] = JSON(artifactSummaries)

        // Include explicit instructions for next steps
        result["instructions"].string = buildInstructions(
            entryCount: entries.count,
            artifactCount: artifactSummaries.count
        )

        // Signal that this tool should be disabled after use
        result["disable_after_use"].bool = true

        // Signal the required next tool (used by ToolExecutionCoordinator for toolChoice chaining)
        result["next_required_tool"].string = OnboardingToolName.displayKnowledgeCardPlan.rawValue

        return .immediate(result)
    }

    private func buildInstructions(entryCount: Int, artifactCount: Int) -> String {
        """
        Phase 2 initialized.
        - \(entryCount) timeline entries from Phase 1
        - \(artifactCount) artifact(s) with summaries available

        ## WORKFLOW OVERVIEW

        ```
        STEP 1: display_knowledge_card_plan  →  Show plan to user
        STEP 2: propose_card_assignments     →  Map docs to cards, identify gaps
        STEP 3: GAPS ASSESSMENT (CRITICAL)   →  Ask for specific missing docs, WAIT for user
        STEP 4: dispatch_kc_agents           →  Parallel agents generate cards
        STEP 5: submit_knowledge_card        →  Persist each returned card
        STEP 6: next_phase                   →  Advance to Phase 3
        ```

        ## STEP 1: Display Knowledge Card Plan

        Call `display_knowledge_card_plan` with:
        - A "job" card for each significant position in the timeline
        - "skill" cards for cross-cutting competencies (Technical Leadership, etc.)

        Example:
        ```json
        {
          "items": [
            {"id": "uuid1", "type": "job", "title": "Senior Engineer at Company X", "status": "pending"},
            {"id": "uuid2", "type": "skill", "title": "Technical Leadership", "status": "pending"}
          ],
          "message": "I've created a plan to document your career."
        }
        ```

        ## STEP 2: Propose Card Assignments

        Call `propose_card_assignments` to:
        - Map artifact IDs to each card based on relevance
        - Identify cards with insufficient documentation (gaps)

        ## STEP 3: GAPS ASSESSMENT (CRITICAL - DO NOT SKIP)

        ⚠️ This step is MANDATORY if any gaps were identified.

        **You MUST present SPECIFIC document requests to the user.** Generic requests are not acceptable.

        ❌ WRONG: "Do you have any other documents I should look at?"
        ❌ WRONG: "Is there anything else you'd like to add?"

        ✅ RIGHT: Present a structured gaps summary like this:

        "Looking at your timeline, I've identified some documentation gaps that would really strengthen your knowledge cards:

        **For Senior Engineer at Acme (2019-2022):**
        - Performance reviews — most companies do annual reviews, even informal email summaries help
        - Project documentation — design docs, architecture decisions, post-mortems you authored
        - The job description — often saved in offer letters or HR portals

        **For Tech Lead at StartupX (2022-2024):**
        - Team feedback or 360 reviews
        - Any presentations or demos you delivered

        **Commonly overlooked sources:**
        - Promotion announcement emails
        - LinkedIn recommendations (can copy-paste)
        - Slack/Teams kudos or thank-you messages
        - Award certificates or recognition emails

        Do you have any of these available? Or should we proceed with what we have?"

        **Document types by role category:**
        - Engineering: performance reviews, design docs, code repos, tech specs, PR histories
        - Management: team reviews, org charts, budget docs, hiring plans, 1:1 notes
        - Sales/BD: quota attainment, deal lists, client testimonials, pipeline reports
        - Product/Design: specs, user research, wireframes, A/B results, roadmaps

        **WAIT for user response** before proceeding to Step 4. Do not call dispatch_kc_agents until:
        - User uploads additional documents, OR
        - User confirms they have no more documents

        ## STEP 4: Generate Knowledge Cards

        Call `dispatch_kc_agents` with the card proposals from Step 2.
        - Parallel agents read full artifact text
        - Each agent generates a comprehensive 500-2000+ word knowledge card
        - Results return as an array

        ## STEP 5: Persist Cards

        For EACH card in the returned array:
        - Review for quality and completeness
        - Call `submit_knowledge_card` to persist

        ## STEP 6: Complete Phase

        When all cards are persisted, call `next_phase` to advance to Phase 3.

        ---
        DO NOT skip display_knowledge_card_plan. The UI must show the plan.
        DO NOT skip gaps assessment if propose_card_assignments returns gaps.
        """
    }
}
