import Foundation
import SwiftyJSON
import SwiftOpenAI

struct UpdateTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Update an existing timeline card with partial field changes (PATCH semantics).
                Only include fields you want to change - omitted fields remain unchanged. Use this to correct errors or add missing information to existing cards.
                RETURNS: { "success": true, "id": "<card-id>" }
                USAGE: Call when user provides corrections or additional details for an existing timeline entry. The UI will reflect changes immediately.
                DO NOT: Include summary or highlights in Phase 1 - skeleton cards contain only basic facts.
                """,
            properties: [
                "id": JSONSchema(
                    type: .string,
                    description: "Unique identifier of the timeline card to update"
                ),
                "fields": TimelineCardSchema.fieldsSchema(required: [])  // No required fields for PATCH
            ],
            required: ["id", "fields"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.updateTimelineCard.rawValue }
    var description: String { "Update existing timeline card with partial changes (PATCH). Returns {success, id}. Only include changed fields." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let id = params["id"].string, !id.isEmpty else {
            throw ToolError.invalidParameters("id must be provided")
        }
        guard let fields = params["fields"].dictionary else {
            throw ToolError.invalidParameters("fields must be provided")
        }
        // Normalize fields for Phase 1 skeleton timeline constraints (don't override experience_type on update)
        let normalizedFields = TimelineCardSchema.normalizePhaseOneFields(JSON(fields), includeExperienceType: false)
        // Update timeline card via coordinator (which emits events)
        let result = await coordinator.updateTimelineCard(id: id, fields: normalizedFields)
        return .immediate(result)
    }
}
