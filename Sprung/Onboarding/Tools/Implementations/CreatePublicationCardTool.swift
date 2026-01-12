//
//  CreatePublicationCardTool.swift
//  Sprung
//
//  Tool for creating publication cards during onboarding.
//  Publications can be added via interview or imported from BibTeX/CV.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CreatePublicationCardTool: InterviewTool {
    private weak var coordinator: OnboardingInterviewCoordinator?

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.createPublicationCard.rawValue }

    var description: String {
        """
        Create a publication card for a research paper, article, book, or other publication. \
        RETURNS: { "success": true, "id": "<card-id>" }. \
        Cards appear in the timeline editor under the Publications section.
        """
    }

    var parameters: JSONSchema { PublicationCardSchema.createSchema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }

        // Get fields
        guard let fieldsDict = params["fields"].dictionary else {
            throw ToolError.invalidParameters("fields is required and must be an object")
        }

        // Convert to Data for decoding
        let fieldsData = try JSONSerialization.data(withJSONObject: fieldsDict.mapValues { $0.object })
        let decoder = JSONDecoder()

        // Validate required fields
        let input = try decoder.decode(CreatePublicationInput.self, from: fieldsData)
        guard !input.name.isEmpty else {
            throw ToolError.invalidParameters("Publication name/title is required")
        }

        // Create publication card via service (default source type is "interview")
        let result = await coordinator.sectionCards.createPublicationCard(
            fields: params["fields"],
            sourceType: "interview"
        )

        // Signal UI to update
        await MainActor.run {
            coordinator.ui.sectionCardToolWasUsed = true
        }

        return .immediate(result)
    }
}
