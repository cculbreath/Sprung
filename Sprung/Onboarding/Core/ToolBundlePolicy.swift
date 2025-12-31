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

    /// Minimal set of tools that should always be available (for error recovery).
    /// CRITICAL: ask_user_skip_to_next_phase is in safeEscapeTools.
    /// When user agrees to skip, it FORCES phase advance immediately.
    /// No interviewer intermediation—prevents dead-end stalls.
    static let safeEscapeTools: Set<String> = [
        OnboardingToolName.updateDossierNotes.rawValue,       // Scratchpad always available
        OnboardingToolName.askUserSkipToNextPhase.rawValue,   // Escape hatch - FORCES advance on user agreement
        OnboardingToolName.persistData.rawValue,              // Always allow dossier updates
        OnboardingToolName.getUserOption.rawValue             // Always allow structured questions
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

    /// Tool bundles for each subphase.
    /// INTERVIEW REVITALIZATION PLAN:
    /// - Phase 1: Voice & Context — Writing samples front-loaded
    /// - Phase 2: Career Story — Active interviewing with dossier weaving
    /// - Phase 3: Evidence Collection — Strategic document requests, batched notifications
    /// - Phase 4: Strategic Synthesis — Strengths/pitfalls, final dossier
    ///
    /// NOTE: During long-running agent ops (PDF ingestion, card inventory, merge),
    /// interviewer should actively use get_user_option and persist_data
    /// to gather dossier insights. User should never wait in silence.
    static let subphaseBundles: [InterviewSubphase: Set<String>] = [
        // MARK: Phase 1: Voice & Context
        .p1_welcome: [
            OnboardingToolName.agentReady.rawValue,           // Initial handshake at interview start
            OnboardingToolName.getUserOption.rawValue,        // For structured questions
            OnboardingToolName.persistData.rawValue,          // For dossier entries
            OnboardingToolName.validateApplicantProfile.rawValue  // Profile intake starts here
        ],

        .p1_writingSamples: [
            OnboardingToolName.getUserUpload.rawValue,        // For file uploads
            OnboardingToolName.ingestWritingSample.rawValue,  // For pasted text
            OnboardingToolName.getUserOption.rawValue,        // For follow-up questions
            OnboardingToolName.persistData.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue
        ],

        .p1_jobSearchContext: [
            OnboardingToolName.getUserOption.rawValue,        // PRIMARY TOOL - use liberally
            OnboardingToolName.persistData.rawValue,          // Save dossier entries
            OnboardingToolName.ingestWritingSample.rawValue   // If they paste something
        ],

        .p1_profileIntake: [
            OnboardingToolName.getApplicantProfile.rawValue,
            OnboardingToolName.getUserUpload.rawValue,        // Contacts import
            OnboardingToolName.getUserOption.rawValue,
            OnboardingToolName.validateApplicantProfile.rawValue,
            OnboardingToolName.validatedApplicantProfileData.rawValue
        ],

        .p1_profileValidation: [
            OnboardingToolName.validateApplicantProfile.rawValue,
            OnboardingToolName.validatedApplicantProfileData.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],

        .p1_phaseTransition: [
            OnboardingToolName.nextPhase.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],

        // MARK: Phase 2: Career Story
        .p2_timelineCollection: [
            OnboardingToolName.getUserUpload.rawValue,        // Resume upload
            OnboardingToolName.createTimelineCard.rawValue,
            OnboardingToolName.updateTimelineCard.rawValue,
            OnboardingToolName.deleteTimelineCard.rawValue,
            OnboardingToolName.getTimelineEntries.rawValue,
            OnboardingToolName.displayTimelineEntriesForReview.rawValue,
            OnboardingToolName.listArtifacts.rawValue,
            OnboardingToolName.getArtifact.rawValue
        ],

        .p2_timelineEnrichment: [    // Active interviewing about each role
            OnboardingToolName.getUserOption.rawValue,        // For structured dossier questions
            OnboardingToolName.persistData.rawValue,          // For dossier insights
            OnboardingToolName.updateTimelineCard.rawValue,
            OnboardingToolName.createTimelineCard.rawValue,
            OnboardingToolName.getTimelineEntries.rawValue,
            OnboardingToolName.displayTimelineEntriesForReview.rawValue
        ],

        .p2_workPreferences: [       // Dossier weaving
            OnboardingToolName.getUserOption.rawValue,        // PRIMARY - rapid structured questions
            OnboardingToolName.persistData.rawValue           // Save preferences to dossier
        ],

        .p2_sectionConfig: [
            OnboardingToolName.configureEnabledSections.rawValue,
            OnboardingToolName.getUserOption.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],

        .p2_documentSuggestions: [   // Strategic suggestions before Phase 3
            OnboardingToolName.persistData.rawValue,          // Save document wishlist
            OnboardingToolName.nextPhase.rawValue
        ],

        .p2_phaseTransition: [
            OnboardingToolName.nextPhase.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],

        // MARK: Phase 3: Evidence Collection
        .p3_documentCollection: [
            OnboardingToolName.openDocumentCollection.rawValue,
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            OnboardingToolName.listArtifacts.rawValue,
            OnboardingToolName.getArtifact.rawValue,
            OnboardingToolName.createWebArtifact.rawValue,
            OnboardingToolName.getUserOption.rawValue,        // For questions during agent waits
            OnboardingToolName.persistData.rawValue,          // For dossier insights during waits
            OnboardingToolName.setObjectiveStatus.rawValue
        ],

        .p3_gitCollection: [
            OnboardingToolName.listArtifacts.rawValue,
            OnboardingToolName.getArtifact.rawValue,
            OnboardingToolName.getUserOption.rawValue,        // For questions during agent waits
            OnboardingToolName.persistData.rawValue,          // For dossier insights during waits
            OnboardingToolName.setObjectiveStatus.rawValue
        ],

        .p3_cardGeneration: [
            OnboardingToolName.listArtifacts.rawValue,
            OnboardingToolName.getArtifact.rawValue,
            OnboardingToolName.getUserOption.rawValue,        // INTERVIEW WHILE KC GENERATION RUNS
            OnboardingToolName.persistData.rawValue,          // Gather strategic insights during wait
            OnboardingToolName.setObjectiveStatus.rawValue
        ],

        .p3_cardReview: [            // LLM reviews generated cards
            OnboardingToolName.listArtifacts.rawValue,
            OnboardingToolName.getArtifact.rawValue,
            OnboardingToolName.getUserOption.rawValue,        // For clarifying questions
            OnboardingToolName.persistData.rawValue,          // For card improvements
            OnboardingToolName.nextPhase.rawValue
        ],

        .p3_phaseTransition: [
            OnboardingToolName.nextPhase.rawValue,
            OnboardingToolName.setObjectiveStatus.rawValue
        ],

        // MARK: Phase 4: Strategic Synthesis
        .p4_strengthsSynthesis: [
            OnboardingToolName.getUserOption.rawValue,
            OnboardingToolName.persistData.rawValue,
            OnboardingToolName.listArtifacts.rawValue,
            OnboardingToolName.getArtifact.rawValue
        ],

        .p4_pitfallsAnalysis: [
            OnboardingToolName.getUserOption.rawValue,
            OnboardingToolName.persistData.rawValue
        ],

        .p4_dossierCompletion: [
            OnboardingToolName.getUserOption.rawValue,        // For gap-filling questions
            OnboardingToolName.persistData.rawValue,
            OnboardingToolName.submitCandidateDossier.rawValue
        ],

        .p4_experienceDefaults: [
            OnboardingToolName.submitExperienceDefaults.rawValue,
            OnboardingToolName.submitForValidation.rawValue,
            OnboardingToolName.getUserOption.rawValue
        ],

        .p4_completion: [
            OnboardingToolName.submitCandidateDossier.rawValue,
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
        case .phase1VoiceContext:
            return inferPhase1Subphase(toolPaneCard: toolPaneCard, objectives: objectives)
        case .phase2CareerStory:
            return inferPhase2Subphase(toolPaneCard: toolPaneCard, objectives: objectives)
        case .phase3EvidenceCollection:
            return inferPhase3Subphase(toolPaneCard: toolPaneCard, objectives: objectives)
        case .phase4StrategicSynthesis:
            return inferPhase4Subphase(toolPaneCard: toolPaneCard, objectives: objectives)
        case .complete:
            return .p4_completion
        }
    }

    /// Infer Phase 1 subphase (Voice & Context)
    /// NEW ORDER: profile → writing samples → job search context
    private static func inferPhase1Subphase(
        toolPaneCard: OnboardingToolPaneCard,
        objectives: [String: String]
    ) -> InterviewSubphase {
        // UI state takes precedence
        switch toolPaneCard {
        case .uploadRequest:
            // Writing samples upload (after profile is complete)
            return .p1_writingSamples
        case .applicantProfileRequest, .applicantProfileIntake:
            return .p1_profileIntake
        case .validationPrompt:
            return .p1_profileValidation
        case .choicePrompt:
            return .p1_jobSearchContext
        default:
            break
        }

        // Infer from objective state
        // NEW PHASE 1 ORDER: profile → writing samples → job search context
        let profileStatus = objectives[OnboardingObjectiveId.applicantProfileComplete.rawValue] ?? "pending"
        let writingSamplesStatus = objectives[OnboardingObjectiveId.writingSamplesCollected.rawValue] ?? "pending"
        let jobSearchStatus = objectives[OnboardingObjectiveId.jobSearchContextCaptured.rawValue] ?? "pending"

        // Start with welcome/profile if profile not complete
        if profileStatus == "pending" || profileStatus == "in_progress" {
            // If profile validation is in progress, show validation subphase
            if profileStatus == "in_progress" {
                return .p1_profileValidation
            }
            return .p1_welcome  // Welcome includes profile intake tools
        }

        // After profile: writing samples collection
        if writingSamplesStatus == "pending" || writingSamplesStatus == "in_progress" {
            return .p1_writingSamples
        }

        // After writing samples: job search context
        if jobSearchStatus == "pending" || jobSearchStatus == "in_progress" {
            return .p1_jobSearchContext
        }

        // All complete: ready for phase transition
        return .p1_phaseTransition
    }

    /// Infer Phase 2 subphase (Career Story)
    private static func inferPhase2Subphase(
        toolPaneCard: OnboardingToolPaneCard,
        objectives: [String: String]
    ) -> InterviewSubphase {
        // UI state takes precedence
        switch toolPaneCard {
        case .uploadRequest:
            return .p2_timelineCollection
        case .editTimelineCards, .confirmTimelineCards:
            return .p2_timelineCollection
        case .choicePrompt:
            return .p2_workPreferences
        case .sectionToggle:
            return .p2_sectionConfig
        case .validationPrompt:
            return .p2_timelineEnrichment
        default:
            break
        }

        // Infer from objective state
        let timelineStatus = objectives[OnboardingObjectiveId.skeletonTimelineComplete.rawValue] ?? "pending"
        let enrichedStatus = objectives[OnboardingObjectiveId.timelineEnriched.rawValue] ?? "pending"
        let preferencesStatus = objectives[OnboardingObjectiveId.workPreferencesCaptured.rawValue] ?? "pending"
        let sectionsStatus = objectives[OnboardingObjectiveId.enabledSections.rawValue] ?? "pending"

        // Timeline collection
        if timelineStatus == "pending" || timelineStatus == "in_progress" {
            return .p2_timelineCollection
        }

        // Timeline enrichment (active interviewing)
        if enrichedStatus == "pending" || enrichedStatus == "in_progress" {
            return .p2_timelineEnrichment
        }

        // Work preferences
        if preferencesStatus == "pending" || preferencesStatus == "in_progress" {
            return .p2_workPreferences
        }

        // Section config
        if sectionsStatus == "pending" || sectionsStatus == "in_progress" {
            return .p2_sectionConfig
        }

        // Document suggestions or transition
        return .p2_documentSuggestions
    }

    /// Infer Phase 3 subphase (Evidence Collection)
    private static func inferPhase3Subphase(
        toolPaneCard: OnboardingToolPaneCard,
        objectives: [String: String]
    ) -> InterviewSubphase {
        // UI state takes precedence
        switch toolPaneCard {
        case .uploadRequest:
            return .p3_documentCollection
        case .choicePrompt:
            return .p3_gitCollection
        case .validationPrompt:
            return .p3_cardReview
        default:
            break
        }

        // Infer from objective state
        let docsStatus = objectives[OnboardingObjectiveId.evidenceDocumentsCollected.rawValue] ?? "pending"
        let gitStatus = objectives[OnboardingObjectiveId.gitReposAnalyzed.rawValue] ?? "pending"
        let inventoryStatus = objectives[OnboardingObjectiveId.cardInventoryComplete.rawValue] ?? "pending"
        let kcStatus = objectives[OnboardingObjectiveId.knowledgeCardsGenerated.rawValue] ?? "pending"

        // Document collection
        if docsStatus == "pending" || docsStatus == "in_progress" {
            return .p3_documentCollection
        }

        // Git collection
        if gitStatus == "pending" || gitStatus == "in_progress" {
            return .p3_gitCollection
        }

        // Card generation
        if inventoryStatus == "pending" || inventoryStatus == "in_progress" ||
           kcStatus == "pending" || kcStatus == "in_progress" {
            return .p3_cardGeneration
        }

        // Card review or transition
        if kcStatus == "completed" {
            return .p3_cardReview
        }

        return .p3_phaseTransition
    }

    /// Infer Phase 4 subphase (Strategic Synthesis)
    private static func inferPhase4Subphase(
        toolPaneCard: OnboardingToolPaneCard,
        objectives: [String: String]
    ) -> InterviewSubphase {
        // UI state takes precedence
        switch toolPaneCard {
        case .validationPrompt:
            return .p4_experienceDefaults
        case .choicePrompt:
            return .p4_dossierCompletion
        default:
            break
        }

        // Infer from objective state
        let strengthsStatus = objectives[OnboardingObjectiveId.strengthsIdentified.rawValue] ?? "pending"
        let pitfallsStatus = objectives[OnboardingObjectiveId.pitfallsDocumented.rawValue] ?? "pending"
        let dossierStatus = objectives[OnboardingObjectiveId.dossierComplete.rawValue] ?? "pending"
        let defaultsStatus = objectives[OnboardingObjectiveId.experienceDefaultsSet.rawValue] ?? "pending"

        // Strengths synthesis
        if strengthsStatus == "pending" || strengthsStatus == "in_progress" {
            return .p4_strengthsSynthesis
        }

        // Pitfalls analysis
        if pitfallsStatus == "pending" || pitfallsStatus == "in_progress" {
            return .p4_pitfallsAnalysis
        }

        // Dossier completion
        if dossierStatus == "pending" || dossierStatus == "in_progress" {
            return .p4_dossierCompletion
        }

        // Experience defaults
        if defaultsStatus == "pending" || defaultsStatus == "in_progress" {
            return .p4_experienceDefaults
        }

        // All complete
        return .p4_completion
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
                // Artifact access tools for Phase 2-4 (not Phase 1)
                if subphase.phase != .phase1VoiceContext {
                    bundle.formUnion(artifactAccessTools)
                }
                return bundle
            case .customTool(let ct):
                // Always include the forced tool - this is required by OpenAI API
                var bundle: Set<String> = [ct.name]
                bundle.formUnion(safeEscapeTools)
                // Artifact access tools for Phase 2-4 (not Phase 1)
                if subphase.phase != .phase1VoiceContext {
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

        // Include artifact access tools for Phase 2-4 subphases (not Phase 1)
        if subphase.phase != .phase1VoiceContext {
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

        // Include artifact access tools for Phase 2-4 (not Phase 1)
        if phase != .phase1VoiceContext {
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
