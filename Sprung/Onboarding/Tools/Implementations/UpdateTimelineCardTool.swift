import Foundation
import SwiftyJSON
import SwiftOpenAI

struct UpdateTimelineCardTool: InterviewTool {
    private static let schema: JSONSchema = JSONSchema(
        type: .object,
        properties: [
            "id": JSONSchema(type: .string),
            "fields": JSONSchema(type: .object)
        ],
        required: ["id", "fields"]
    )
    
    let service: OnboardingInterviewService
    
    init(service: OnboardingInterviewService) {
        self.service = service
    }
    
    var name: String { "update_timeline_card" }
    var description: String { "Update timeline card" }
    var parameters: JSONSchema { Self.schema }
    
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let id = params["id"].string, !id.isEmpty else {
            throw ToolError.invalidParameters("id must be provided")
        }
        guard let fields = params["fields"].dictionary else {
            throw ToolError.invalidParameters("fields must be provided")
        }

        // Update timeline card via coordinator (which emits events)
        let result = await service.coordinator.updateTimelineCard(id: id, fields: JSON(fields))
        return .immediate(result)
    }
}
