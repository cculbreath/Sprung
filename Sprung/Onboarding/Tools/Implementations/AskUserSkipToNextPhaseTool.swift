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
            EMERGENCY ONLY - Ask user to override a blocked phase transition.
            DO NOT USE THIS FOR NORMAL PHASE TRANSITIONS - use next_phase instead.
            Only call this AFTER next_phase has returned a "blocked" status.
            WORKFLOW:
            1. Call next_phase first (ALWAYS try this first)
            2. If next_phase returns blocked, THEN call this tool
            3. If user approves, call next_phase again
            RETURNS: { "status": "approved" } or { "status": "rejected" }
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
        "EMERGENCY ONLY: Ask user to override a blocked next_phase. Call next_phase FIRST - only use this if next_phase returns blocked."
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
