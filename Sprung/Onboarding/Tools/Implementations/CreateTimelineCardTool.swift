import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CreateTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = {
        let fieldsSchema = JSONSchema(
            type: .object,
            description: "Timeline card fields (title, organization, location, start, end, summary, highlights).",
            additionalProperties: true
        )

        return JSONSchema(
            type: .object,
            description: "Create a new skeleton timeline card.",
            properties: ["fields": fieldsSchema],
            required: ["fields"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "create_timeline_card" }
    var description: String { "Append a new skeleton timeline card with the supplied fields." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let fields = params["fields"].dictionary else {
            throw ToolError.invalidParameters("fields must be provided")
        }

        // Create timeline card via coordinator (which emits events)
        let result = await coordinator.createTimelineCard(fields: JSON(fields))
        return .immediate(result)
    }
}
