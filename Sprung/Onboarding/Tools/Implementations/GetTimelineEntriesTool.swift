import Foundation
import SwiftyJSON

struct GetTimelineEntriesTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Retrieve the skeleton timeline entries (positions, education, etc.) from Phase 1.
                Use this in Phase 2 to iterate over each entry and generate Knowledge Cards.
                RETURNS: { "count": <number>, "entries": [{ timeline entry objects }] }
                Each entry contains: id, title/role, organization/company, location, start, end, type
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

    var name: String { OnboardingToolName.getTimelineEntries.rawValue }
    var description: String { "Get all timeline entries from Phase 1 skeleton timeline. Use to iterate and generate Knowledge Cards for each position." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let timeline = await coordinator.state.artifacts.skeletonTimeline

        guard let timeline = timeline else {
            var response = JSON()
            response["status"].string = "completed"
            response["count"].int = 0
            response["entries"] = JSON([])
            response["message"].string = "No skeleton timeline available. Complete Phase 1 first."
            return .immediate(response)
        }

        let entries = timeline["experiences"].arrayValue
        var response = JSON()
        response["status"].string = "completed"
        response["count"].int = entries.count
        response["entries"] = JSON(entries)

        if entries.isEmpty {
            response["message"].string = "Timeline exists but has no entries."
        }

        return .immediate(response)
    }
}
