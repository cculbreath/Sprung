//
//  DisplayTimelineForReviewTool.swift
//  Sprung
//
//  Convenience tool to display the current skeleton timeline for user review.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct DisplayTimelineForReviewTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "summary": JSONSchema(
                type: .string,
                description: "Optional summary message to display with the timeline review"
            )
        ]

        return JSONSchema(
            type: .object,
            properties: properties,
            required: [],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "display_timeline_entries_for_review" }
    var description: String { "Display the current skeleton timeline entries for user review and confirmation" }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Query current timeline from coordinator
        guard let timelineJSON = await coordinator.skeletonTimelineJSON else {
            throw ToolError.invalidParameters("No skeleton timeline exists yet. Create timeline cards first.")
        }

        // Validate that timeline has at least one entry
        let timelineArray = timelineJSON["timeline"].array ?? []
        guard !timelineArray.isEmpty else {
            throw ToolError.invalidParameters("Timeline is empty. Create timeline cards before requesting review.")
        }

        // Get optional summary message
        let summary = params["summary"].string ?? "Please review the timeline entries below and confirm they are accurate."

        // Build validation prompt
        let validationPrompt = OnboardingValidationPrompt(
            dataType: "skeleton_timeline",
            payload: timelineJSON,
            message: summary
        )

        // Emit UI request to show the validation prompt
        await coordinator.eventBus.publish(.validationPromptRequested(prompt: validationPrompt, continuationId: UUID()))

        // Return completed - the tool's job is to present UI, which it has done
        // User's validation response will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"

        return .immediate(response)
    }
}
