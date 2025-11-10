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
                description: "Optional summary message shown to user in timeline review card. Explain what they're reviewing and what to check for."
            )
        ]

        return JSONSchema(
            type: .object,
            description: """
                Present the current skeleton timeline in an editable review UI card for user validation and corrections.

                Use this at the end of timeline building to get user confirmation before persisting. User can review all entries, make edits, and confirm accuracy.

                RETURNS: { "message": "UI presented. Awaiting user input.", "status": "completed" }

                The tool completes immediately after presenting UI. User validation response arrives as a new user message with status and (potentially modified) timeline data.

                USAGE: Call after collecting all timeline entries via create_timeline_card and user confirms data gathering is complete. This is the validation checkpoint before calling persist_data.

                WORKFLOW:
                1. Collect timeline cards via chat interview + create_timeline_card
                2. When timeline feels complete, call display_timeline_entries_for_review
                3. Tool returns immediately - review card is now active
                4. User reviews timeline, makes corrections in UI if needed, confirms/rejects
                5. You receive validation response with status and timeline data
                6. If confirmed, call persist_data(dataType: "skeleton_timeline", data: <timeline>)

                ERROR: Will fail if no timeline cards exist yet. Create at least one card before requesting review.

                DO NOT: Call this before timeline collection is reasonably complete - premature validation wastes user time.
                """,
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
    var description: String { "Present timeline review UI with all cards. Returns immediately - validation response arrives as user message. Use before persisting." }
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
        await coordinator.eventBus.publish(.validationPromptRequested(prompt: validationPrompt))

        // Return completed - the tool's job is to present UI, which it has done
        // User's validation response will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"

        return .immediate(response)
    }
}
