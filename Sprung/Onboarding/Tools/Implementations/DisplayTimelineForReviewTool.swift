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
                Activate the timeline EDITOR UI in the Tool Pane so timeline cards become visible and editable as you create them.

                PURPOSE: This opens an EDITOR interface (NOT final approval). The user can make live edits, delete cards, or click "Save Timeline" to send changes back to you. This allows iterative refinement.

                CRITICAL WORKFLOW SEQUENCE:
                1. FIRST: Call this tool to activate the timeline editor (even before creating any cards)
                2. THEN: Create timeline cards using create_timeline_card - cards appear in editor immediately
                3. DURING: User can edit, delete, reorder cards and click "Save Timeline" to send updates
                4. FINALLY: When timeline is complete, call submit_for_validation to present FINAL APPROVAL UI

                RETURNS: { "message": "Timeline review UI activated.", "status": "completed" }

                The tool completes immediately after activating the editor. Timeline cards you create afterward will appear in this UI automatically.

                USAGE: Call this BEFORE creating timeline cards when starting skeleton_timeline workflow. This activates the editor where cards will appear.

                WORKFLOW:
                1. Call display_timeline_entries_for_review to activate editor UI
                2. Create cards with create_timeline_card - each appears immediately
                3. User makes live edits and clicks "Save Timeline" when ready
                4. You receive user's changes as a developer message
                5. When timeline is complete, call submit_for_validation for FINAL approval

                IMPORTANT: This is the EDITOR, not the final approval step. After timeline is complete, you must call submit_for_validation to get user's final confirmation.

                ERROR: Will fail if called when timeline UI is already active or if skeleton timeline has already been validated/persisted.
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
    var description: String { "Activate timeline EDITOR UI before creating cards. User can edit/save changes. NOT final approval - use submit_for_validation afterward." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Get current timeline from coordinator (may be nil or empty - that's OK!)
        let timelineJSON = await MainActor.run {
            coordinator.skeletonTimelineSync ?? JSON()
        }

        // Get optional summary message
        let summary = params["summary"].string ?? "Timeline review activated. Cards will appear here as you create them."

        // Build editor prompt - even if timeline is empty, we activate the UI
        // Cards created afterward will appear in this UI in real-time
        let validationPrompt = OnboardingValidationPrompt(
            dataType: "skeleton_timeline",
            payload: timelineJSON,
            message: summary,
            mode: .editor  // Editor mode: allows tools, shows Save button
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
