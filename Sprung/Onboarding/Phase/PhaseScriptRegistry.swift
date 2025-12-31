//
//  PhaseScriptRegistry.swift
//  Sprung
//
//  Registry for phase scripts, providing access to phase-specific behavior.
//
import Foundation
import SwiftyJSON

/// Result of validating a phase transition.
enum PhaseTransitionValidation {
    case allowed
    case blocked(reason: String, message: String)
    case requiresConfirmation(warning: String, message: String)
    case alreadyComplete
}

@MainActor
final class PhaseScriptRegistry {
    // MARK: - Properties
    private let scripts: [InterviewPhase: PhaseScript]

    // MARK: - Init
    init() {
        self.scripts = [
            .phase1VoiceContext: PhaseOneScript(),
            .phase2CareerStory: PhaseTwoScript(),
            .phase3EvidenceCollection: PhaseThreeScript(),
            .phase4StrategicSynthesis: PhaseFourScript()
        ]
    }

    // MARK: - Public API
    /// Returns the script for the given phase.
    func script(for phase: InterviewPhase) -> PhaseScript? {
        scripts[phase]
    }

    /// Returns the base developer message text (sent once on first request, persists via previous_response_id).
    /// Phase introductory prompts are sent as additional developer messages at phase start.
    func buildSystemPrompt(for phase: InterviewPhase) -> String {
        Self.baseDeveloperMessage()
    }

    // MARK: - Phase Transitions
    /// Determines the next phase after the given phase.
    /// Returns nil if already at the final phase.
    func nextPhase(after currentPhase: InterviewPhase) -> InterviewPhase? {
        // Delegate to InterviewPhase.next() for consistency
        currentPhase.next()
    }

    /// Validates whether the current phase can transition to the next phase.
    /// Returns a validation result indicating success or the reason for failure.
    func validateTransition(
        from currentPhase: InterviewPhase,
        coordinator: OnboardingInterviewCoordinator,
        dataStore: InterviewDataStore
    ) async -> PhaseTransitionValidation {
        switch currentPhase {
        case .phase1VoiceContext:
            return await validatePhaseOneToTwo(coordinator: coordinator)
        case .phase2CareerStory:
            return await validatePhaseTwoToThree(coordinator: coordinator)
        case .phase3EvidenceCollection:
            // Check user approval flag from StateCoordinator
            let userApproved = await coordinator.state.userApprovedKCSkip
            return await validatePhaseThreeToFour(
                coordinator: coordinator,
                userApprovedSkip: userApproved
            )
        case .phase4StrategicSynthesis:
            return await validatePhaseFourToComplete(dataStore: dataStore)
        case .complete:
            return .alreadyComplete
        }
    }

    // MARK: - Private Validation Methods

