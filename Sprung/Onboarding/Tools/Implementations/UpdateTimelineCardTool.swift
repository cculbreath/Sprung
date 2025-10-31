import Foundation
import SwiftyJSON
import SwiftOpenAI

struct UpdateTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = {
        let fieldsSchema = JSONSchema(
            type: .object,
            description: "Fields to update on the existing timeline card.",
            additionalProperties: true
        )

        return JSONSchema(
            type: .object,
            description: "Update an existing skeleton timeline card.",
            properties: [
                "id": JSONSchema(type: .string, description: "Identifier of the card to update."),
                "fields": fieldsSchema
            ],
            required: ["id", "fields"],
            additionalProperties: false
        )
    }()

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "update_timeline_card" }
    var description: String { "Modify fields on an existing skeleton timeline card." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let identifier = params["id"].string, !identifier.isEmpty else {
            throw ToolError.invalidParameters("id must be a non-empty string")
        }

        guard params["fields"] != .null else {
            throw ToolError.invalidParameters("fields must be provided as an object")
        }

        do {
            let response = try await service.updateTimelineCard(id: identifier, fields: params["fields"])
            return .immediate(response)
        } catch let error as TimelineCardError {
            return .error(.executionFailed(error.localizedDescription))
        }
    }
}
