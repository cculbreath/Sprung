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
        OnboardingToolName.getUserOption.rawValue,            // Always allow structured questions
        OnboardingToolName.updateTodoList.rawValue            // Task tracking always available
    ]

    // MARK: - Artifact Access Tools

    /// Artifact access tools - included in Phase 2-4 subphases
    /// NOTE: get_artifact REMOVED from orchestrator access.
    /// Orchestrator works from artifact summaries (list_artifacts) and conversation.
    /// Full document content is processed by subagents (extraction, KC generation).
    static let artifactAccessTools: Set<String> = [
        OnboardingToolName.listArtifacts.rawValue,     // Metadata only - summaries for orchestration
        OnboardingToolName.requestRawFile.rawValue,    // For user download requests
        OnboardingToolName.createWebArtifact.rawValue  // For saving web_search content
    ]

    // MARK: - Filesystem Browsing Tools

    /// Filesystem-style tools for browsing exported artifacts.
    /// Available in Phase 3 when artifacts are exported to temp folder.
    /// Responses are ephemeral (pruned after N turns) - LLM should take notes.
    static let filesystemBrowsingTools: Set<String> = [
        OnboardingToolName.readFile.rawValue,
        OnboardingToolName.listDirectory.rawValue,
        OnboardingToolName.globSearch.rawValue,
        OnboardingToolName.grepSearch.rawValue
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
    /// interviewer should actively use get_user_option to gather insights.
    /// User should never wait in silence.
    static let subphaseBundles: [InterviewSubphase: Set<String>] = [
        // MARK: Phase 1: Voice & Context
        .p1_welcome: [
            OnboardingToolName.agentReady.rawValue,           // Initial handshake at interview start
            OnboardingToolName.getUserOption.rawValue,        // For structured questions
            OnboardingToolName.getApplicantProfile.rawValue,  // Profile form (agent_ready directs here)
            OnboardingToolName.validateApplicantProfile.rawValue  // For URL/document extraction validation
        ],

        .p1_writingSamples: [
            OnboardingToolName.getUserUpload.rawValue,        // For file uploads
            OnboardingToolName.ingestWritingSample.rawValue,  // For pasted text
            OnboardingToolName.getUserOption.rawValue,        // For follow-up questions
            OnboardingToolName.cancelUserUpload.rawValue
        ],

        .p1_jobSearchContext: [
            OnboardingToolName.getUserOption.rawValue,        // PRIMARY TOOL - use liberally
            OnboardingToolName.ingestWritingSample.rawValue   // If they paste something
        ],

        .p1_profileIntake: [
            OnboardingToolName.getApplicantProfile.rawValue,
            OnboardingToolName.getUserUpload.rawValue,        // Contacts import
            OnboardingToolName.getUserOption.rawValue,
            OnboardingToolName.validateApplicantProfile.rawValue
        ],

        .p1_profileValidation: [
            OnboardingToolName.validateApplicantProfile.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],

        .p1_phaseTransition: [
            OnboardingToolName.nextPhase.rawValue
        ],

        // MARK: Phase 2: Career Story
        .p2_timelineCollection: [
            OnboardingToolName.getUserUpload.rawValue,        // Resume upload
            OnboardingToolName.createTimelineCard.rawValue,
            OnboardingToolName.updateTimelineCard.rawValue,
            OnboardingToolName.deleteTimelineCard.rawValue,
            OnboardingToolName.reorderTimelineCards.rawValue,
            OnboardingToolName.getTimelineEntries.rawValue,
            OnboardingToolName.displayTimelineEntriesForReview.rawValue,
            OnboardingToolName.listArtifacts.rawValue         // Metadata only - subagents handle extraction
        ],

        .p2_timelineEnrichment: [    // Active interviewing about each role
            OnboardingToolName.getUserOption.rawValue,        // For structured dossier questions
            OnboardingToolName.updateTimelineCard.rawValue,
            OnboardingToolName.createTimelineCard.rawValue,
            OnboardingToolName.reorderTimelineCards.rawValue,
            OnboardingToolName.getTimelineEntries.rawValue,
            OnboardingToolName.displayTimelineEntriesForReview.rawValue,
            OnboardingToolName.configureEnabledSections.rawValue  // Available for instruction-based guidance
        ],

        .p2_workPreferences: [       // Dossier weaving
            OnboardingToolName.getUserOption.rawValue         // PRIMARY - rapid structured questions
        ],

        .p2_sectionConfig: [
            OnboardingToolName.configureEnabledSections.rawValue,
            OnboardingToolName.getUserOption.rawValue,
            OnboardingToolName.nextPhase.rawValue
        ],

        .p2_documentSuggestions: [   // Strategic suggestions before Phase 3
            OnboardingToolName.nextPhase.rawValue
        ],

        .p2_timelineValidation: [    // After user clicks "Done with Timeline"
            OnboardingToolName.submitForValidation.rawValue,
            OnboardingToolName.getTimelineEntries.rawValue,
            OnboardingToolName.configureEnabledSections.rawValue,  // Available after validation confirms
            OnboardingToolName.nextPhase.rawValue                  // Available for instruction-based phase advance
        ],

        .p2_phaseTransition: [
            OnboardingToolName.nextPhase.rawValue
        ],

        // MARK: Phase 3: Evidence Collection
        // NOTE: get_artifact REMOVED - orchestrator works from summaries, subagents handle extraction
        .p3_documentCollection: [
            OnboardingToolName.openDocumentCollection.rawValue,
            OnboardingToolName.getUserUpload.rawValue,
            OnboardingToolName.cancelUserUpload.rawValue,
            OnboardingToolName.listArtifacts.rawValue,        // Summaries only
            OnboardingToolName.createWebArtifact.rawValue,
            OnboardingToolName.getUserOption.rawValue         // For dossier questions during waits
        ],

        .p3_gitCollection: [
            OnboardingToolName.listArtifacts.rawValue,        // Summaries only
            OnboardingToolName.getUserOption.rawValue         // For dossier questions during waits
        ],

        .p3_cardGeneration: [
            OnboardingToolName.listArtifacts.rawValue,        // Summaries only
            OnboardingToolName.getUserOption.rawValue         // INTERVIEW WHILE KC GENERATION RUNS
        ],

        .p3_cardReview: [            // LLM reviews generated cards from KC summaries
            OnboardingToolName.listArtifacts.rawValue,        // Summaries only
            OnboardingToolName.getUserOption.rawValue         // For clarifying questions
            // NOTE: next_phase NOT available in Phase 3 - user clicks "Approve Cards" to advance
        ],

        .p3_phaseTransition: [
            // Phase 3 transitions automatically when user clicks "Approve Cards"
            // No tools needed - this subphase exists only for completeness
        ],

        // MARK: Phase 4: Strategic Synthesis
        // NOTE: get_artifact REMOVED - synthesis uses timeline, KC summaries, and conversation
        .p4_strengthsSynthesis: [
            OnboardingToolName.getUserOption.rawValue,
            OnboardingToolName.listArtifacts.rawValue         // Summaries only for reference
        ],

        .p4_pitfallsAnalysis: [
            OnboardingToolName.getUserOption.rawValue
        ],

        .p4_dossierCompletion: [
            OnboardingToolName.getUserOption.rawValue,        // For gap-filling questions
            OnboardingToolName.submitCandidateDossier.rawValue
        ],

        .p4_experienceDefaults: [
            OnboardingToolName.generateExperienceDefaults.rawValue,
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
        // NOTE: .choicePrompt intentionally NOT mapped here.
        // Choice prompts can appear during various Phase 1 activities. We rely on
        // objective-based inference below to determine the correct subphase,
        // ensuring tools like next_phase are available when the phase is ready to advance.
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
        case .editTimelineCards:
            return .p2_timelineCollection
        case .confirmTimelineCards, .validationPrompt:
            // User clicked "Done with Timeline" - need to validate before advancing
            // This enables submit_for_validation tool
            return .p2_timelineValidation
        // NOTE: .choicePrompt intentionally NOT mapped here.
        // Choice prompts can appear during various Phase 2 activities (work preferences,
        // section config follow-ups, etc.). We rely on objective-based inference below
        // to determine the correct subphase, ensuring tools like next_phase are available
        // when the interview is ready to advance.
        case .sectionToggle:
            return .p2_sectionConfig
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
        // UI state takes precedence for specific card types
        switch toolPaneCard {
        case .uploadRequest:
            return .p3_documentCollection
        // NOTE: .choicePrompt intentionally NOT mapped here.
        // Choice prompts can appear during various Phase 3 activities (git collection,
        // card review, etc.). We rely on objective-based inference below to determine
        // the correct subphase, ensuring tools like next_phase are available when ready.
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
        // UI state takes precedence for specific card types
        switch toolPaneCard {
        case .validationPrompt:
            return .p4_experienceDefaults
        // NOTE: .choicePrompt intentionally NOT mapped here.
        // Choice prompts can appear during various Phase 4 activities. We rely on
        // objective-based inference below to determine the correct subphase,
        // ensuring tools like next_phase are available when ready.
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

        // Include filesystem browsing tools for Phase 3 (evidence collection)
        if subphase.phase == .phase3EvidenceCollection {
            bundle.formUnion(filesystemBrowsingTools)
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

        // Include filesystem browsing tools for Phase 3
        if phase == .phase3EvidenceCollection {
            allowed.formUnion(filesystemBrowsingTools)
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
