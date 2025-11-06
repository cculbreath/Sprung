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
                description: "Type of validation to perform",
                enum: ["applicant_profile", "skeleton_timeline", "enabled_sections", "knowledge_card"]
            ),
            "data": JSONSchema(
                type: .object,
                description: "The data to validate"
            ),
            "summary": JSONSchema(
                type: .string,
                description: "Summary of what was collected for the user"
            )
        ]

        return JSONSchema(
            type: .object,
            properties: properties,
            required: ["validation_type", "data", "summary"]
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "submit_for_validation" }
    var description: String { "Submit collected data for user validation" }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let payload = try ValidationPayload(json: params)

        // Emit UI request to show the validation prompt
        await coordinator.eventBus.publish(.validationPromptRequested(prompt: payload.toValidationPrompt(), continuationId: UUID()))

        // Return immediately - we'll handle the validation response as a new user message
        var response = JSON()
        response["status"].string = "awaiting_user_input"
        response["message"].string = "Validation prompt has been presented to the user"

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