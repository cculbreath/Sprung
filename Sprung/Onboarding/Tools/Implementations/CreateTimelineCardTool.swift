import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CreateTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Create a skeleton timeline card for a position, role, or educational experience.
                Phase 1 cards capture only basic timeline facts - title, organization, dates, and location. Summary and highlights are added in later phases.
                RETURNS: { "success": true, "id": "<card-id>" }
                USAGE: Call after gathering position details via chat or artifact extraction. Cards are displayed in the timeline editor UI where users can review and edit them.
                DO NOT: Generate descriptions or bullet points in Phase 1 - defer to Phase 2 deep dive.
                """,
            properties: ["fields": TimelineCardSchema.fieldsSchema(required: ["title", "organization", "start"])],
            required: ["fields"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.createTimelineCard.rawValue }
    var description: String { "Create skeleton timeline card with basic facts (title, org, dates, location). Returns {success, id}. Phase 1 only - no descriptions." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let fields = params["fields"].dictionary else {
            throw ToolError.invalidParameters("fields must be provided")
        }
        // Normalize fields for Phase 1 skeleton timeline constraints
        let normalizedFields = TimelineCardSchema.normalizePhaseOneFields(JSON(fields), includeExperienceType: true)
        // Create timeline card via coordinator (which emits events)
        let result = await coordinator.createTimelineCard(fields: normalizedFields)
        return .immediate(result)
    }
}
