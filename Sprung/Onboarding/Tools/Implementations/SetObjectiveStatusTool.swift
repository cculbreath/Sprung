import Foundation
import SwiftyJSON
import SwiftOpenAI

struct SetObjectiveStatusTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Update the internal status of an onboarding objective (pending, in_progress, completed, skipped).

                Use this to signal workflow progress to the coordinator. The coordinator uses these status updates to manage phase transitions, trigger objective workflows, and maintain the ledger.

                RETURNS: { "objective_id": "<id>", "status": "<status>", "updated": true }

                CRITICAL CONSTRAINT: This tool must be called ALONE without any assistant message in the same turn. Status updates are atomic, fire-and-forget operations.

                USAGE:
                - Mark objectives "in_progress" when starting work
                - Mark "completed" when finished (coordinator may auto-complete parent objectives)
                - Mark "skipped" when user declines optional steps
                - Do NOT communicate status changes to user in chat - these are silent background operations

                WORKFLOW: Tool responses are for internal tracking only. The coordinator sends developer messages when objectives complete; you don't need to echo status changes.
                """,
            properties: [
                "objective_id": JSONSchema(
                    type: .string,
                    description: "Identifier of the objective to update. Must match Phase 1 objective namespace.",
                    enum: [
                        // Top-level Phase 1 objectives
                        "applicant_profile",
                        "skeleton_timeline",
                        "enabled_sections",
                        "dossier_seed",

                        // Applicant profile sub-objectives
                        "contact_source_selected",
                        "contact_data_collected",
                        "contact_data_validated",
                        "contact_photo_collected",
                        "applicant_profile.contact_intake",
                        "applicant_profile.contact_intake.activate_card",
                        "applicant_profile.contact_intake.persisted",
                        "applicant_profile.profile_photo",
                        "applicant_profile.profile_photo.retrieve_profile",
                        "applicant_profile.profile_photo.evaluate_need",
                        "applicant_profile.profile_photo.collect_upload",

                        // Skeleton timeline sub-objectives
                        "skeleton_timeline.intake_artifacts",
                        "skeleton_timeline.timeline_editor",
                        "skeleton_timeline.context_interview",
                        "skeleton_timeline.completeness_signal"
                    ]
                ),
                "status": JSONSchema(
                    type: .string,
                    description: "Desired status for this objective.",
                    enum: ["pending", "in_progress", "completed", "skipped"]
                ),
                "notes": JSONSchema(
                    type: .string,
                    description: "Optional notes about this status change for debugging/logging."
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
    var description: String { "Update objective status (atomic operation - call alone, no assistant message). Returns {objective_id, status, updated}. Silent background operation." }
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
