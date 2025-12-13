import Foundation
import SwiftyJSON
import SwiftOpenAI
struct ReorderTimelineCardsTool: InterviewTool {
    private static let schema: JSONSchema = JSONSchema(
        type: .object,
        description: """
            Reorder existing skeleton timeline cards by supplying a complete list of card identifiers in the desired new order.
            CRITICAL: You MUST provide ALL existing timeline card IDs in the ordered_ids array. Any cards omitted from the list will be PERMANENTLY REMOVED from the timeline. This is a complete replacement operation, not a partial reorder.
            Use this when user wants to change the chronological order of timeline entries (e.g., sorting by date, grouping education separately, prioritizing certain roles).
            RETURNS: { "success": true, "count": <number-of-cards> }
            USAGE: First, retrieve all current card IDs (via display_timeline_entries_for_review or by tracking create_timeline_card responses). Then, reorder the complete list and call this tool with ALL IDs in the new order.
            WORKFLOW:
            1. User requests reordering (e.g., "sort by date" or "move my current job to the top")
            2. Get all current timeline card IDs
            3. Reorder the complete ID list according to user's preference
            4. Call reorder_timeline_cards with ALL IDs in new order
            5. Timeline updates immediately to reflect new order
            ERROR: Will fail if ordered_ids is empty. Cards with IDs not in the list will be silently dropped.
            DO NOT: Provide a partial list thinking other cards will stay in place - they will be removed.
            """,
        properties: [
            "ordered_ids": TimelineCardSchema.orderedIds
        ],
        required: ["ordered_ids"],
        additionalProperties: false
    )
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.reorderTimelineCards.rawValue }
    var description: String { "Reorder timeline cards. CRITICAL: Must include ALL card IDs - omitted cards are removed. Returns {success, count}." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let orderedIds = params["ordered_ids"].array?.compactMap({ $0.string }),
              !orderedIds.isEmpty else {
            throw ToolError.invalidParameters("ordered_ids must be a non-empty array of strings")
        }
        // Reorder timeline cards via coordinator (which emits events)
        let result = await coordinator.reorderTimelineCards(orderedIds: orderedIds)
        return .immediate(result)
    }
}
