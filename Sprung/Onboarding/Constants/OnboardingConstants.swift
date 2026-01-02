//
//  OnboardingConstants.swift
//  Sprung
//
//  Centralized enums for magic strings used throughout the onboarding module.
//  Provides type safety and IDE autocomplete for tool names, objective IDs, and data types.
//
import Foundation

// MARK: - Model Configuration
/// Default model configuration for onboarding interview
enum OnboardingModelConfig {
    /// UserDefaults key for the selected OpenAI interview model
    static let userDefaultsKey = "onboardingInterviewDefaultModelId"
    /// UserDefaults key for the selected Anthropic interview model
    static let anthropicModelKey = "onboardingAnthropicModelId"
    /// UserDefaults key for the selected provider
    static let providerKey = "onboardingProvider"

    /// Returns the currently configured provider
    static var currentProvider: OnboardingProvider {
        let rawValue = UserDefaults.standard.string(forKey: providerKey) ?? "openai"
        return OnboardingProvider(rawValue: rawValue) ?? .openai
    }

    /// Returns the currently configured model ID from settings (provider-aware)
    /// Default is registered in SprungApp.init()
    static var currentModelId: String {
        switch currentProvider {
        case .openai:
            return UserDefaults.standard.string(forKey: userDefaultsKey) ?? "gpt-4o"
        case .anthropic:
            return UserDefaults.standard.string(forKey: anthropicModelKey) ?? "claude-sonnet-4-20250514"
        }
    }
}

// MARK: - Tool Names
/// All tool names used in the onboarding interview flow.
/// Use these enum cases instead of raw strings for type safety.
enum OnboardingToolName: String, CaseIterable {
    // Phase 1 Tools
    case agentReady = "agent_ready"
    case getUserOption = "get_user_option"
    case getApplicantProfile = "get_applicant_profile"
    case getUserUpload = "get_user_upload"
    case cancelUserUpload = "cancel_user_upload"
    case createTimelineCard = "create_timeline_card"
    case updateTimelineCard = "update_timeline_card"
    case deleteTimelineCard = "delete_timeline_card"
    case reorderTimelineCards = "reorder_timeline_cards"
    case displayTimelineEntriesForReview = "display_timeline_entries_for_review"
    case submitForValidation = "submit_for_validation"
    case validateApplicantProfile = "validate_applicant_profile"
    case configureEnabledSections = "configure_enabled_sections"
    case updateDossierNotes = "update_dossier_notes"
    case listArtifacts = "list_artifacts"
    case getArtifact = "get_artifact"
    case requestRawFile = "request_raw_file"
    case nextPhase = "next_phase"
    case askUserSkipToNextPhase = "ask_user_skip_to_next_phase"
    // Phase 2 Tools
    case getTimelineEntries = "get_timeline_entries"
    case openDocumentCollection = "open_document_collection"

    // Web Browsing Tools
    case createWebArtifact = "create_web_artifact"

    // Phase 3/4 Tools
    case ingestWritingSample = "ingest_writing_sample"
    case submitExperienceDefaults = "submit_experience_defaults"
    case submitCandidateDossier = "submit_candidate_dossier"
}
// MARK: - Objective IDs
/// All objective IDs used in the onboarding interview flow.
/// Organized by phase with sub-objectives using dot notation.
///
/// INTERVIEW REVITALIZATION PLAN — New Objective Structure:
/// Phase 1: writing_samples_collected, voice_primers_extracted, job_search_context_captured, applicant_profile_complete
/// Phase 2: skeleton_timeline_complete, timeline_enriched, work_preferences_captured, unique_circumstances_documented
/// Phase 3: evidence_documents_collected, git_repos_analyzed, card_inventory_complete, knowledge_cards_generated
/// Phase 4: strengths_identified, pitfalls_documented, dossier_complete, experience_defaults_set
enum OnboardingObjectiveId: String, CaseIterable {
    // MARK: Phase 1: Voice & Context
    /// At least one substantial writing sample collected
    case writingSamplesCollected = "writing_samples_collected"
    /// Voice analysis complete (runs in background after writing sample upload)
    case voicePrimersExtracted = "voice_primers_extracted"
    /// Core dossier field populated (why searching, priorities)
    case jobSearchContextCaptured = "job_search_context_captured"
    /// Contact info validated (name, email, phone, location)
    case applicantProfileComplete = "applicant_profile_complete"
    // Legacy Phase 1 objectives (backwards compatibility)
    case applicantProfile = "applicant_profile"
    case contactSourceSelected = "contact_source_selected"
    case contactDataCollected = "contact_data_collected"
    case contactDataValidated = "contact_data_validated"
    case contactPhotoCollected = "contact_photo_collected"

