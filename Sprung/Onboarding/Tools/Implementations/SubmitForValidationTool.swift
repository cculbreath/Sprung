//
//  SubmitForValidationTool.swift
//  Sprung
//
//  Submits data for validation by the user.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct SubmitForValidationTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "validation_type": JSONSchema(
                type: .string,
                description: "Type of data being validated. Each type presents specialized validation UI.",
                enum: ["applicant_profile", "skeleton_timeline", "enabled_sections", "knowledge_card"]
            ),
            "data": JSONSchema(
                type: .object,
                description: "The complete data payload to validate. Schema varies by validation_type."
            ),
            "summary": JSONSchema(
                type: .string,
                description: "Human-readable summary shown to user in validation card. Explain what was collected and what they're confirming."
            )
        ]

        return JSONSchema(
            type: .object,
            description: """
                Present validation card in the tool pane for user review and confirmation of collected data.

                This is the primary confirmation surface for most Phase 1 objectives. Use this at the end of a sub-phase to get user sign-off before persisting data.

                RETURNS: { "message": "UI presented. Awaiting user input.", "status": "completed" }

                The tool completes immediately after presenting UI. User validation response arrives as a new user message with status: "confirmed", "rejected", or "modified".

                USAGE: Call at sub-phase boundaries to confirm collected data before persisting. Provides user control and prevents storing incorrect/incomplete data. The summary parameter should explain what they're reviewing.

                WORKFLOW:
                1. Collect data for a sub-phase (e.g., skeleton timeline cards)
                2. Call submit_for_validation with validation_type, data, and summary
                3. Tool returns immediately - validation card is now active
                4. User reviews, edits if needed, and confirms/rejects
                5. You receive validation response with status and (potentially modified) data
                6. If confirmed, call persist_data with the validated data

                Phase 1 validation_types:
                - applicant_profile: Contact info validation
                - skeleton_timeline: Timeline cards review before persisting
                - enabled_sections: Resume sections confirmation

                DO NOT: Re-validate already confirmed data unless new information is introduced. Once meta.validation_state = "user_validated", trust it.
                """,
            properties: properties,
            required: ["validation_type", "data", "summary"]
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "submit_for_validation" }
    var description: String { "Present validation card for user review. Returns immediately - response arrives as user message. Use at sub-phase boundaries." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let payload = try ValidationPayload(json: params)

        // Emit UI request to show the validation prompt
        await coordinator.eventBus.publish(.validationPromptRequested(prompt: payload.toValidationPrompt()))

        // Return completed - the tool's job is to present UI, which it has done
        // User's validation response will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"

        return .immediate(response)
    }
}

private struct ValidationPayload {
    let validationType: String
    let data: JSON
    let summary: String

    init(json: JSON) throws {
        guard let type = json["validation_type"].string, !type.isEmpty else {
            throw ToolError.invalidParameters("validation_type must be provided")
        }

        let validTypes = ["applicant_profile", "skeleton_timeline", "enabled_sections", "knowledge_card"]
        guard validTypes.contains(type) else {
            throw ToolError.invalidParameters("validation_type must be one of: \(validTypes.joined(separator: ", "))")
        }

        self.validationType = type

        guard let data = json["data"].dictionary, !data.isEmpty else {
            throw ToolError.invalidParameters("data must be a non-empty object")
        }
        self.data = json["data"]

        guard let summary = json["summary"].string, !summary.isEmpty else {
            throw ToolError.invalidParameters("summary must be provided")
        }
        self.summary = summary
    }

    func toValidationPrompt() -> OnboardingValidationPrompt {
        OnboardingValidationPrompt(
            dataType: validationType,
            payload: data,
            message: summary
        )
    }
}