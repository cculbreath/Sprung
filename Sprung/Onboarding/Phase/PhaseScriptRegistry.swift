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
            .phase1CoreFacts: PhaseOneScript(),
            .phase2DeepDive: PhaseTwoScript(),
            .phase3WritingCorpus: PhaseThreeScript()
        ]
    }

    // MARK: - Public API
    /// Returns the script for the given phase.
    func script(for phase: InterviewPhase) -> PhaseScript? {
        scripts[phase]
    }

    /// Returns the script for the current phase.
    func currentScript(for phase: InterviewPhase) -> PhaseScript? {
        script(for: phase)
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
        switch currentPhase {
        case .phase1CoreFacts:
            return .phase2DeepDive
        case .phase2DeepDive:
            return .phase3WritingCorpus
        case .phase3WritingCorpus:
            return .complete
        case .complete:
            return nil
        }
    }

    /// Validates whether the current phase can transition to the next phase.
    /// Returns a validation result indicating success or the reason for failure.
    func validateTransition(
        from currentPhase: InterviewPhase,
        coordinator: OnboardingInterviewCoordinator,
        dataStore: InterviewDataStore,
        confirmSkip: Bool
    ) async -> PhaseTransitionValidation {
        switch currentPhase {
        case .phase1CoreFacts:
            return await validatePhaseOneToTwo(coordinator: coordinator)
        case .phase2DeepDive:
            return await validatePhaseTwoToThree(
                dataStore: dataStore,
                confirmSkip: confirmSkip
            )
        case .phase3WritingCorpus:
            return await validatePhaseThreeToComplete(dataStore: dataStore)
        case .complete:
            return .alreadyComplete
        }
    }

    // MARK: - Private Validation Methods
    private func validatePhaseOneToTwo(
        coordinator: OnboardingInterviewCoordinator
    ) async -> PhaseTransitionValidation {
        // VALIDATION: skeleton_timeline MUST have at least one entry before Phase 2
        let timeline = coordinator.ui.skeletonTimeline
        let experiences = timeline?["experiences"].array ?? []

        if experiences.isEmpty {
            Logger.warning("⚠️ next_phase blocked: skeleton_timeline is empty", category: .ai)
            return .blocked(
                reason: "missing_skeleton_timeline",
                message: """
                    Cannot advance to Phase 2: No timeline entries exist. \
                    You must create skeleton timeline cards from the user's resume or work history before proceeding. \
                    Use create_timeline_card to add work experience, education, and other entries. \
                    If user uploaded a resume, extract the positions and create cards for each.
                    """
            )
        }

        Logger.info("✅ skeleton_timeline validated (\(experiences.count) entries) for Phase 1 → Phase 2", category: .ai)
        return .allowed
    }

    private func validatePhaseTwoToThree(
        dataStore: InterviewDataStore,
        confirmSkip: Bool
    ) async -> PhaseTransitionValidation {
        // VALIDATION: Warn if no evidence documents were uploaded
        let artifacts = await dataStore.list(dataType: "artifact")
        let knowledgeCards = await dataStore.list(dataType: "knowledge_card")

        if artifacts.isEmpty && knowledgeCards.isEmpty {
            Logger.warning("⚠️ next_phase warning: no evidence documents or knowledge cards", category: .ai)

            if !confirmSkip {
                return .requiresConfirmation(
                    warning: "no_evidence_collected",
                    message: """
                        No evidence documents were uploaded and no knowledge cards were generated. \
                        This will result in generic resume content without specific achievements. \
                        Are you sure you want to proceed to Phase 3? If so, call next_phase again with \
                        confirm_skip=true. Otherwise, use open_document_collection to upload evidence.
                        """
                )
            }

            Logger.info("✅ User confirmed skip to Phase 3 without evidence", category: .ai)
        }

        return .allowed
    }

    private func validatePhaseThreeToComplete(
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

        Logger.info("✅ experience_defaults validated for Phase 3 → Complete transition", category: .ai)
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
