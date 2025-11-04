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
        guard let orderedIds = params["ordered_ids"].array?.compactMap({ $0.string }),
              !orderedIds.isEmpty else {
            throw ToolError.invalidParameters("ordered_ids must be a non-empty array of strings")
        }

        // Reorder timeline cards via coordinator (which emits events)
        let result = await service.coordinator.reorderTimelineCards(orderedIds: orderedIds)
        return .immediate(result)
    }
}
