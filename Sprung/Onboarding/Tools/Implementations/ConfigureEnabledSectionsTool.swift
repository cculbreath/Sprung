//
//  ConfigureEnabledSectionsTool.swift
//  Sprung
//
//  Presents a section toggle UI to configure which resume sections are enabled.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ConfigureEnabledSectionsTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "proposed_sections": JSONSchema(
                type: .array,
                description: "Initial section identifiers to propose as enabled",
                items: JSONSchema(type: .string, description: "Section identifier"),
                required: nil,
                additionalProperties: false
            ),
            "available_sections": JSONSchema(
                type: .array,
                description: "All available section identifiers the user can choose from",
                items: JSONSchema(type: .string, description: "Section identifier"),
                required: nil,
                additionalProperties: false
            ),
            "rationale": JSONSchema(
                type: .string,
                description: "Optional explanation or context for the proposed sections"
            )
        ]

        return JSONSchema(
            type: .object,
            description: "Parameters for the configure_enabled_sections tool",
            properties: properties,
            required: ["proposed_sections", "available_sections"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var name: String { "configure_enabled_sections" }
    var description: String {
        "Present a section toggle UI to configure which resume sections are enabled. Returns the user's confirmed section selections."
    }
    var parameters: JSONSchema { Self.schema }

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        let payload = try SectionTogglePayload(json: params)
        let requestId = UUID()

        let request = OnboardingSectionToggleRequest(
            id: requestId,
            proposedSections: payload.proposedSections,
            availableSections: payload.availableSections,
            rationale: payload.rationale
        )

        // Emit UI request to show the section toggle UI
        await coordinator.eventBus.publish(.sectionToggleRequested(request: request, continuationId: UUID()))

        // Return immediately - we'll handle the section selection as a new user message
        var response = JSON()
        response["status"].string = "awaiting_user_input"
        response["message"].string = "Section toggle UI has been presented to the user"

        return .immediate(response)
    }
}

private struct SectionTogglePayload {
    let proposedSections: [String]
    let availableSections: [String]
    let rationale: String?

    init(json: JSON) throws {
        guard let proposedArray = json["proposed_sections"].arrayObject as? [String] else {
            throw ToolError.invalidParameters("proposed_sections must be an array of strings")
        }
        guard let availableArray = json["available_sections"].arrayObject as? [String], !availableArray.isEmpty else {
            throw ToolError.invalidParameters("available_sections must be a non-empty array of strings")
        }

        self.proposedSections = proposedArray
        self.availableSections = availableArray
        self.rationale = json["rationale"].string
    }
}
