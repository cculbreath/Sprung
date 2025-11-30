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

        var result = JSON()
        result["status"].string = "completed"
        result["timeline_entry_count"].int = entries.count
        result["timeline_entries"] = JSON(entries)

        // Include explicit instructions for next steps
        result["instructions"].string = buildInstructions(entryCount: entries.count)

        // Signal that this tool should be disabled after use
        result["disable_after_use"].bool = true

        // Signal the required next tool (used by ToolExecutionCoordinator for toolChoice chaining)
        result["next_required_tool"].string = OnboardingToolName.displayKnowledgeCardPlan.rawValue

        return .immediate(result)
    }

    private func buildInstructions(entryCount: Int) -> String {
        """
        Phase 2 initialized. You have \(entryCount) timeline entries to process.

        YOUR IMMEDIATE NEXT ACTION:
        Call `display_knowledge_card_plan` with a plan containing:
        1. A "job" type card for each significant position in the timeline
        2. "skill" type cards for cross-cutting competencies you identify

        EXAMPLE PLAN STRUCTURE:
        {
          "items": [
            {"id": "uuid1", "type": "job", "title": "Senior Engineer at Company X", "status": "pending"},
            {"id": "uuid2", "type": "job", "title": "Developer at Startup Y", "status": "pending"},
            {"id": "uuid3", "type": "skill", "title": "Technical Leadership", "status": "pending"},
            {"id": "uuid4", "type": "skill", "title": "Full-Stack Development", "status": "pending"}
          ],
          "message": "I've created a plan to document your career. Let's start with your most recent role."
        }

        RULES:
        - Generate the plan based on the timeline entries provided above
        - Use UUIDs for item IDs
        - Set all initial statuses to "pending"
        - Include a helpful message explaining the plan to the user
        - After displaying the plan, begin working through items systematically
        - For each item: mark in_progress → collect documents → generate card → mark complete

        DO NOT skip calling display_knowledge_card_plan. This is required to show the UI.
        """
    }
}
