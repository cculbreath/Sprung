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
        let tokenId = UUID()

        var waitingPayload = JSON()
        waitingPayload["status"].string = "waiting"
        waitingPayload["tool"].string = name
        waitingPayload["message"].string = "Waiting for user to configure enabled sections"
        waitingPayload["action_required"].string = "section_toggle"

        let request = OnboardingSectionToggleRequest(
            id: tokenId,
            proposedSections: payload.proposedSections,
            availableSections: payload.availableSections,
            rationale: payload.rationale
        )

        let token = ContinuationToken(
            id: tokenId,
            toolName: name,
            initialPayload: waitingPayload,
            uiRequest: .sectionToggle(request),
            resumeHandler: { input in
                if input["cancelled"].boolValue {
                    return .error(.userCancelled)
                }

                guard let enabledArray = input["enabledSections"].arrayObject as? [String] else {
                    return .error(.invalidParameters("enabledSections must be an array of strings"))
                }

                var response = JSON()
                response["status"].string = "confirmed"
                response["enabledSections"] = JSON(enabledArray)
                response["timestamp"].string = self.dateFormatter.string(from: Date())
                return .immediate(response)
            }
        )

        return .waiting(message: "Waiting for user to configure enabled sections", continuation: token)
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
