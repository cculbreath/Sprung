//
//  NextPhaseTool.swift
//  Sprung
//
//  Requests advancing to the next interview phase.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct NextPhaseTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "overrides": JSONSchema(
                type: .array,
                description: "Optional. List of objectives to skip/override",
                items: JSONSchema(type: .string)
            ),
            "reason": JSONSchema(
                type: .string,
                description: "Optional. Reason for requesting to advance with unmet objectives"
            )
        ]

        return JSONSchema(
            type: .object,
            properties: properties
        )
    }()

    let service: OnboardingInterviewService

    var name: String { "next_phase" }
    var description: String { "Request advancing to the next interview phase." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // TODO: Reimplement using event-driven architecture
        // Temporarily return empty response to fix compilation
        var response = JSON()
        response["status"] = "pending"
        response["message"] = "Phase advancement temporarily disabled during refactoring"
        return .immediate(response)
    }
}