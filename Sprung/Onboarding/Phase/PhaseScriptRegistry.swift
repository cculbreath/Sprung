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

    /// Returns the base system prompt text for the interview.
    /// Phase-specific instructions are sent as user messages with <coordinator> tags.
    func buildSystemPrompt(for phase: InterviewPhase) -> String {
        Self.baseSystemPrompt()
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
        // VALIDATION 1: skeleton_timeline MUST have at least one entry before Phase 3
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

        // VALIDATION 2: skeleton_timeline MUST be validated (user clicked "Done with Timeline")
        let timelineStatus = coordinator.ui.objectiveStatuses[OnboardingObjectiveId.skeletonTimelineComplete.rawValue]
        if timelineStatus != "completed" {
            Logger.warning("⚠️ next_phase blocked: skeleton_timeline not validated", category: .ai)
            return .blocked(
                reason: "timeline_not_validated",
                message: """
                    Cannot advance to Phase 3: The skeleton timeline has not been validated. \
                    The user must review and approve the timeline entries before proceeding. \
                    Use submit_for_validation with validation_type="skeleton_timeline" to request user approval. \
                    After user approves, the objective status will be set to "completed" and you can call next_phase.
                    """
            )
        }

        // VALIDATION 3: enabled_sections MUST be configured before Phase 3
        let sectionsStatus = coordinator.ui.objectiveStatuses[OnboardingObjectiveId.enabledSections.rawValue]
        if sectionsStatus != "completed" {
            Logger.warning("⚠️ next_phase blocked: enabled_sections not configured", category: .ai)
            return .blocked(
                reason: "sections_not_configured",
                message: """
                    Cannot advance to Phase 3: Resume sections have not been configured. \
                    Call configure_enabled_sections to let the user choose which resume sections to include \
                    (e.g., work, education, skills, projects). Base your recommendations on their timeline. \
                    After user confirms, you can call next_phase to proceed to evidence collection.
                    """
            )
        }

        // VALIDATION 4: If non-chronological sections are enabled, they must be collected
        let enabledSections = await coordinator.state.artifacts.enabledSections
        let nonChronologicalSections: Set<String> = ["awards", "publications", "languages", "references"]
        let enabledNonChronological = enabledSections.intersection(nonChronologicalSections)

        if !enabledNonChronological.isEmpty {
            let sectionCardsStatus = coordinator.ui.objectiveStatuses[OnboardingObjectiveId.sectionCardsComplete.rawValue]
            if sectionCardsStatus != "completed" {
                let sectionList = enabledNonChronological.sorted().joined(separator: ", ")
                Logger.warning("⚠️ next_phase blocked: section cards not collected for: \(sectionList)", category: .ai)

                // Build specific instructions for each enabled section
                var instructions: [String] = []
                if enabledNonChronological.contains("publications") {
                    instructions.append("• publications: offer CV/BibTeX upload via get_user_upload(upload_type='cv'), or use create_publication_card for each publication")
                }
                if enabledNonChronological.contains("awards") {
                    instructions.append("• awards: use create_section_card(sectionType='award') for each award/honor")
                }
                if enabledNonChronological.contains("languages") {
                    instructions.append("• languages: use create_section_card(sectionType='language') for each language")
                }
                if enabledNonChronological.contains("references") {
                    instructions.append("• references: use create_section_card(sectionType='reference') for each reference")
                }
                let instructionText = instructions.joined(separator: "\n")

                return .blocked(
                    reason: "section_cards_incomplete",
                    message: """
                        Cannot advance to Phase 3: Section cards have not been collected for enabled sections.

                        ENABLED NON-CHRONOLOGICAL SECTIONS: \(sectionList)

                        REQUIRED ACTIONS:
                        \(instructionText)

                        AFTER COLLECTING:
                        1. Call display_section_cards_for_review to show the section cards editor
                        2. Call submit_for_validation(validation_type='section_cards') for user approval
                        3. Once approved, call next_phase to proceed
                        """
                )
            }
        }

        Logger.info("✅ Phase 2→3 validated: \(experiences.count) timeline entries, sections configured", category: .ai)
        return .allowed
    }

    /// Phase 3 → Phase 4: Validate evidence collection before strategic synthesis
    private func validatePhaseThreeToFour(
        coordinator: OnboardingInterviewCoordinator,
        userApprovedSkip: Bool
    ) async -> PhaseTransitionValidation {
        // VALIDATION 1: Block if card merge is still in progress
        let isMerging = await MainActor.run { coordinator.ui.isMergingCards }
        if isMerging {
            Logger.warning("⚠️ next_phase blocked: card merge still in progress", category: .ai)
            return .blocked(
                reason: "card_merge_in_progress",
                message: """
                    Cannot advance to Phase 4: Knowledge card merging is still in progress. \
                    Please wait for the merge operation to complete before calling next_phase. \
                    The system will notify you when cards are ready for review.
                    """
            )
        }

        // VALIDATION 2: Block if skills processing or ATS expansion agents are still running
        let runningAgentTypes: Set<AgentType> = [.skillsProcessing, .atsExpansion, .cardMerge, .backgroundMerge]
        let runningAgents = await MainActor.run {
            coordinator.agentActivityTracker.runningAgents.filter { runningAgentTypes.contains($0.agentType) }
        }
        if !runningAgents.isEmpty {
            let agentNames = runningAgents.map { $0.agentType.displayName }.joined(separator: ", ")
            Logger.warning("⚠️ next_phase blocked: agents still running (\(agentNames))", category: .ai)
            return .blocked(
                reason: "agents_still_running",
                message: """
                    Cannot advance to Phase 4: Background agents are still processing. \
                    Running agents: \(agentNames). \
                    Please wait for all card merge and skills processing to complete before calling next_phase.
                    """
            )
        }

        // VALIDATION 3: Block if cards are awaiting user approval
        let awaitingApproval = await MainActor.run { coordinator.ui.cardAssignmentsReadyForApproval }
        if awaitingApproval {
            Logger.warning("⚠️ next_phase blocked: cards awaiting user approval", category: .ai)
            return .blocked(
                reason: "awaiting_card_approval",
                message: """
                    Cannot advance to Phase 4: Knowledge cards are ready but awaiting user approval. \
                    The user must review the proposed cards and click "Approve & Create Cards" before proceeding. \
                    Tell the user to review the cards in the tool pane and approve them when ready.
                    """
            )
        }

        // VALIDATION 4: Require knowledge cards OR explicit user approval
        // Having uploaded artifacts is NOT sufficient - KC generation must succeed
        // Query KnowledgeCardStore (SwiftData) for onboarding knowledge cards - this is the authoritative source
        let knowledgeCards = await MainActor.run {
            coordinator.getKnowledgeCardStore().onboardingCards
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
        // NOTE: experience_defaults generation moved to SGM (Seed Generation Module)
        // which is presented after Phase 4 completes. No validation needed here.
        Logger.info("✅ Phase 4→Complete validated: ready for SGM", category: .ai)
        return .allowed
    }
    // MARK: - Base System Prompt
    private static func baseSystemPrompt() -> String {
        PromptLibrary.interviewBaseSystem
    }
}
