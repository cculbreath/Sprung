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
    static let safeEscapeTools: Set<String> = [
        OnboardingToolName.getUserOption.rawValue
    ]

    // MARK: - Artifact Access Tools

    /// Artifact access tools - ALWAYS included in Phase 2-3 subphases
    static let artifactAccessTools: Set<String> = [
        OnboardingToolName.listArtifacts.rawValue,
        OnboardingToolName.getArtifact.rawValue,
        OnboardingToolName.getContextPack.rawValue,
        OnboardingToolName.requestRawFile.rawValue
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
            OnboardingToolName.validatedApplicantProfileData.rawValue
        ],
        .p1_photoCollection: [
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            OnboardingToolName.getUserOption.rawValue
        ],
        .p1_resumeUpload: [
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            OnboardingToolName.listArtifacts.rawValue,
            OnboardingToolName.getArtifact.rawValue
        ],
        .p1_timelineEditing: [
            OnboardingToolName.createTimelineCard.rawValue,
            OnboardingToolName.updateTimelineCard.rawValue,
            OnboardingToolName.deleteTimelineCard.rawValue,
            OnboardingToolName.reorderTimelineCards.rawValue,
            OnboardingToolName.getTimelineEntries.rawValue,
            OnboardingToolName.displayTimelineEntriesForReview.rawValue,
            OnboardingToolName.listArtifacts.rawValue,
            OnboardingToolName.getArtifact.rawValue
        ],
        .p1_timelineValidation: [
            OnboardingToolName.submitForValidation.rawValue,
            OnboardingToolName.displayTimelineEntriesForReview.rawValue,
            OnboardingToolName.updateTimelineCard.rawValue,
            OnboardingToolName.deleteTimelineCard.rawValue,
            OnboardingToolName.createTimelineCard.rawValue
        ],
        .p1_sectionConfig: [
            OnboardingToolName.configureEnabledSections.rawValue,
            OnboardingToolName.getUserOption.rawValue
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
            OnboardingToolName.startPhaseTwo.rawValue
        ],
        .p2_documentCollection: [
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            OnboardingToolName.scanGitRepo.rawValue,
            OnboardingToolName.openDocumentCollection.rawValue
        ],
        .p2_cardAssignment: [
            OnboardingToolName.proposeCardAssignments.rawValue,
            OnboardingToolName.getUserOption.rawValue
        ],
        .p2_userApprovalWait: [
            OnboardingToolName.getUserOption.rawValue
        ],
        .p2_kcGeneration: [
            OnboardingToolName.dispatchKCAgents.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],
        .p2_cardSubmission: [
            OnboardingToolName.submitKnowledgeCard.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p2_phaseTransition: [
            OnboardingToolName.nextPhase.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],

        // MARK: Phase 3 Subphases (all include artifact access)
        .p3_bootstrap: [
            OnboardingToolName.startPhaseThree.rawValue
        ],
        .p3_writingCollection: [
            OnboardingToolName.ingestWritingSample.rawValue,
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue
        ],
        .p3_sampleReview: [
            OnboardingToolName.ingestWritingSample.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],
        .p3_dossierCompilation: [
            OnboardingToolName.submitExperienceDefaults.rawValue,
            OnboardingToolName.submitCandidateDossier.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],
        .p3_dossierValidation: [
            OnboardingToolName.submitForValidation.rawValue,
            OnboardingToolName.getUserOption.rawValue
        ],
        .p3_dataSubmission: [
            OnboardingToolName.submitExperienceDefaults.rawValue,
            OnboardingToolName.submitCandidateDossier.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],
        .p3_interviewComplete: [
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
        let auditStatus = objectives[OnboardingObjectiveId.evidenceAuditCompleted.rawValue] ?? "pending"
        let cardsStatus = objectives[OnboardingObjectiveId.cardsGenerated.rawValue] ?? "pending"

        // Bootstrap phase (no objectives started)
        if auditStatus == "pending" {
            return .p2_bootstrap
        }

        // Evidence audit in progress
        if auditStatus == "in_progress" {
            // Could be document collection or card assignment
            // Default to document collection if we don't have enough context
            return .p2_documentCollection
        }

        // Cards generation
        if auditStatus == "completed" && cardsStatus != "completed" {
            if cardsStatus == "pending" {
                return .p2_kcGeneration
            }
            return .p2_cardSubmission
        }

        // All complete
        return .p2_phaseTransition
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
        if let choice = toolChoice {
            switch choice {
            case .none:
                return []
            case .functionTool(let ft):
                var bundle = safeEscapeTools
                bundle.insert(ft.name)
                // Include artifact access in Phase 2-3 even when forcing a tool
                if subphase.phase != .phase1CoreFacts {
                    bundle.formUnion(artifactAccessTools)
                }
                return bundle.intersection(allowedTools)
            case .customTool(let ct):
                var bundle = safeEscapeTools
                bundle.insert(ct.name)
                if subphase.phase != .phase1CoreFacts {
                    bundle.formUnion(artifactAccessTools)
                }
                return bundle.intersection(allowedTools)
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
