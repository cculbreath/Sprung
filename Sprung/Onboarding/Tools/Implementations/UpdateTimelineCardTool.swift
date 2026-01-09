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
                "id": TimelineCardSchema.id,
                "fields": TimelineCardSchema.fieldsSchema(required: [])  // No required fields for PATCH
            ],
            required: ["id", "fields"],
            additionalProperties: false
        )
    }()

    private weak var coordinator: OnboardingInterviewCoordinator?

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.updateTimelineCard.rawValue }
    var description: String { "Update existing timeline card with partial changes (PATCH). Returns {success, id}. Only include changed fields." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        // Validate card ID
        let id = try ToolResultHelpers.requireString(params["id"].string, named: "id")

        // Decode at the boundary: Use JSONDecoder for type-safe parsing
        guard let fieldsDict = params["fields"].dictionary else {
            throw ToolError.invalidParameters("fields is required and must be an object")
        }

        // Convert SwiftyJSON dictionary to Data for decoding
        let fieldsData = try JSONSerialization.data(withJSONObject: fieldsDict.mapValues { $0.object })
        let decoder = JSONDecoder()

        // Decode to typed struct (all fields optional for PATCH semantics)
        let input: UpdateTimelineCardInput
        do {
            input = try decoder.decode(UpdateTimelineCardInput.self, from: fieldsData)
        } catch {
            throw ToolError.invalidParameters("Invalid fields format: \(error.localizedDescription)")
        }

        // Validate that at least one field is provided for update
        let hasAtLeastOneField = input.experienceType != nil ||
                                  input.title != nil ||
                                  input.organization != nil ||
                                  input.location != nil ||
                                  input.start != nil ||
                                  input.end != nil ||
                                  input.url != nil

        guard hasAtLeastOneField else {
            throw ToolError.invalidParameters("At least one field must be provided for updates")
        }

        // Build normalized fields JSON for service layer
        // Phase 1: Don't override experienceType on update
        var normalizedFields = JSON()
        if let title = input.title {
            normalizedFields["title"].string = title
        }
        if let organization = input.organization {
            normalizedFields["organization"].string = organization
        }
        if let location = input.location {
            normalizedFields["location"].string = location
        }
        if let start = input.start {
            normalizedFields["start"].string = start
        }
        if let end = input.end {
            normalizedFields["end"].string = end
        }
        if let url = input.url {
            normalizedFields["url"].string = url
        }

        // Update timeline card via coordinator (which emits events)
        let result = await coordinator.timeline.updateTimelineCard(id: id, fields: normalizedFields)
        return .immediate(result)
    }
}
