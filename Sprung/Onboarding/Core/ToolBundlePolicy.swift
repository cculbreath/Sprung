//
//  ToolBundlePolicy.swift
//  Sprung
//
//  Dynamic tool bundling policy using subphase-aware selection.
//  Part of Milestone 3: Dynamic tool bundling
//

import Foundation
import SwiftOpenAI

/// Policy for selecting minimal tool sets per request based on interview subphase
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
        OnboardingToolName.getContextPack.rawValue,
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
            // Allow model to progress itself and dispatch agents once docs are ready
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.dispatchKCAgents.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p2_documentCollection: [
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            // NOTE: scanGitRepo removed - it's triggered by UI button, not LLM
            OnboardingToolName.openDocumentCollection.rawValue,
            // Card merge is now triggered by "Done with Uploads" button, not LLM tool
            OnboardingToolName.dispatchKCAgents.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p2_cardAssignment: [
            OnboardingToolName.getUserOption.rawValue,
            // Fallback: allow manual KC creation if an agent fails
            OnboardingToolName.submitKnowledgeCard.rawValue,
            // Progression: after assignment, model dispatches agents
            OnboardingToolName.dispatchKCAgents.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],
        .p2_userApprovalWait: [
            OnboardingToolName.getUserOption.rawValue,
            // Fallback: allow manual KC creation if an agent fails
            OnboardingToolName.submitKnowledgeCard.rawValue,
            // Progression: after approval, model dispatches agents
            OnboardingToolName.dispatchKCAgents.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],
        .p2_kcGeneration: [
            OnboardingToolName.dispatchKCAgents.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            // Cards are auto-presented for validation - no submit_knowledge_card needed
            // Keep submitKnowledgeCard available for manual card creation (edge case)
            OnboardingToolName.submitKnowledgeCard.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p2_cardSubmission: [
            // Keep for manual card creation (LLM crafts card without agent)
            OnboardingToolName.submitKnowledgeCard.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p2_phaseTransition: [
            OnboardingToolName.nextPhase.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            // Fallback: keep manual KC tool available if dispatch had failures
            OnboardingToolName.submitKnowledgeCard.rawValue
        ],

        // MARK: Phase 3 Subphases (all include artifact access)
        .p3_bootstrap: [
            OnboardingToolName.startPhaseThree.rawValue,
            // Progression: after bootstrap, model collects writing samples
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.ingestWritingSample.rawValue
        ],
        .p3_writingCollection: [
            OnboardingToolName.ingestWritingSample.rawValue,
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            // Progression: after collection, model compiles dossier
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.submitExperienceDefaults.rawValue
        ],
        .p3_sampleReview: [
            OnboardingToolName.ingestWritingSample.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            // Progression: after review, model compiles dossier
            OnboardingToolName.submitExperienceDefaults.rawValue,
            OnboardingToolName.submitCandidateDossier.rawValue
        ],
        .p3_dossierCompilation: [
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

    /// Select tool bundle based on subphase
    /// - Parameters:
    ///   - subphase: The current interview subphase
    ///   - allowedTools: The full set of allowed tools for this phase
    ///   - toolChoice: Optional tool choice override
    /// - Returns: Filtered set of tool names to include
    static func selectBundleForSubphase(
        _ subphase: InterviewSubphase,
        allowedTools: Set<String>,
        toolChoice: ToolChoiceMode? = nil
    ) -> Set<String> {
        // Handle toolChoice overrides
        // CRITICAL: When forcing a specific tool, that tool MUST be included regardless of
        // whether allowedTools is populated. On the first request, allowedTools may be empty
        // because the event system hasn't processed yet. The OpenAI API requires the forced
        // tool to be present in the tools array.
        if let choice = toolChoice {
            switch choice {
            case .none:
                return []
            case .functionTool(let ft):
                // Always include the forced tool - this is required by OpenAI API
                var bundle: Set<String> = [ft.name]
                // Add safe escape tools that are in allowedTools
                bundle.formUnion(safeEscapeTools.intersection(allowedTools))
                // Include artifact access in Phase 2-3 even when forcing a tool
                if subphase.phase != .phase1CoreFacts {
                    bundle.formUnion(artifactAccessTools.intersection(allowedTools))
                }
                return bundle
            case .customTool(let ct):
                // Always include the forced tool - this is required by OpenAI API
                var bundle: Set<String> = [ct.name]
                bundle.formUnion(safeEscapeTools.intersection(allowedTools))
                if subphase.phase != .phase1CoreFacts {
                    bundle.formUnion(artifactAccessTools.intersection(allowedTools))
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

        // Intersect with allowed tools
        return bundle.intersection(allowedTools)
    }
}
