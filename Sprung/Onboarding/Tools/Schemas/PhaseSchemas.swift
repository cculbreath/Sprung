//
//  PhaseSchemas.swift
//  Sprung
//
//  Shared JSON schema definitions for phase management and objective tools.
//  DRY: Used by NextPhaseTool, SetObjectiveStatusTool, StartPhaseTwoTool, StartPhaseThreeTool, and AgentReadyTool.
//
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Shared schema definitions for phase management and objective tracking
enum PhaseSchemas {
    /// Schema for objective status updates
    /// Used by SetObjectiveStatusTool
    static func objectiveStatusSchema() -> JSONSchema {
        JSONSchema(
            type: .object,
            description: """
                Update the internal status of an onboarding objective (pending, in_progress, completed, skipped).
                Use this to signal workflow progress to the coordinator. The coordinator uses these status updates to manage phase transitions, trigger objective workflows, and maintain the ledger.
                RETURNS: { "objective_id": "<id>", "status": "<status>", "updated": true }
                CRITICAL CONSTRAINT: This tool must be called ALONE without any assistant message in the same turn. Status updates are atomic, fire-and-forget operations.
                USAGE:
                - Mark objectives "in_progress" when starting work
                - Mark "completed" when finished (coordinator may auto-complete parent objectives)
                - Mark "skipped" when user declines optional steps
                - Do NOT communicate status changes to user in chat - these are silent background operations
                WORKFLOW: Tool responses are for internal tracking only. The coordinator sends developer messages when objectives complete; you don't need to echo status changes.
                """,
            properties: [
                "objective_id": objectiveIdField(),
                "status": objectiveStatusField(),
                "notes": JSONSchema(
                    type: .string,
                    description: "Optional notes about this status change for debugging/logging."
                ),
                "details": JSONSchema(
                    type: .object,
                    description: "Optional string key-value pairs with context (e.g., source='manual', mode='skip', artifact_id='123').",
                    additionalProperties: true
                )
            ],
            required: ["objective_id", "status"],
            additionalProperties: false
        )
    }

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

    /// Schema for Phase 2 bootstrap tool
    /// Used by StartPhaseTwoTool
    static func startPhaseTwoSchema() -> JSONSchema {
        JSONSchema(
            type: .object,
            description: """
                Bootstrap tool for Phase 2. Call this FIRST after receiving Phase 2 instructions.
                RETURNS: Timeline entries from Phase 1 + explicit instructions for knowledge card generation.
                IMPORTANT: After receiving this tool's response, you MUST call open_document_collection.
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }

    /// Schema for Phase 3 bootstrap tool
    /// Used by StartPhaseThreeTool
    static func startPhaseThreeSchema() -> JSONSchema {
        JSONSchema(
            type: .object,
            description: """
                Bootstrap tool for Phase 3. Call this FIRST after receiving Phase 3 instructions.
                RETURNS: Knowledge cards from Phase 2, applicant profile, and instructions for writing corpus collection.
                After receiving this tool's response, begin collecting writing samples and finalizing the dossier.
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

    // MARK: - Field Schemas

    /// Objective ID field with all valid Phase 1 objective identifiers
    static func objectiveIdField() -> JSONSchema {
        JSONSchema(
            type: .string,
            description: "Identifier of the objective to update. Must match Phase 1 objective namespace.",
            enum: [
                // Top-level Phase 1 objectives
                "applicant_profile",
                "skeleton_timeline",
                "enabled_sections",
                "dossier_seed",
                // Applicant profile sub-objectives
                "contact_source_selected",
                "contact_data_collected",
                "contact_data_validated",
                "contact_photo_collected",
                "applicant_profile.contact_intake",
                "applicant_profile.contact_intake.activate_card",
                "applicant_profile.contact_intake.persisted",
                "applicant_profile.profile_photo",
                "applicant_profile.profile_photo.retrieve_profile",
                "applicant_profile.profile_photo.evaluate_need",
                "applicant_profile.profile_photo.collect_upload",
                // Skeleton timeline sub-objectives
                "skeleton_timeline.intake_artifacts",
                "skeleton_timeline.timeline_editor",
                "skeleton_timeline.context_interview",
                "skeleton_timeline.completeness_signal"
            ]
        )
    }

    /// Objective status field with valid status values
    static func objectiveStatusField() -> JSONSchema {
        JSONSchema(
            type: .string,
            description: "Desired status for this objective.",
            enum: ["pending", "in_progress", "completed", "skipped"]
        )
    }
}
