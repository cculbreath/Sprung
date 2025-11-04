import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ReorderTimelineCardsTool: InterviewTool {
    private static let schema: JSONSchema = JSONSchema(
        type: .object,
        description: "Reorder existing skeleton timeline cards by supplying their identifiers in the desired order.",
        properties: [
            "ordered_ids": JSONSchema(
                type: .array,
                description: "Identifiers of existing cards in desired order.",
                items: JSONSchema(type: .string)
            )
        ],
        required: ["ordered_ids"],
        additionalProperties: false
    )

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "reorder_timeline_cards" }
    var description: String { "Reorder skeleton timeline cards using an ordered list of ids." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // TODO: Reimplement using event-driven architecture
        var response = JSON()
        response["success"] = true
        return .immediate(response)
    }
}
