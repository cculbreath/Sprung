//
//  ToolBundlePolicy.swift
//  Sprung
//
//  SINGLE SOURCE OF TRUTH for tool availability in the onboarding interview.
//
//  ## Architecture
//
//  This file defines which tools are available at each point in the interview.
//  There is ONE place to update when adding or changing tool availability:
//  the `subphaseBundles` dictionary below.
//
//  ## How It Works
//
//  1. **Subphase Bundles** (`subphaseBundles`): Define which tools are available
//     for each fine-grained interview subphase (e.g., p1_profileIntake, p3_dossierCompilation)
//
//  2. **Phase-Level Permissions**: Automatically derived by `allowedToolsForPhase()`,
//     which unions all subphase bundles for that phase. Used for tool execution validation.
//
//  3. **Request-Time Selection**: `selectBundleForSubphase()` determines which tools
//     to send in each API request based on current UI state and objectives.
//
//  ## Adding a New Tool
//
//  1. Register the tool in `OnboardingToolRegistrar.registerTools()`
//  2. Add the tool to relevant subphase bundles in `subphaseBundles` below
//  3. That's it! Phase-level permissions are derived automatically.
//
//  ## Special Tool Sets
//
//  - `safeEscapeTools`: Always included (escape hatches for blocked states)
//  - `artifactAccessTools`: Included in Phase 2-3 subphases (document access)
//

import Foundation
import SwiftOpenAI

/// Policy for selecting minimal tool sets per request based on interview subphase.
/// This is the SINGLE SOURCE OF TRUTH for tool availability.
struct ToolBundlePolicy {

    // MARK: - Safe Escape Tools

    /// Minimal set of tools that should always be available (for error recovery)
    /// NOTE: get_user_option removed - it was causing the model to prefer generic tools
    /// over specialized ones. It's now explicitly included only in bundles that need it.
    static let safeEscapeTools: Set<String> = [
        OnboardingToolName.updateDossierNotes.rawValue,  // Scratchpad always available
        OnboardingToolName.askUserSkipToNextPhase.rawValue  // Escape hatch for blocked transitions
    ]

    // MARK: - Artifact Access Tools

    /// Artifact access tools - ALWAYS included in Phase 2-3 subphases
    static let artifactAccessTools: Set<String> = [
        OnboardingToolName.listArtifacts.rawValue,
        OnboardingToolName.getArtifact.rawValue,
        OnboardingToolName.requestRawFile.rawValue,
        OnboardingToolName.createWebArtifact.rawValue  // For saving web_search content
    ]

    // MARK: - Subphase Tool Bundles

