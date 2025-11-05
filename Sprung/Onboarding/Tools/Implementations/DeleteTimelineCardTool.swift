import Foundation
import SwiftyJSON
import SwiftOpenAI

struct DeleteTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = JSONSchema(
        type: .object,
        description: "Remove a skeleton timeline card by identifier.",
        properties: [
            "id": JSONSchema(type: .string, description: "Identifier of the card to delete.")
        ],
        required: ["id"],
        additionalProperties: false
    )

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "delete_timeline_card" }
    var description: String { "Delete a skeleton timeline card." }
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
