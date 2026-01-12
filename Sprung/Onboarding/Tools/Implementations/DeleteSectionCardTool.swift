//
//  DeleteSectionCardTool.swift
//  Sprung
//
//  Tool for deleting section cards for non-chronological resume sections.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct DeleteSectionCardTool: InterviewTool {
    private weak var coordinator: OnboardingInterviewCoordinator?

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.deleteSectionCard.rawValue }

    var description: String {
        """
        Delete a section card by ID. Use when the user indicates an entry is incorrect or should be removed. \
        RETURNS: { "success": true, "id": "<deleted-card-id>" }.
        """
    }

    var parameters: JSONSchema { SectionCardSchema.deleteSchema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }

        // Validate required parameters
        guard let cardId = params["id"].string, !cardId.isEmpty else {
            throw ToolError.invalidParameters("Card ID is required")
        }

        // Look up the card to get its section type
        let sectionType = await coordinator.ui.getSectionCardType(id: cardId)
        guard let sectionType else {
            throw ToolError.invalidParameters("No section card found with ID: \(cardId)")
        }

        // Delete section card via service
        let result = await coordinator.sectionCards.deleteSectionCard(
            id: cardId,
            sectionType: sectionType
        )

        return .immediate(result)
    }
}
