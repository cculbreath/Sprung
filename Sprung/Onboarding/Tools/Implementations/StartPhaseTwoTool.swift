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
        - \(entryCount) timeline entries
        - \(artifactCount) artifact(s) with summaries

        ## YOUR WORKFLOW

        ### STEP 1: Display Knowledge Card Plan
        Call `display_knowledge_card_plan` with a plan containing:
        - A "job" type card for each significant position in the timeline
        - "skill" type cards for cross-cutting competencies you identify

        Example:
        {
          "items": [
            {"id": "uuid1", "type": "job", "title": "Senior Engineer at Company X", "status": "pending"},
            {"id": "uuid2", "type": "skill", "title": "Technical Leadership", "status": "pending"}
          ],
          "message": "I've created a plan to document your career."
        }

        ### STEP 2: Propose Card Assignments
        After displaying the plan:
        - Review the artifact summaries provided above
        - For each card, identify which artifacts contain relevant information
        - Call `propose_card_assignments` to map artifacts to cards:
          - Assign relevant artifact IDs to each card
          - Identify documentation gaps (cards without sufficient artifacts)

        ### STEP 3: Handle Gaps (if any)
        If there are documentation gaps:
        - Present the gaps to the user
        - Ask if they have additional documents (performance reviews, project docs, etc.)
        - Wait for user uploads or confirmation they have no more docs

        ### STEP 4: Generate Knowledge Cards
        When artifact assignments are ready:
        - Call `dispatch_kc_agents` with the card proposals
        - Parallel agents will read artifacts and generate knowledge cards
        - Review returned cards for quality
        - Use `submit_knowledge_card` to persist valid cards

        ## KEY POINTS
        - Artifact summaries let you see all docs WITHOUT reading full text
        - Sub-agents handle the detailed artifact reading and card generation
        - After cards are generated and persisted, call `next_phase` to advance

        DO NOT skip calling display_knowledge_card_plan. This is required to show the UI.
        """
    }
}
