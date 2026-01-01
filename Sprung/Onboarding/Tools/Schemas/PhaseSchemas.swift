//
//  PhaseSchemas.swift
//  Sprung
//
//  Shared JSON schema definitions for phase management tools.
//  DRY: Used by NextPhaseTool and AgentReadyTool.
//
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Shared schema definitions for phase management
enum PhaseSchemas {
    /// Schema for phase transition requests
    /// Used by NextPhaseTool
    static func phaseTransitionSchema() -> JSONSchema {
        JSONSchema(
            type: .object,
            description: """
                Advance to the next interview phase. Use when user wants to skip or when objectives are complete.
                Normal progression uses phase-specific tools. In Phase 2, KC generation is handled by UI buttons.
                RETURNS:
                - { "status": "completed", "new_phase": "...", "next_required_tool": "..." }
                - If objectives skipped: includes "skipped_objectives" array
                - Phase 2→3 requires knowledge cards OR user approval via submit_for_validation
                - Phase 3→Complete without experience_defaults: { "error": true, "reason": "missing_experience_defaults" }
                BLOCKING: If blocked due to missing knowledge cards, use submit_for_validation with \
                validation_type="skip_kc_approval" to ask user for explicit approval. Only user UI \
                approval can ungate phase transition.
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }

    /// Schema for agent ready bootstrap tool
    /// Used by AgentReadyTool
    static func agentReadySchema() -> JSONSchema {
        JSONSchema(
            type: .object,
            description: """
                Signal that you have received and understood the phase instructions and are ready to begin the interview.
                This is a bootstrap tool used only during conversation initialization. \
                After receiving developer instructions for a new phase, call this tool to acknowledge receipt and signal readiness. \
                Proceeed to steps in interview when tool response is received.
                RETURNS: { "status": "completed", "content": "I am ready to begin. + {{instructions}}" }
                USAGE: Call this immediately after receiving phase instructions, before attempting any other actions.
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }

}
