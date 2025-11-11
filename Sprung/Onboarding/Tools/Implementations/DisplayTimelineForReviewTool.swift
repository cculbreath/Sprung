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
                Activate the timeline review UI in the Tool Pane so timeline cards become visible to the user as you create them.

                CRITICAL WORKFLOW SEQUENCE:
                1. FIRST: Call this tool to activate the timeline UI (even before creating any cards)
                2. THEN: Create timeline cards using create_timeline_card - cards appear in UI immediately
                3. FINALLY: User can review, edit, delete, or approve cards through the UI in real-time

                RETURNS: { "message": "UI presented. Awaiting user input.", "status": "completed" }

                The tool completes immediately after activating the timeline UI. Timeline cards you create afterward will appear in this UI automatically.

                USAGE: Call this BEFORE creating timeline cards when starting skeleton_timeline workflow. This activates the UI container where cards will appear.

                WORKFLOW:
                1. Call display_timeline_entries_for_review to activate timeline UI
                2. Create cards with create_timeline_card - each appears immediately in the UI
                3. User can edit/delete/approve cards in real-time as you create them
                4. Refine cards based on user feedback until timeline is complete
                5. User confirms timeline completeness through the UI

                ERROR: Will fail if called when timeline UI is already active or if skeleton timeline has already been validated/persisted.

                DO NOT: Wait to create all cards before calling this - call it FIRST to activate the UI, then create cards one by one.
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
        // Get current timeline from coordinator (may be nil or empty - that's OK!)
        let timelineJSON = await MainActor.run {
            coordinator.skeletonTimelineSync ?? JSON()
        }

        // Get optional summary message
        let summary = params["summary"].string ?? "Timeline review activated. Cards will appear here as you create them."

        // Build validation prompt - even if timeline is empty, we activate the UI
        // Cards created afterward will appear in this UI in real-time
        let validationPrompt = OnboardingValidationPrompt(
            dataType: "skeleton_timeline",
            payload: timelineJSON,
            message: summary
        )

        // Emit UI request to show the validation prompt
        await coordinator.eventBus.publish(.validationPromptRequested(prompt: validationPrompt))

        // Return completed - the tool's job is to activate UI, which it has done
        // Timeline cards created afterward will appear in this UI automatically
        var response = JSON()
        response["message"].string = "Timeline review UI activated. Cards will appear as you create them."
        response["status"].string = "completed"

        return .immediate(response)
    }
}
