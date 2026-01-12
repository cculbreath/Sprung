//
//  UpdatePublicationCardTool.swift
//  Sprung
//
//  Tool for updating publication cards.
//  Uses PATCH semantics - only provided fields are updated.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct UpdatePublicationCardTool: InterviewTool {
    private weak var coordinator: OnboardingInterviewCoordinator?

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.updatePublicationCard.rawValue }

    var description: String {
        """
        Update an existing publication card with partial field changes (PATCH semantics). \
        Only fields provided in the 'fields' object will be updated; others remain unchanged. \
        RETURNS: { "success": true, "id": "<card-id>" }.
        """
    }

    var parameters: JSONSchema { PublicationCardSchema.updateSchema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }

        // Validate required parameters
        guard let cardId = params["id"].string, !cardId.isEmpty else {
            throw ToolError.invalidParameters("Card ID is required")
        }

        guard let fieldsDict = params["fields"].dictionary, !fieldsDict.isEmpty else {
            throw ToolError.invalidParameters("At least one field must be provided for update")
        }

        // Verify the card exists
        let exists = await coordinator.ui.publicationCardExists(id: cardId)
        guard exists else {
            throw ToolError.invalidParameters("No publication card found with ID: \(cardId)")
        }

        // Update publication card via service
        let result = await coordinator.sectionCards.updatePublicationCard(
            id: cardId,
            fields: params["fields"]
        )

        return .immediate(result)
    }
}
