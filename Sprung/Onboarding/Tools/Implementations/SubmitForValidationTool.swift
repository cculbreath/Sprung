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
        // TODO: Reimplement using event-driven architecture
        var response = JSON()
        response["status"] = "pending"
        response["message"] = "Validation temporarily disabled during refactoring"
        return .immediate(response)
    }
}