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
            "proposedSections": MiscSchemas.proposedSections,
            "rationale": MiscSchemas.sectionConfigRationale
        ]
        return JSONSchema(
            type: .object,
            description: """
                Present a section toggle UI card where user selects which JSON Resume sections to include.

                CRITICAL: You MUST provide the proposedSections parameter as an object mapping section keys to booleans.

                CORRECT CALL FORMAT:
                {
                  "proposedSections": {"work": true, "education": true, "skills": true, "projects": true, "publications": false},
                  "rationale": "optional explanation"
                }

                INCORRECT (will fail):
                {"rationale": "some text"}  ← MISSING proposedSections!

                Valid section keys: work, education, volunteer, awards, certificates, publications, skills, languages, interests, references, projects

                Set sections to true/false based on user's data. If they mentioned publications, set "publications": true. If no awards mentioned, set "awards": false.
                """,
            properties: properties,
            required: ["proposedSections"],
            additionalProperties: false
        )
    }()
    private weak var coordinator: OnboardingInterviewCoordinator?

    var name: String { OnboardingToolName.configureEnabledSections.rawValue }
    var description: String {
        """
        Present section toggle UI. REQUIRED: proposedSections object with section keys mapped to boolean values.
        Example call: {"proposedSections": {"work": true, "education": true, "skills": true, "projects": true, "publications": false}, "rationale": "optional explanation"}
        The proposedSections parameter is REQUIRED - do NOT omit it.
        """
    }
    var parameters: JSONSchema { Self.schema }
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
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
        await coordinator.eventBus.publish(.toolpane(.sectionToggleRequested(request: request)))
        // Block until user completes the action or interrupts
        let result = await coordinator.uiToolContinuationManager.awaitUserAction(toolName: name)
        return .immediate(result.toJSON())
    }
}
private struct SectionTogglePayload {
    let proposedSections: [String]
    let rationale: String?
    init(json: JSON) throws {
        // Try to get proposedSections as an object
        var proposedObj: [String: JSON]?

        if let dict = json["proposedSections"].dictionary {
            // Normal case: already an object
            proposedObj = dict
        } else if let jsonString = json["proposedSections"].string {
            // Handle double-encoding: LLM passed a JSON string instead of an object
            // Try to parse the string as JSON
            if let data = jsonString.data(using: .utf8) {
                let parsed = JSON(data)
                if let dict = parsed.dictionary {
                    proposedObj = dict
                    Logger.warning("⚠️ configure_enabled_sections: proposedSections was double-encoded as string, parsed successfully", category: .ai)
                }
            }
        }

        guard let proposedObj = proposedObj else {
            throw ToolError.invalidParameters(
                "proposedSections must be an object, not a string. " +
                "CORRECT: {\"proposedSections\": {\"work\": true, \"education\": true}} " +
                "WRONG: {\"proposedSections\": \"{\\\"work\\\": true}\"}"
            )
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