    /// Phase 1 → Phase 2: Validate voice/context collection before career story
    private func validatePhaseOneToTwo(
        coordinator: OnboardingInterviewCoordinator
    ) async -> PhaseTransitionValidation {
        // VALIDATION: Applicant profile MUST be validated before Phase 2
        // Writing samples are encouraged but not required (can continue to develop voice later)
        let artifacts = await coordinator.state.artifacts
        let profile = artifacts.applicantProfile

        // Check if profile has basic required fields
        let hasName = !(profile?["name"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasEmail = !(profile?["email"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        if !hasName || !hasEmail {
            Logger.warning("⚠️ next_phase blocked: applicant profile incomplete", category: .ai)
            return .blocked(
                reason: "missing_applicant_profile",
                message: """
                    Cannot advance to Phase 2: Applicant profile is incomplete. \
                    At minimum, collect name and email before proceeding. \
                    Use validate_applicant_profile to confirm the profile is ready.
                    """
            )
        }

        Logger.info("✅ Phase 1→2 validated: profile complete", category: .ai)
        return .allowed
    }

    /// Phase 2 → Phase 3: Validate career story before evidence collection
    private func validatePhaseTwoToThree(
        coordinator: OnboardingInterviewCoordinator
    ) async -> PhaseTransitionValidation {
        // VALIDATION: skeleton_timeline MUST have at least one entry before Phase 3
        let timeline = coordinator.ui.skeletonTimeline
        let experiences = timeline?["experiences"].array ?? []

        if experiences.isEmpty {
            Logger.warning("⚠️ next_phase blocked: skeleton_timeline is empty", category: .ai)
            return .blocked(
                reason: "missing_skeleton_timeline",
                message: """
                    Cannot advance to Phase 3: No timeline entries exist. \
                    You must create skeleton timeline cards from the user's resume or work history before proceeding. \
                    Use create_timeline_card to add work experience, education, and other entries. \
                    If user uploaded a resume, extract the positions and create cards for each.
                    """
            )
        }

        Logger.info("✅ Phase 2→3 validated: \(experiences.count) timeline entries exist", category: .ai)
        return .allowed
    }

    /// Phase 3 → Phase 4: Validate evidence collection before strategic synthesis
    private func validatePhaseThreeToFour(
        coordinator: OnboardingInterviewCoordinator,
        userApprovedSkip: Bool
    ) async -> PhaseTransitionValidation {
        // VALIDATION: Require knowledge cards OR explicit user approval
        // Having uploaded artifacts is NOT sufficient - KC generation must succeed
        // Query ResRefStore (SwiftData) for onboarding knowledge cards - this is the authoritative source
        let knowledgeCards = await MainActor.run {
            coordinator.getResRefStore().resRefs.filter { $0.isFromOnboarding }
        }

        if knowledgeCards.isEmpty {
            // If user has explicitly approved skipping via UI, allow it
            if userApprovedSkip {
                Logger.info("✅ User approved skip to Phase 4 without knowledge cards (via UI)", category: .ai)
                return .allowed
            }

            Logger.warning("⚠️ next_phase blocked: no knowledge cards generated", category: .ai)

            // BLOCKED: Require knowledge cards or explicit user approval via UI
            return .blocked(
                reason: "no_knowledge_cards",
                message: """
                    Cannot advance to Phase 4: No knowledge cards were generated. \
                    Knowledge cards are required to create tailored resume content.

                    OPTIONS:
                    1. Ask the user to upload more documents and click "Generate Cards" to retry
                    2. Use submit_for_validation with validation_type="skip_kc_approval" to ask user \
                       if they want to proceed without knowledge cards

                    The user must explicitly approve via the UI before phase advance is allowed.
                    """
            )
        }

        Logger.info("✅ Phase 3→4 validated: \(knowledgeCards.count) knowledge cards exist", category: .ai)
        return .allowed
    }

    /// Phase 4 → Complete: Validate strategic synthesis before completing interview
    private func validatePhaseFourToComplete(
        dataStore: InterviewDataStore
    ) async -> PhaseTransitionValidation {
        // VALIDATION: experience_defaults MUST be persisted before completing the interview
        let experienceDefaults = await dataStore.list(dataType: "experience_defaults")

        if experienceDefaults.isEmpty {
            Logger.warning("⚠️ next_phase blocked: experience_defaults not persisted", category: .ai)
            return .blocked(
                reason: "missing_experience_defaults",
                message: """
                    Cannot complete interview: experience_defaults have not been persisted.
                    You MUST call submit_experience_defaults (or persist_data) before calling next_phase.
                    Use the knowledge cards and skeleton timeline to generate structured resume data with:
                    - work: Array of work experience entries from timeline
                    - education: Array of education entries from timeline
                    - projects: Array of project entries (if any)
                    - skills: Array of skill categories extracted from knowledge cards
                    Example: submit_experience_defaults({"work": [...], "education": [...], "skills": [...]})
                    """
            )
        }

        Logger.info("✅ Phase 4→Complete validated: experience_defaults persisted", category: .ai)
        return .allowed
    }
    // MARK: - Base Developer Message
    private static func baseDeveloperMessage() -> String {
        """
        You are the Sprung onboarding interviewer—a concise, friendly guide helping users build career profiles for resume generation.

        ## Personality
        - Concise, direct, and friendly
        - Keep users informed with brief updates
        - Collaborative tone; avoid excessive formality

        ## Response Style
        - Skip stock phrases ("Got it!", "Sure!", "Absolutely!", "Great question!")
        - Don't recap what you're about to do—just do it
        - Don't repeat back what the user just said
        - For conceptual questions, use knowledge—don't make unnecessary tool calls

        ## Action Bias
        - If user intent is ambiguous but reasonable, proceed with the most likely interpretation
        - Only ask clarifying questions when the answer materially affects the outcome
        - Prefer action over confirmation for routine operations

        ## Preamble Messages
        ALWAYS output assistant text BEFORE making tool calls. Never call a tool without first writing a brief preamble.
        - Keep preambles to 1-2 sentences (8-12 words for quick updates)
        - Build on prior context to create momentum
        - For your FIRST tool call: include a warm welcome greeting
        Examples: "Welcome! Let me open your profile card." • "Great, now I'll check about adding a photo." • "Opening the timeline editor."

        ## Message Types
        - `assistant`: Shown directly to user in chatbox
        - `user`: User messages wrapped in <chatbox>tags</chatbox>; system messages have no tags
        - `developer`: Coordinator instructions (not shown to user)—follow immediately

        ## Tool Pane
        UI tools present cards: get_applicant_profile, get_user_upload, get_user_option, submit_for_validation, configure_enabled_sections, display_timeline_entries_for_review
        Cards dismiss when user completes action.

        ## Workflow
        - Interview organized into Phases with objectives
        - Coordinator tracks objective status via developer messages
        - Follow developer instructions without debate
        - Don't re-validate data the user has already approved
        - Use submit_for_validation for final confirmations

        ## Tool Constraints
        - set_objective_status is ATOMIC: call it alone with NO assistant message
        - Only call currently-allowed tools; others are rejected

        ## Artifacts
        Uploads produce artifact records. Use list_artifacts, get_artifact, request_raw_file to query them.
        """
    }
}