    // MARK: Phase 2: Career Story
    /// All positions captured with dates
    case skeletonTimelineComplete = "skeleton_timeline_complete"
    /// Each position has narrative context beyond dates
    case timelineEnriched = "timeline_enriched"
    /// Remote/location/arrangement preferences captured
    case workPreferencesCaptured = "work_preferences_captured"
    /// Gaps, pivots, constraints explained
    case uniqueCircumstancesDocumented = "unique_circumstances_documented"
    /// User has configured which sections to include
    case enabledSections = "enabled_sections"
    // Legacy Phase 2 objectives (backwards compatibility)
    case skeletonTimeline = "skeleton_timeline"
    case dossierSeed = "dossier_seed"
    case evidenceAuditCompleted = "evidence_audit_completed"
    case cardsGenerated = "cards_generated"

    // MARK: Phase 3: Evidence Collection
    /// Supporting documents uploaded
    case evidenceDocumentsCollected = "evidence_documents_collected"
    /// Code repositories processed
    case gitReposAnalyzed = "git_repos_analyzed"
    /// All knowledge cards identified from documents
    case cardInventoryComplete = "card_inventory_complete"
    /// Knowledge cards created and persisted
    case knowledgeCardsGenerated = "knowledge_cards_generated"

    // MARK: Phase 4: Strategic Synthesis
    /// Strategic strengths documented with evidence
    case strengthsIdentified = "strengths_identified"
    /// Potential concerns + mitigation strategies documented
    case pitfallsDocumented = "pitfalls_documented"
    /// All dossier fields populated with rich narratives
    case dossierComplete = "dossier_complete"
    /// Resume defaults configured
    case experienceDefaultsSet = "experience_defaults_set"
    // Legacy Phase 3 objectives (backwards compatibility)
    case oneWritingSample = "one_writing_sample"
}
// MARK: - Data Types
/// Data types used for artifact storage and session persistence.
enum OnboardingDataType: String, CaseIterable {
    case applicantProfile = "applicant_profile"
    case skeletonTimeline = "skeleton_timeline"
    case artifactRecord = "artifact_record"
    case knowledgeCard = "knowledge_card"
    case writingSample = "writing_sample"
    case candidateDossier = "candidate_dossier"
    case candidateDossierEntry = "candidate_dossier_entry"
    case experienceDefaults = "experience_defaults"
    case enabledSections = "enabled_sections"
}

// MARK: - Interview Subphases
/// Granular subphases for precise tool bundling.
/// Each subphase maps to a specific set of tools the model needs.
///
/// INTERVIEW REVITALIZATION PLAN:
/// - Phase 1: Voice & Context — Writing samples front-loaded, voice primers extracted
/// - Phase 2: Career Story — Active interviewing, dossier weaving throughout
/// - Phase 3: Evidence Collection — Strategic document requests, batched notifications
/// - Phase 4: Strategic Synthesis — Strengths/pitfalls analysis, final dossier
enum InterviewSubphase: String, CaseIterable, Codable {
    // MARK: Phase 1: Voice & Context
    case p1_welcome = "p1_welcome"                         // Initial welcome
    case p1_writingSamples = "p1_writing_samples"         // Front-loaded writing sample collection
    case p1_jobSearchContext = "p1_job_search_context"    // Dossier questions about priorities
    case p1_profileIntake = "p1_profile_intake"           // Collecting contact info
    case p1_profileValidation = "p1_profile_validation"   // Validating profile
    case p1_phaseTransition = "p1_phase_transition"       // Ready to advance to Phase 2

    // MARK: Phase 2: Career Story
    case p2_timelineCollection = "p2_timeline_collection"     // Resume upload or conversational collection
    case p2_timelineEnrichment = "p2_timeline_enrichment"     // Active interviewing about each role
    case p2_workPreferences = "p2_work_preferences"           // Dossier weaving (remote, location, etc.)
    case p2_sectionConfig = "p2_section_config"               // Configuring enabled sections
    case p2_documentSuggestions = "p2_document_suggestions"   // Strategic suggestions before Phase 3
    case p2_timelineValidation = "p2_timeline_validation"     // User clicked "Done with Timeline", needs validation
    case p2_phaseTransition = "p2_phase_transition"           // Ready to advance to Phase 3

    // MARK: Phase 3: Evidence Collection
    case p3_documentCollection = "p3_document_collection"     // Strategic document requests
    case p3_gitCollection = "p3_git_collection"               // Git repository selection
    case p3_cardGeneration = "p3_card_generation"             // Card inventory + merge + KC generation
    case p3_cardReview = "p3_card_review"                     // LLM reviews generated cards
    case p3_phaseTransition = "p3_phase_transition"           // Ready to advance to Phase 4

