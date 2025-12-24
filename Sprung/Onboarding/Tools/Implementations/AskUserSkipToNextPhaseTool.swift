//
//  AskUserSkipToNextPhaseTool.swift
//  Sprung
//
//  Asks user for explicit approval to skip to next phase when requirements aren't met.
//  This is the ONLY way to ungate next_phase when knowledge cards are missing.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct AskUserSkipToNextPhaseTool: InterviewTool {
    private static let schema: JSONSchema = JSONSchema(
        type: .object,
        description: """
            Ask user for explicit approval to skip to the next phase when requirements aren't met.
            Use this when next_phase is blocked (e.g., no knowledge cards generated).
            Presents a confirmation dialog to the user. If they approve, next_phase becomes unblocked.
            RETURNS: { "status": "approved" } or { "status": "rejected" }
            WORKFLOW:
            1. next_phase returns blocked with reason "no_knowledge_cards"
            2. Call this tool to ask user if they want to proceed anyway
            3. If approved, call next_phase again - it will now succeed
            4. If rejected, continue trying to generate knowledge cards
            """,
        properties: [
            "reason": JSONSchema(
                type: .string,
                description: "Brief explanation of why skip is needed (shown to user)"
            )
        ],
        required: ["reason"],
        additionalProperties: false
    )

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.askUserSkipToNextPhase.rawValue }
    var description: String {
        "Ask user for explicit approval to skip to next phase when blocked by missing requirements."
    }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let reason = params["reason"].stringValue

        // Create a choice prompt for user approval
        let prompt = OnboardingChoicePrompt(
            prompt: """
                Skip to next phase?

                The assistant wants to move to the next phase, but some steps weren't completed:

                \(reason)

                Do you want to proceed anyway?
                """,
            options: [
                OnboardingChoiceOption(id: "approve", title: "Yes, skip ahead", detail: nil, icon: nil),
                OnboardingChoiceOption(id: "reject", title: "No, keep working", detail: nil, icon: nil)
            ],
            selectionStyle: .single,
            required: true,
            source: "skip_phase_approval"  // Used to identify this prompt for special handling
        )

        // Present the choice prompt
        await coordinator.eventBus.publish(.choicePromptRequested(prompt: prompt))

        // Return pending - user response will complete the tool call
        return .pendingUserAction
    }
}
