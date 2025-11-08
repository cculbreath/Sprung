import Foundation
import SwiftyJSON
import SwiftOpenAI

struct SetObjectiveStatusTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Mark an onboarding objective as pending, in progress, completed, or skipped. Optionally provide context details.",
            properties: [
                "objective_id": JSONSchema(
                    type: .string,
                    description: "Identifier of the objective (e.g., applicant_profile)."
                ),
                "status": JSONSchema(
                    type: .string,
                    description: "Desired status (pending, in_progress, completed, skipped).",
                    enum: ["pending", "in_progress", "completed", "skipped"]
                ),
                "notes": JSONSchema(
                    type: .string,
                    description: "Optional notes about this status change."
                ),
                "details": JSONSchema(
                    type: .object,
                    description: "Optional string key-value pairs with context (e.g., source='manual', mode='skip', artifact_id='123').",
                    additionalProperties: true
                )
            ],
            required: ["objective_id", "status"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
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

        // Validate status value
        let validStatuses = ["pending", "in_progress", "completed", "skipped"]
        guard validStatuses.contains(status) else {
            throw ToolError.invalidParameters("Invalid status: \(status). Must be one of: pending, in_progress, completed, skipped")
        }

        // Extract optional metadata
        let notes = params["notes"].string
        var details: [String: String] = [:]
        if let detailsJSON = params["details"].dictionary {
            for (key, value) in detailsJSON {
                if let stringValue = value.string {
                    details[key] = stringValue
                } else {
                    throw ToolError.invalidParameters("details values must be strings (key: \(key))")
                }
            }
        }

        // Update objective status via coordinator (which emits events)
        let result = try await coordinator.updateObjectiveStatus(
            objectiveId: objectiveId,
            status: status,
            notes: notes,
            details: details
        )

        return .immediate(result)
    }
}