    // MARK: Phase 4: Strategic Synthesis
    case p4_strengthsSynthesis = "p4_strengths_synthesis"     // Identify strategic strengths
    case p4_pitfallsAnalysis = "p4_pitfalls_analysis"         // Document concerns + mitigations
    case p4_dossierCompletion = "p4_dossier_completion"       // Fill remaining dossier gaps
    case p4_experienceDefaults = "p4_experience_defaults"     // Configure resume defaults
    case p4_completion = "p4_completion"                       // Final wrap-up

    /// The parent phase for this subphase
    var phase: InterviewPhase {
        switch self {
        case .p1_welcome, .p1_writingSamples, .p1_jobSearchContext,
             .p1_profileIntake, .p1_profileValidation, .p1_phaseTransition:
            return .phase1VoiceContext
        case .p2_timelineCollection, .p2_timelineEnrichment, .p2_workPreferences,
             .p2_sectionConfig, .p2_documentSuggestions, .p2_timelineValidation, .p2_phaseTransition:
            return .phase2CareerStory
        case .p3_documentCollection, .p3_gitCollection, .p3_cardGeneration,
             .p3_cardReview, .p3_phaseTransition:
            return .phase3EvidenceCollection
        case .p4_strengthsSynthesis, .p4_pitfallsAnalysis, .p4_dossierCompletion,
             .p4_experienceDefaults, .p4_completion:
            return .phase4StrategicSynthesis
        }
    }
}

// MARK: - Document Type Policy

/// Centralized file extension definitions for document handling.
/// Single source of truth for accepted/extractable/image extensions.
struct DocumentTypePolicy {
    /// All file extensions accepted for drops in the onboarding dropzone.
    static let acceptedExtensions = Set([
        "pdf", "docx", "txt", "png", "jpg", "jpeg", "md", "json", "gif", "webp", "heic", "html", "htm", "rtf"
    ])

    /// File extensions that can have text extracted (for LLM context).
    static let extractableExtensions = Set([
        "pdf", "txt", "docx", "html", "htm", "md", "rtf"
    ])

    /// Image file extensions (for visual artifacts).
    static let imageExtensions = Set([
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"
    ])

    /// Check if a file extension is accepted for drops.
    static func isAccepted(_ ext: String) -> Bool {
        acceptedExtensions.contains(ext.lowercased())
    }

    /// Check if a file extension can have text extracted.
    static func isExtractable(_ ext: String) -> Bool {
        extractableExtensions.contains(ext.lowercased())
    }

    /// Check if a file extension is an image.
    static func isImage(_ ext: String) -> Bool {
        imageExtensions.contains(ext.lowercased())
    }
}

// MARK: - Tool Groupings

extension OnboardingToolName {
    /// Timeline tools that can operate during validation state for real-time card editing.
    /// Used by ToolGating to allow these tools while waiting for validation input.
    static let timelineTools: Set<String> = Set([
        OnboardingToolName.createTimelineCard,
        OnboardingToolName.updateTimelineCard,
        OnboardingToolName.deleteTimelineCard,
        OnboardingToolName.reorderTimelineCards
    ].map(\.rawValue))

    /// Tools that should auto-complete successfully instead of being blocked.
    /// These are "cleanup" or "dismissal" tools that the LLM may call after UI state
    /// has already changed. Blocking them causes conversation sync errors.
    /// Instead of blocking, return success with a friendly message.
    static let autoCompleteWhenBlockedTools: Set<String> = Set([
        OnboardingToolName.cancelUserUpload  // UI may already be dismissed
    ].map(\.rawValue))
}

// MARK: - Convenience Extensions
extension OnboardingToolName {
    /// Convert an array of tool name enums to their raw string values.
    static func rawValues(_ tools: [OnboardingToolName]) -> [String] {
        tools.map { $0.rawValue }
    }
    /// Convert a set of tool name enums to a set of raw string values.
    static func rawValues(_ tools: Set<OnboardingToolName>) -> Set<String> {
        Set(tools.map { $0.rawValue })
    }
}
extension OnboardingObjectiveId {
    /// Convert an array of objective ID enums to their raw string values.
    static func rawValues(_ objectives: [OnboardingObjectiveId]) -> [String] {
        objectives.map { $0.rawValue }
    }
    /// Get the parent objective ID (for sub-objectives).
    /// Returns nil if this is a root objective.
    var parentId: OnboardingObjectiveId? {
        let parts = rawValue.split(separator: ".")
        guard parts.count > 1 else { return nil }
        let parentRaw = parts.dropLast().joined(separator: ".")
        return OnboardingObjectiveId(rawValue: parentRaw)
    }
    /// Check if this is a sub-objective (contains a dot).
    var isSubObjective: Bool {
        rawValue.contains(".")
    }
}
