import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CreateTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            properties: ["fields": TimelineCardSchema.fieldsSchema(required: ["title", "organization", "start"])],
            required: ["fields"],
            additionalProperties: false
        )
    }()

    private weak var coordinator: OnboardingInterviewCoordinator?

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.createTimelineCard.rawValue }
    var description: String {
        """
        Create skeleton timeline card for a position, role, or education. \
        REQUIRED: fields object with title, organization, start. \
        Optional: experienceType (work|education|volunteer|project), location, end, url. \
        Example: { "fields": { "experienceType": "work", "title": "Engineer", "organization": "Acme", "start": "2020", "end": "2023" } }. \
        RETURNS: { "success": true, "id": "<card-id>" }. \
        DO NOT generate descriptions/bullets - only skeleton facts.
        """
    }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        // Decode at the boundary: Use JSONDecoder for type-safe parsing
        guard let fieldsDict = params["fields"].dictionary else {
            throw ToolError.invalidParameters("fields is required and must be an object")
        }

        // Convert SwiftyJSON dictionary to Data for decoding
        let fieldsData = try JSONSerialization.data(withJSONObject: fieldsDict.mapValues { $0.object })
        let decoder = JSONDecoder()

        // Decode to typed struct
        let input: CreateTimelineCardInput
        do {
            input = try decoder.decode(CreateTimelineCardInput.self, from: fieldsData)
        } catch {
            throw ToolError.invalidParameters("Invalid fields format: \(error.localizedDescription)")
        }

        // Validate required fields using typed properties
        guard !input.title.isEmpty else {
            throw ToolError.invalidParameters("Card title is required for new timeline cards")
        }
        guard !input.organization.isEmpty else {
            throw ToolError.invalidParameters("Organization name is required for new timeline cards")
        }
        guard !input.start.isEmpty else {
            throw ToolError.invalidParameters("Start date is required for new timeline cards (e.g., 'January 2020', 'March 2019', '2018')")
        }

        // Build normalized fields JSON for service layer
        var normalizedFields = JSON()
        normalizedFields["experienceType"].string = input.experienceType?.rawValue ?? "work"
        normalizedFields["title"].string = input.title
        normalizedFields["organization"].string = input.organization
        if let location = input.location {
            normalizedFields["location"].string = location
        }
        normalizedFields["start"].string = input.start
        if let end = input.end {
            normalizedFields["end"].string = end
        }
        if let url = input.url {
            normalizedFields["url"].string = url
        }

        // Create timeline card via timeline service (which emits events)
        let result = await coordinator.timeline.createTimelineCard(fields: normalizedFields)

        // Signal UI to auto-switch to Timeline tab
        await MainActor.run {
            coordinator.ui.timelineToolWasUsed = true
        }

        return .immediate(result)
    }
}
