//
//  CreateSectionCardTool.swift
//  Sprung
//
//  Tool for creating section cards for non-chronological resume sections.
//  Handles awards, languages, and references.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CreateSectionCardTool: InterviewTool {
    private weak var coordinator: OnboardingInterviewCoordinator?

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.createSectionCard.rawValue }

    var description: String {
        """
        Create a section card for a non-chronological resume section (award, language, or reference). \
        RETURNS: { "success": true, "id": "<card-id>", "sectionType": "<type>" }. \
        Cards appear in the timeline editor under their respective section.
        """
    }

    var parameters: JSONSchema { SectionCardSchema.createSchema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }

        // Validate section type
        guard let sectionTypeString = params["sectionType"].string,
              let sectionType = AdditionalSectionType(rawValue: sectionTypeString) else {
            throw ToolError.invalidParameters("sectionType is required and must be one of: award, language, reference")
        }

        // Get fields
        guard let fieldsDict = params["fields"].dictionary else {
            throw ToolError.invalidParameters("fields is required and must be an object")
        }

        // Convert to Data for decoding
        let fieldsData = try JSONSerialization.data(withJSONObject: fieldsDict.mapValues { $0.object })
        let decoder = JSONDecoder()

        // Validate required fields based on section type
        switch sectionType {
        case .award:
            let input = try decoder.decode(CreateAwardInput.self, from: fieldsData)
            guard !input.title.isEmpty else {
                throw ToolError.invalidParameters("Award title is required")
            }

        case .language:
            let input = try decoder.decode(CreateLanguageInput.self, from: fieldsData)
            guard !input.language.isEmpty else {
                throw ToolError.invalidParameters("Language name is required")
            }

        case .reference:
            let input = try decoder.decode(CreateReferenceInput.self, from: fieldsData)
            guard !input.name.isEmpty else {
                throw ToolError.invalidParameters("Reference name is required")
            }
        }

        // Build normalized fields JSON
        var normalizedFields = params["fields"]

        // Create section card via service
        let result = await coordinator.sectionCards.createSectionCard(
            sectionType: sectionTypeString,
            fields: normalizedFields
        )

        // Signal UI to update
        await MainActor.run {
            coordinator.ui.sectionCardToolWasUsed = true
        }

        return .immediate(result)
    }
}
