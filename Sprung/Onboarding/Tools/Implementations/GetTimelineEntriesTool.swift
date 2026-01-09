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

    private weak var coordinator: OnboardingInterviewCoordinator?

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.getTimelineEntries.rawValue }
    var description: String { "Get all timeline entries from Phase 1 skeleton timeline. Use to iterate and generate Knowledge Cards for each position." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        let timeline = await coordinator.state.artifacts.skeletonTimeline

        guard let timeline = timeline else {
            return ToolResultHelpers.statusResponse(
                status: "completed",
                message: "No skeleton timeline available. Complete Phase 1 first.",
                additionalData: JSON(["count": 0, "entries": []])
            )
        }

        let entries = timeline["experiences"].arrayValue

        var additionalData = JSON()
        additionalData["count"].int = entries.count
        additionalData["entries"] = JSON(entries)

        if entries.isEmpty {
            return ToolResultHelpers.statusResponse(
                status: "completed",
                message: "Timeline exists but has no entries.",
                additionalData: additionalData
            )
        }

        return ToolResultHelpers.statusResponse(
            status: "completed",
            additionalData: additionalData
        )
    }
}
