import Foundation
import SwiftyJSON
import SwiftOpenAI
struct DeleteTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = JSONSchema(
        type: .object,
        description: """
            Remove a skeleton timeline card by its unique identifier.
            Use this when user indicates a timeline entry is incorrect, irrelevant, or was created by mistake. The card is immediately removed from the timeline.
            RETURNS: { "success": true, "id": "<deleted-card-id>" }
            USAGE: Call when user requests removal of a specific timeline entry during timeline building or review phase. Common scenarios: duplicate entries, test data, positions user doesn't want to include.
            WORKFLOW: After deletion, the timeline is updated immediately. If you're in a review/validation cycle, the UI will reflect the removal.
            ERROR: Will fail if id doesn't match an existing timeline card.
            """,
        properties: [
            "id": TimelineCardSchema.id
        ],
        required: ["id"],
        additionalProperties: false
    )
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.deleteTimelineCard.rawValue }
    var description: String { "Remove timeline card by ID. Returns {success, id}. Use when user wants to remove an entry." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let id = params["id"].string, !id.isEmpty else {
            throw ToolError.invalidParameters("id must be provided")
        }
        // Delete timeline card via coordinator (which emits events)
        let result = await coordinator.deleteTimelineCard(id: id)
        return .immediate(result)
    }
}
