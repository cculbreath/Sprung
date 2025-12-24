import Foundation
import SwiftyJSON
import SwiftOpenAI
struct SetObjectiveStatusTool: InterviewTool {
    private static let schema: JSONSchema = PhaseSchemas.objectiveStatusSchema()
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.setObjectiveStatus.rawValue }
    var description: String { "Update objective status (atomic operation - call alone, no assistant message). Returns {objective_id, status, updated}. Silent background operation." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        let objectiveId = try ToolResultHelpers.requireString(params["objective_id"].string, named: "objective_id")

        guard let status = params["status"].string?.lowercased() else {
            throw ToolError.missingField("status")
        }

        // Validate status value
        let validStatuses = ["pending", "in_progress", "completed", "skipped"]
        guard validStatuses.contains(status) else {
            throw ToolError.invalidEnum(field: "status", value: status, validValues: validStatuses)
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
