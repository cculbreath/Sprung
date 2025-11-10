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
                type: .object,
                description: """
                    Object mapping JSON Resume top-level section keys to boolean enabled/disabled state.

                    Valid section keys (from JSON Resume schema):
                    - work: Work experience entries
                    - education: Educational background
                    - volunteer: Volunteer experience
                    - awards: Professional awards and recognitions
                    - certificates: Professional certifications
                    - publications: Published works
                    - skills: Technical and professional skills
                    - languages: Language proficiencies
                    - interests: Personal interests and hobbies
                    - references: Professional references
                    - projects: Career projects and portfolio items

                    Example: { "work": true, "education": true, "skills": true, "publications": false, "projects": true, "awards": false }
                    """,
                additionalProperties: true
            ),
            "rationale": JSONSchema(
                type: .string,
                description: "Optional explanation or context for the proposed sections"
            )
        ]

        return JSONSchema(
            type: .object,
            description: """
                Present a section toggle UI card where user selects which JSON Resume sections to include in their final resume.

                Use this at the end of skeleton_timeline to let user customize their resume structure. The UI shows toggles for each section with your proposed selections pre-checked.

                RETURNS: { "message": "UI presented. Awaiting user input.", "status": "completed" }

                The tool completes immediately after presenting UI. User's final section selections arrive as a new user message.

                USAGE: Call after skeleton timeline is complete. Analyze user's timeline/profile to propose which sections they likely want. Set sections to true/false based on what you've gathered.

                WORKFLOW:
                1. Skeleton timeline is complete and validated
                2. Analyze what data user provided (mentioned publications → "publications": true, no awards → "awards": false)
                3. Build proposed_sections object: { "work": true, "education": true, "skills": true, ... }
                4. Call configure_enabled_sections with your proposal
                5. Tool returns immediately - section toggle card is now active
                6. User confirms/modifies section selections (toggles on/off)
                7. You receive user message with final enabled sections object
                8. Call persist_data(dataType: "experience_defaults", data: { enabled_sections: <user-confirmed-object> })

                Required sections (always include): basics (not toggleable - contact info always included)
                Common sections: work, education, skills, projects, volunteer, awards, certificates, publications, languages, interests, references

                DO NOT: Hardcode all sections to true. Be selective based on user's actual data. If they haven't mentioned awards, set "awards": false.
                """,
            properties: properties,
            required: ["proposed_sections"],
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
        "Present section toggle UI. Pass object: {\"work\": true, \"education\": true, \"skills\": false, ...}. Returns immediately - selections arrive as user message."
    }
    var parameters: JSONSchema { Self.schema }

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        let payload = try SectionTogglePayload(json: params)
        let requestId = UUID()

        // Use enum as source of truth for all available sections
        let allSections = ExperienceSectionKey.allCases.map(\.rawValue)

        let request = OnboardingSectionToggleRequest(
            id: requestId,
            proposedSections: payload.proposedSections,
            availableSections: allSections,
            rationale: payload.rationale
        )

        // Emit UI request to show the section toggle UI
        await coordinator.eventBus.publish(.sectionToggleRequested(request: request))

        // Return completed - the tool's job is to present UI, which it has done
        // User's section selection will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"

        return .immediate(response)
    }
}

private struct SectionTogglePayload {
    let proposedSections: [String]
    let rationale: String?

    init(json: JSON) throws {
        guard let proposedObj = json["proposed_sections"].dictionary else {
            throw ToolError.invalidParameters("proposed_sections must be an object mapping section keys to boolean values")
        }

        // Extract keys where value is true (enabled sections)
        var enabled: [String] = []
        for (key, value) in proposedObj {
            if value.bool == true {
                enabled.append(key)
            }
        }

        // Validate section keys against enum (source of truth)
        let validSections = Set(ExperienceSectionKey.allCases.map(\.rawValue))
        let invalidKeys = enabled.filter { !validSections.contains($0) }
        if !invalidKeys.isEmpty {
            throw ToolError.invalidParameters("Invalid section keys: \(invalidKeys.joined(separator: ", ")). Must be valid JSON Resume top-level keys: \(validSections.sorted().joined(separator: ", "))")
        }

        self.proposedSections = enabled
        self.rationale = json["rationale"].string
    }
}
