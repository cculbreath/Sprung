//
//  UpdateSectionCardTool.swift
//  Sprung
//
//  Tool for updating section cards for non-chronological resume sections.
//  Uses PATCH semantics - only provided fields are updated.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct UpdateSectionCardTool: InterviewTool {
    private weak var coordinator: OnboardingInterviewCoordinator?

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.updateSectionCard.rawValue }

    var description: String {
        """
        Update an existing section card with partial field changes (PATCH semantics). \
        Only fields provided in the 'fields' object will be updated; others remain unchanged. \
        RETURNS: { "success": true, "id": "<card-id>" }.
        """
    }

    var parameters: JSONSchema { SectionCardSchema.updateSchema }

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

        // Look up the card to get its section type
        let sectionType = await coordinator.ui.getSectionCardType(id: cardId)
        guard let sectionType else {
            throw ToolError.invalidParameters("No section card found with ID: \(cardId)")
        }

        // Update section card via service
        let result = await coordinator.sectionCards.updateSectionCard(
            id: cardId,
            sectionType: sectionType,
            fields: params["fields"]
        )

        return .immediate(result)
    }
}