    /// Tool bundles for each subphase
    /// Key principle: Artifact access tools are ALWAYS included in Phase 2-3 subphases
    static let subphaseBundles: [InterviewSubphase: Set<String>] = [
        // MARK: Phase 1 Subphases
        .p1_profileIntake: [
            OnboardingToolName.getApplicantProfile.rawValue,
            OnboardingToolName.getUserOption.rawValue,
            OnboardingToolName.getUserUpload.rawValue,  // For contacts import
            OnboardingToolName.validateApplicantProfile.rawValue,
            OnboardingToolName.validatedApplicantProfileData.rawValue,
            OnboardingToolName.createWebArtifact.rawValue  // For saving web_search content from profile URLs
        ],
        .p1_photoCollection: [
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            OnboardingToolName.getUserOption.rawValue,
            // Progression: after photo, model starts timeline
            OnboardingToolName.createTimelineCard.rawValue,
            OnboardingToolName.displayTimelineEntriesForReview.rawValue
        ],
        .p1_resumeUpload: [
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            OnboardingToolName.listArtifacts.rawValue,
            OnboardingToolName.getArtifact.rawValue,
            // Progression: after resume upload, model creates timeline cards
            OnboardingToolName.createTimelineCard.rawValue,
            OnboardingToolName.displayTimelineEntriesForReview.rawValue
        ],
        .p1_timelineEditing: [
            // Resume upload is offered at the START of timeline editing - include upload tools
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            // Timeline card management
            OnboardingToolName.createTimelineCard.rawValue,
            OnboardingToolName.updateTimelineCard.rawValue,
            OnboardingToolName.deleteTimelineCard.rawValue,
            OnboardingToolName.reorderTimelineCards.rawValue,
            OnboardingToolName.getTimelineEntries.rawValue,
            OnboardingToolName.displayTimelineEntriesForReview.rawValue,
            OnboardingToolName.listArtifacts.rawValue,
            OnboardingToolName.getArtifact.rawValue,
            // Progression tools - model needs these to advance the interview
            OnboardingToolName.submitForValidation.rawValue,
            OnboardingToolName.configureEnabledSections.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p1_timelineValidation: [
            OnboardingToolName.submitForValidation.rawValue,
            OnboardingToolName.displayTimelineEntriesForReview.rawValue,
            OnboardingToolName.updateTimelineCard.rawValue,
            OnboardingToolName.deleteTimelineCard.rawValue,
            OnboardingToolName.createTimelineCard.rawValue,
            // Progression tools
            OnboardingToolName.configureEnabledSections.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p1_sectionConfig: [
            // Specialized section config tool
            OnboardingToolName.configureEnabledSections.rawValue,
            // Progression tools
            OnboardingToolName.nextPhase.rawValue
        ],
        .p1_dossierSeed: [
            OnboardingToolName.persistData.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p1_phaseTransition: [
            OnboardingToolName.nextPhase.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],

        // MARK: Phase 2 Subphases (all include artifact access)
        .p2_bootstrap: [
            OnboardingToolName.startPhaseTwo.rawValue,
            // Progression: after bootstrap, model collects documents
            OnboardingToolName.openDocumentCollection.rawValue,
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p2_documentCollection: [
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            OnboardingToolName.openDocumentCollection.rawValue,
            // KC generation is now triggered by UI buttons (Done with Uploads → Generate Cards)
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p2_cardAssignment: [
            OnboardingToolName.getUserOption.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],
        .p2_userApprovalWait: [
            OnboardingToolName.getUserOption.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],
        .p2_kcGeneration: [
            // Card generation handled by UI (Approve & Create button)
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p2_cardSubmission: [
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p2_phaseTransition: [
            OnboardingToolName.nextPhase.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],

        // MARK: Phase 3 Subphases (all include artifact access)
        .p3_bootstrap: [
            OnboardingToolName.startPhaseThree.rawValue,
            // Progression: after bootstrap, model collects writing samples
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.ingestWritingSample.rawValue
        ],
        .p3_writingCollection: [
            OnboardingToolName.getUserOption.rawValue,  // For structured questions about sample types
            OnboardingToolName.ingestWritingSample.rawValue,
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            // Progression: after collection, model compiles dossier
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.submitExperienceDefaults.rawValue
        ],
        .p3_sampleReview: [
            OnboardingToolName.getUserOption.rawValue,  // For structured feedback on samples
            OnboardingToolName.ingestWritingSample.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            // Progression: after review, model compiles dossier
            OnboardingToolName.submitExperienceDefaults.rawValue,
            OnboardingToolName.submitCandidateDossier.rawValue
        ],
        .p3_dossierCompilation: [
            OnboardingToolName.getUserOption.rawValue,  // For structured questions during dossier gathering
            OnboardingToolName.persistData.rawValue,
            OnboardingToolName.submitExperienceDefaults.rawValue,
            OnboardingToolName.submitCandidateDossier.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            // Progression: after compilation, model validates dossier
            OnboardingToolName.submitForValidation.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p3_dossierValidation: [
            OnboardingToolName.persistData.rawValue,
            OnboardingToolName.submitForValidation.rawValue,
            OnboardingToolName.getUserOption.rawValue,
            // Progression: after validation, model submits final data
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.submitCandidateDossier.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p3_dataSubmission: [
            OnboardingToolName.persistData.rawValue,
            OnboardingToolName.submitExperienceDefaults.rawValue,
            OnboardingToolName.submitCandidateDossier.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p3_interviewComplete: [
            OnboardingToolName.persistData.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ]
    ]

    // MARK: - Subphase Inference

    /// Infer the current subphase from objective status and UI state
    /// - Parameters:
    ///   - phase: Current interview phase
    ///   - toolPaneCard: Currently displayed tool pane card
    ///   - objectives: Map of objective ID to status
    /// - Returns: The inferred subphase
    static func inferSubphase(
        phase: InterviewPhase,
        toolPaneCard: OnboardingToolPaneCard,
        objectives: [String: String]
    ) -> InterviewSubphase {
        switch phase {
        case .phase1CoreFacts:
            return inferPhase1Subphase(toolPaneCard: toolPaneCard, objectives: objectives)
        case .phase2DeepDive:
            return inferPhase2Subphase(toolPaneCard: toolPaneCard, objectives: objectives)
        case .phase3WritingCorpus:
            return inferPhase3Subphase(toolPaneCard: toolPaneCard, objectives: objectives)
        case .complete:
            return .p3_interviewComplete
        }
    }

    /// Infer Phase 1 subphase
    private static func inferPhase1Subphase(
        toolPaneCard: OnboardingToolPaneCard,
        objectives: [String: String]
    ) -> InterviewSubphase {
        // UI state takes precedence
        switch toolPaneCard {
        case .applicantProfileRequest, .applicantProfileIntake:
            return .p1_profileIntake
        case .uploadRequest:
            // Check if we're in photo collection or resume upload phase
            if objectives[OnboardingObjectiveId.contactPhotoCollected.rawValue] == "in_progress" {
                return .p1_photoCollection
            }
            if objectives[OnboardingObjectiveId.skeletonTimeline.rawValue] == "in_progress" ||
               objectives[OnboardingObjectiveId.skeletonTimeline.rawValue] == "pending" {
                return .p1_resumeUpload
            }
            return .p1_resumeUpload
        case .editTimelineCards:
            return .p1_timelineEditing
        case .confirmTimelineCards, .validationPrompt:
            return .p1_timelineValidation
        case .sectionToggle:
            return .p1_sectionConfig
        default:
            break
        }

        // Infer from objective state
        let profileStatus = objectives[OnboardingObjectiveId.applicantProfile.rawValue] ?? "pending"
        let photoStatus = objectives[OnboardingObjectiveId.contactPhotoCollected.rawValue] ?? "pending"
        let timelineStatus = objectives[OnboardingObjectiveId.skeletonTimeline.rawValue] ?? "pending"
        let sectionsStatus = objectives[OnboardingObjectiveId.enabledSections.rawValue] ?? "pending"
        let dossierStatus = objectives[OnboardingObjectiveId.dossierSeed.rawValue] ?? "pending"

        // Check profile intake
        if profileStatus == "pending" || profileStatus == "in_progress" {
            if photoStatus == "in_progress" {
                return .p1_photoCollection
            }
            return .p1_profileIntake
        }

        // Check photo collection (after profile but before timeline)
        if photoStatus == "pending" || photoStatus == "in_progress" {
            return .p1_photoCollection
        }

        // Check timeline editing
        if timelineStatus == "pending" || timelineStatus == "in_progress" {
            return .p1_timelineEditing
        }

        // Check section config
        if sectionsStatus == "pending" || sectionsStatus == "in_progress" {
            return .p1_sectionConfig
        }

        // Check dossier seed
        if dossierStatus == "pending" || dossierStatus == "in_progress" {
            return .p1_dossierSeed
        }

        // All complete - ready for transition
        return .p1_phaseTransition
    }

    /// Infer Phase 2 subphase
    private static func inferPhase2Subphase(
        toolPaneCard: OnboardingToolPaneCard,
        objectives: [String: String]
    ) -> InterviewSubphase {
        // UI state takes precedence
        switch toolPaneCard {
        case .uploadRequest:
            return .p2_documentCollection
        case .validationPrompt:
            return .p2_cardAssignment
        case .choicePrompt:
            return .p2_userApprovalWait
        default:
            break
        }

        // Infer from objective state
        // NOTE: Must match ObjectiveStore Phase 2 objectives (interviewed_one_experience, one_card_generated)
        let interviewStatus = objectives[OnboardingObjectiveId.interviewedOneExperience.rawValue] ?? "pending"
        let cardsStatus = objectives[OnboardingObjectiveId.oneCardGenerated.rawValue] ?? "pending"

        // Bootstrap phase (no objectives started)
        if interviewStatus == "pending" && cardsStatus == "pending" {
            return .p2_bootstrap
        }

        // Interview/document collection in progress
        if interviewStatus == "in_progress" {
            // Could be document collection or card assignment
            // Default to document collection if we don't have enough context
            return .p2_documentCollection
        }

        // Interview complete, ready for card generation
        if interviewStatus == "completed" && cardsStatus == "pending" {
            return .p2_kcGeneration
        }

        // Cards generation in progress
        if cardsStatus == "in_progress" {
            return .p2_kcGeneration
        }

        // Cards complete, ready for submission
        if cardsStatus == "completed" {
            return .p2_phaseTransition
        }

        // Default to KC generation if we have documents but interview started
        return .p2_kcGeneration
    }

    /// Infer Phase 3 subphase
    private static func inferPhase3Subphase(
        toolPaneCard: OnboardingToolPaneCard,
        objectives: [String: String]
    ) -> InterviewSubphase {
        // UI state takes precedence
        switch toolPaneCard {
        case .uploadRequest:
            return .p3_writingCollection
        case .validationPrompt:
            return .p3_dossierValidation
        default:
            break
        }

        // Infer from objective state
        let writingStatus = objectives[OnboardingObjectiveId.oneWritingSample.rawValue] ?? "pending"
        let dossierStatus = objectives[OnboardingObjectiveId.dossierComplete.rawValue] ?? "pending"
        let validationStatus = objectives[OnboardingObjectiveId.dossierCompleteValidation.rawValue] ?? "pending"
        let persistedStatus = objectives[OnboardingObjectiveId.dossierCompletePersisted.rawValue] ?? "pending"

        // Bootstrap phase
        if writingStatus == "pending" && dossierStatus == "pending" {
            return .p3_bootstrap
        }

        // Writing sample collection
        if writingStatus == "pending" || writingStatus == "in_progress" {
            return .p3_writingCollection
        }

        // Dossier compilation
        if dossierStatus == "pending" || dossierStatus == "in_progress" {
            if validationStatus == "in_progress" {
                return .p3_dossierValidation
            }
            if persistedStatus == "in_progress" {
                return .p3_dataSubmission
            }
            return .p3_dossierCompilation
        }

        // All complete
        return .p3_interviewComplete
    }

    // MARK: - Bundle Selection

    /// Select tool bundle based on subphase.
    /// Returns the set of tools to send to the LLM for this specific subphase.
    /// - Parameters:
    ///   - subphase: The current interview subphase
    ///   - toolChoice: Optional tool choice override (for forcing a specific tool)
    /// - Returns: Set of tool names to include in the API request
    static func selectBundleForSubphase(
        _ subphase: InterviewSubphase,
        toolChoice: ToolChoiceMode? = nil
    ) -> Set<String> {
        // Handle toolChoice overrides
        // CRITICAL: When forcing a specific tool, that tool MUST be included.
        // The OpenAI API requires the forced tool to be present in the tools array.
        if let choice = toolChoice {
            switch choice {
            case .none:
                return []
            case .functionTool(let ft):
                // Always include the forced tool - this is required by OpenAI API
                var bundle: Set<String> = [ft.name]
                bundle.formUnion(safeEscapeTools)
                if subphase.phase != .phase1CoreFacts {
                    bundle.formUnion(artifactAccessTools)
                }
                return bundle
            case .customTool(let ct):
                // Always include the forced tool - this is required by OpenAI API
                var bundle: Set<String> = [ct.name]
                bundle.formUnion(safeEscapeTools)
                if subphase.phase != .phase1CoreFacts {
                    bundle.formUnion(artifactAccessTools)
                }
                return bundle
            default:
                break
            }
        }

        // Get base bundle for subphase
        var bundle = subphaseBundles[subphase] ?? []

        // Always include safe escape tools
        bundle.formUnion(safeEscapeTools)

        // Include artifact access tools for Phase 2-3 subphases
        if subphase.phase != .phase1CoreFacts {
            bundle.formUnion(artifactAccessTools)
        }

        return bundle
    }

    // MARK: - Phase-Level Tool Permissions

    /// Compute allowed tools for a phase by unioning all subphase bundles.
    /// This is used for tool execution validation (can this tool run in this phase?).
    /// - Parameter phase: The interview phase
    /// - Returns: Set of all tool names permitted in this phase
    static func allowedToolsForPhase(_ phase: InterviewPhase) -> Set<String> {
        var allowed = Set<String>()

        // Union all subphase bundles for this phase
        for (subphase, bundle) in subphaseBundles where subphase.phase == phase {
            allowed.formUnion(bundle)
        }

        // Always include safe escape tools
        allowed.formUnion(safeEscapeTools)

        // Include artifact access tools for Phase 2-3
        if phase != .phase1CoreFacts {
            allowed.formUnion(artifactAccessTools)
        }

        return allowed
    }

    /// Precomputed allowed tools for all phases (for efficient lookup)
    static let allowedToolsByPhase: [InterviewPhase: Set<String>] = {
        var result: [InterviewPhase: Set<String>] = [:]
        for phase in InterviewPhase.allCases {
            result[phase] = allowedToolsForPhase(phase)
        }
        return result
    }()
}
