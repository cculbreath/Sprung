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
                enum: ["applicant_profile", "skeleton_timeline", "enabled_sections"]
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

    let service: OnboardingInterviewService

    var name: String { "submit_for_validation" }
    var description: String { "Submit collected data for user validation" }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let payload = try ValidationPayload(json: params)
        let continuationId = UUID()

        var waitingPayload = JSON()
        waitingPayload["status"].string = "waiting"
        waitingPayload["tool"].string = name
        waitingPayload["message"].string = "Waiting for validation response"
        waitingPayload["validation_type"].string = payload.validationType

        let token = ContinuationToken(
            id: continuationId,
            toolName: name,
            initialPayload: waitingPayload,
            uiRequest: .validationPrompt(payload.toValidationPrompt()),
            resumeHandler: { input in
                if input["cancelled"].boolValue {
                    return .error(.userCancelled)
                }

                guard let status = input["status"].string else {
                    return .error(.invalidParameters("status is required"))
                }

                var response = JSON()
                response["status"].string = status

                if input["updatedData"].exists() {
                    response["updatedData"] = input["updatedData"]
                }

                if input["changes"].exists() {
                    response["changes"] = input["changes"]
                }

                if let notes = input["notes"].string {
                    response["notes"].string = notes
                }

                return .immediate(response)
            }
        )

        return .waiting(message: "Waiting for validation response", continuation: token)
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

        let validTypes = ["applicant_profile", "skeleton_timeline", "enabled_sections"]
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