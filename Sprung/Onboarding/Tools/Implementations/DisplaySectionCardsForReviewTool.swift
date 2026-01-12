//
//  DisplaySectionCardsForReviewTool.swift
//  Sprung
//
//  Tool to activate the section cards editor UI for user review.
//  Covers non-chronological sections: awards, publications, languages, references.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct DisplaySectionCardsForReviewTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Activate section cards EDITOR UI for user review and editing.",
            properties: [
                "summary": JSONSchema(
                    type: .string,
                    description: "Brief summary of the section cards to be reviewed (optional)"
                )
            ],
            required: [],
            additionalProperties: false
        )
    }()

    private weak var coordinator: OnboardingInterviewCoordinator?

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.displaySectionCardsForReview.rawValue }

    var description: String {
        """
        Activate section cards EDITOR UI for user review. \
        User can edit awards, publications, languages, and references in the Timeline tab. \
        Call this after creating section cards, before final validation.
        """
    }

    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }

        // Activate the section cards editor in the Timeline tab
        await MainActor.run {
            coordinator.ui.isSectionCardsEditorActive = true
        }

        // Mark section cards objective as in_progress
        await coordinator.eventBus.publish(.objective(.statusUpdateRequested(
            id: OnboardingObjectiveId.sectionCardsComplete.rawValue,
            status: "in_progress",
            source: "display_section_cards_tool",
            notes: "Section cards editor activated",
            details: nil
        )))

        // Emit UI update event
        await coordinator.eventBus.publish(.sectionCard(.uiUpdateNeeded))

        var response = JSON()
        response["message"].string = "Section cards editor activated. User can now edit awards, publications, languages, and references in the Timeline tab."
        response["status"].string = "completed"
        return .immediate(response)
    }
}
