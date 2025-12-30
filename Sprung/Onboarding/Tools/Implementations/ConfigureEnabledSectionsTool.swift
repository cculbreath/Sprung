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
            "proposed_sections": MiscSchemas.proposedSections,
            "rationale": MiscSchemas.sectionConfigRationale
        ]
        return JSONSchema(
            type: .object,
            description: """
                Present a section toggle UI card where user selects which JSON Resume sections to include.

                CRITICAL: You MUST provide the proposed_sections parameter as an object mapping section keys to booleans.

                CORRECT CALL FORMAT:
                {
                  "proposed_sections": {"work": true, "education": true, "skills": true, "projects": true, "publications": false},
                  "rationale": "optional explanation"
                }

                INCORRECT (will fail):
                {"rationale": "some text"}  ← MISSING proposed_sections!

                Valid section keys: work, education, volunteer, awards, certificates, publications, skills, languages, interests, references, projects

                Set sections to true/false based on user's data. If they mentioned publications, set "publications": true. If no awards mentioned, set "awards": false.
                """,
            properties: properties,
            required: ["proposed_sections"],
            additionalProperties: false
        )
    }()
    private unowned let coordinator: OnboardingInterviewCoordinator

    var name: String { OnboardingToolName.configureEnabledSections.rawValue }
    var description: String {
        """
        Present section toggle UI. REQUIRED: proposed_sections object with section keys mapped to boolean values.
        Example call: {"proposed_sections": {"work": true, "education": true, "skills": true, "projects": true, "publications": false}, "rationale": "optional explanation"}
        The proposed_sections parameter is REQUIRED - do NOT omit it.
        """
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
        // Codex paradigm: Return pending - don't send tool response until user acts.
        // The tool output will be sent when user confirms section selections.
        return .pendingUserAction
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
        for (key, value) in proposedObj where value.bool == true {
            enabled.append(key)
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
