//
//  DeletePublicationCardTool.swift
//  Sprung
//
//  Tool for deleting publication cards.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct DeletePublicationCardTool: InterviewTool {
    private weak var coordinator: OnboardingInterviewCoordinator?

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.deletePublicationCard.rawValue }

    var description: String {
        """
        Delete a publication card by ID. Use when the user indicates a publication is incorrect or should be removed. \
        RETURNS: { "success": true, "id": "<deleted-card-id>" }.
        """
    }

    var parameters: JSONSchema { PublicationCardSchema.deleteSchema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }

        // Validate required parameters
        guard let cardId = params["id"].string, !cardId.isEmpty else {
            throw ToolError.invalidParameters("Card ID is required")
        }

        // Verify the card exists
        let exists = await coordinator.ui.publicationCardExists(id: cardId)
        guard exists else {
            throw ToolError.invalidParameters("No publication card found with ID: \(cardId)")
        }

        // Delete publication card via service
        let result = await coordinator.sectionCards.deletePublicationCard(id: cardId)

        return .immediate(result)
    }
}
