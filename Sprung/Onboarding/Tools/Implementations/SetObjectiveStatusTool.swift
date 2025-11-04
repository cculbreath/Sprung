import Foundation
import SwiftyJSON
import SwiftOpenAI

struct SetObjectiveStatusTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Mark an onboarding objective as pending, in progress, completed, or skipped.",
            properties: [
                "objective_id": JSONSchema(
                    type: .string,
                    description: "Identifier of the objective (e.g., applicant_profile)."
                ),
                "status": JSONSchema(
                    type: .string,
                    description: "Desired status (pending, in_progress, completed, skipped).",
                    enum: ["pending", "in_progress", "completed", "skipped", "reset"]
                )
            ],
            required: ["objective_id", "status"],
            additionalProperties: false
        )
    }()

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "set_objective_status" }
    var description: String { "Update the status of an onboarding objective." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let objectiveId = params["objective_id"].string, !objectiveId.isEmpty else {
            throw ToolError.invalidParameters("objective_id must be provided")
        }
        guard let status = params["status"].string?.lowercased() else {
            throw ToolError.invalidParameters("status must be provided")
        }

        // TODO: Emit event for objective status update
        // let result = try await service.updateObjectiveStatus(objectiveId: objectiveId, status: status)
        var response = JSON()
        response["objective_id"].string = objectiveId
        response["status"].string = status
        response["success"].bool = true
        return .immediate(response)
    }
}
