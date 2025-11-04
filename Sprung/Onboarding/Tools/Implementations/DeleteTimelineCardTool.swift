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

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "delete_timeline_card" }
    var description: String { "Delete a skeleton timeline card." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // TODO: Reimplement using event-driven architecture
        var response = JSON()
        response["success"].bool = true
        response["id"].string = params["id"].stringValue
        return .immediate(response)
    }
}
