//
//  SubmitForValidationTool.swift
//  Sprung
//
//  Submits data for validation by the user.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI
struct SubmitForValidationTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "validation_type": ValidationSchemas.validationType,
            "data": ValidationSchemas.dataPayload,
            "summary": ValidationSchemas.summary
        ]
        return JSONSchema(
            type: .object,
            description: """
                Present FINAL APPROVAL card in the tool pane for user confirmation of collected data.
                PURPOSE: This is the FINAL confirmation step that blocks other tools and presents approval UI. \
                Only call this AFTER data collection is complete.
                This is the primary confirmation surface for most Phase 1 objectives. \
                Use this at the end of a sub-phase to get user sign-off before persisting data.
                RETURNS: { "message": "UI presented. Awaiting user input.", "status": "completed" }
                The tool completes immediately after presenting UI. User validation response arrives as a new user message.
                USAGE: Call at sub-phase boundaries to confirm collected data before persisting. \
                This BLOCKS non-timeline tools until user responds.
                WORKFLOW:
                1. Collect data for a sub-phase (e.g., after user finishes editing timeline cards)
                2. Call submit_for_validation with validation_type, data, and summary
                3. Tool returns immediately - validation card is now active (approval UI shown)
                4. User reviews and responds in one of three ways:
                   a) Clicks "Confirm" - Data is finalized, you receive "Validation response: confirmed"
                   b) Clicks "Reject" - Data is rejected, you receive "Validation response: rejected"
                   c) Makes edits and clicks "Submit Changes Only" - Validation prompt closes, \
                   you receive message explaining changes were made
                5. If user submits changes during validation, reassess the updated data, ask clarifying questions if needed, \
                then call submit_for_validation again when ready
                6. If confirmed, mark objective complete
                USER CAN EDIT DURING VALIDATION (skeleton_timeline only):
                For timeline validation, the user sees timeline cards and can make edits. If they do:
                - They can click "Submit Changes Only" to save changes and return to chat for your reassessment
                - OR click "Confirm with Changes" to finalize the timeline with their edits
                When user submits changes only, you'll receive: "User made changes to the timeline cards and submitted them for review. \
                Please reassess the updated timeline, ask any clarifying questions if needed, or submit for validation again when ready."
                This is NORMAL workflow - acknowledge their changes, discuss if needed, then re-submit for final validation.
                Phase 1 validation_types:
                - applicant_profile: Contact info validation (no editing during validation)
                - skeleton_timeline: Timeline cards final approval with optional editing. Data is auto-fetched from current timeline state.
                - enabled_sections: Resume sections confirmation (no editing during validation)
                Phase 2 validation_types:
                - knowledge_card: Knowledge card approval
                Phase 3 validation_types:
                - candidate_dossier: Final dossier review with writing samples, knowledge cards, and profile summary
                IMPORTANT FOR TIMELINE: Call display_timeline_entries_for_review FIRST (opens editor), let user edit/save, \
                THEN call submit_for_validation(validation_type="skeleton_timeline", summary="...", data={}) for final approval. \
                The current timeline data will be automatically retrieved.
                DO NOT: Re-validate already confirmed data unless new information is introduced. \
                Once meta.validation_state = "user_validated", trust it.
                """,
            properties: properties,
            required: ["validation_type", "data", "summary"]
        )
    }()
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.submitForValidation.rawValue }
    var description: String {
        """
        Present FINAL APPROVAL card with Confirm/Reject buttons. \
        Blocks tools until user responds. Call at end of sub-phase after data collection complete.
        """
    }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        var payload = try ValidationPayload(json: params)
        // Auto-fetch current data from coordinator for certain validation types
        if payload.validationType == OnboardingDataType.skeletonTimeline.rawValue {
            // Use the coordinator's current skeleton timeline as the data payload
            let currentTimeline = await MainActor.run {
                coordinator.ui.skeletonTimeline ?? JSON()
            }
            payload = ValidationPayload(
                validationType: payload.validationType,
                data: currentTimeline,
                summary: payload.summary
            )
        } else if payload.validationType == OnboardingDataType.experienceDefaults.rawValue {
            // Use the coordinator's current ExperienceDefaultsDraft as the data payload.
            // Data is optional for this type; we always auto-fetch to ensure consistency.
            let currentDefaults = await coordinator.currentExperienceDefaultsForValidation()
            payload = ValidationPayload(
                validationType: payload.validationType,
                data: currentDefaults,
                summary: payload.summary
            )
        }
        // Emit UI request to show the validation prompt
        await coordinator.eventBus.publish(.validationPromptRequested(prompt: payload.toValidationPrompt()))
        // Codex paradigm: Return pending - don't send tool response until user acts.
        // The tool output will be sent when user confirms/rejects validation.
        return .pendingUserAction
    }
}
private struct ValidationPayload {
    let validationType: String
    let data: JSON
    let summary: String
    init(json: JSON) throws {
        guard let type = json["validation_type"].string, !type.isEmpty else {
            throw ToolError.invalidParameters("validation_type must be provided")
        }
        let validTypes: [OnboardingDataType] = [.applicantProfile, .skeletonTimeline, .enabledSections, .knowledgeCard, .candidateDossier, .experienceDefaults]
        let validTypeStrings = validTypes.map(\.rawValue)
        guard validTypeStrings.contains(type) else {
            throw ToolError.invalidParameters("validation_type must be one of: \(validTypeStrings.joined(separator: ", "))")
        }
        self.validationType = type
        // For skeleton_timeline, data is optional (will be auto-fetched from coordinator)
        // For experience_defaults, data may be empty (auto-fetched from ExperienceDefaultsStore)
        // For other types, data must be provided
        if type == OnboardingDataType.skeletonTimeline.rawValue || type == OnboardingDataType.experienceDefaults.rawValue {
            self.data = json["data"]
        } else {
            guard let data = json["data"].dictionary, !data.isEmpty else {
                throw ToolError.invalidParameters("Missing required 'data' parameter. For \(type) validation, you must include the complete data object to validate. Example: {\"validation_type\": \"\(type)\", \"data\": {...your content...}, \"summary\": \"...\"}")
            }
            self.data = json["data"]
        }
        guard let summary = json["summary"].string, !summary.isEmpty else {
            throw ToolError.invalidParameters("summary must be provided")
        }
        self.summary = summary
    }
    // Direct initializer for creating payload with explicit values
    init(validationType: String, data: JSON, summary: String) {
        self.validationType = validationType
        self.data = data
        self.summary = summary
    }
    func toValidationPrompt() -> OnboardingValidationPrompt {
        OnboardingValidationPrompt(
            dataType: validationType,
            payload: data,
            message: summary
        )
    }
}
