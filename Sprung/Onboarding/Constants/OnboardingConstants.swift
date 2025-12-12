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
    /// UserDefaults key for the selected interview model
    static let userDefaultsKey = "onboardingInterviewDefaultModelId"

    /// Returns the currently configured model ID from settings
    /// Default is registered in SprungApp.init()
    static var currentModelId: String {
        UserDefaults.standard.string(forKey: userDefaultsKey) ?? "gpt-4o"
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
    case validatedApplicantProfileData = "validated_applicant_profile_data"
    case configureEnabledSections = "configure_enabled_sections"
    case listArtifacts = "list_artifacts"
    case getArtifact = "get_artifact"
    case requestRawFile = "request_raw_file"
    case nextPhase = "next_phase"
    // Phase 2 Tools
    case startPhaseTwo = "start_phase_two"
    case getTimelineEntries = "get_timeline_entries"
    case displayKnowledgeCardPlan = "display_knowledge_card_plan"
    case setCurrentKnowledgeCard = "set_current_knowledge_card"
    case scanGitRepo = "scan_git_repo"
    case requestEvidence = "request_evidence"
    case submitKnowledgeCard = "submit_knowledge_card"
    case persistData = "persist_data"
    case setObjectiveStatus = "set_objective_status"

    // Multi-Agent Tools (Phase 2)
    case proposeCardAssignments = "propose_card_assignments"
    case dispatchKCAgents = "dispatch_kc_agents"

    // Phase 3 Tools
    case startPhaseThree = "start_phase_three"
    case ingestWritingSample = "ingest_writing_sample"
    case submitExperienceDefaults = "submit_experience_defaults"
    case submitCandidateDossier = "submit_candidate_dossier"
}
// MARK: - Objective IDs
/// All objective IDs used in the onboarding interview flow.
/// Organized by phase with sub-objectives using dot notation.
enum OnboardingObjectiveId: String, CaseIterable {
    // MARK: Phase 1 Objectives
    // Applicant Profile
    case applicantProfile = "applicant_profile"
    case applicantProfileContactIntake = "applicant_profile.contact_intake"
    case applicantProfileContactIntakeActivateCard = "applicant_profile.contact_intake.activate_card"
    case applicantProfileContactIntakePersisted = "applicant_profile.contact_intake.persisted"
    case applicantProfileProfilePhoto = "applicant_profile.profile_photo"
    // Contact Flow
    case contactSourceSelected = "contact_source_selected"
    case contactDataCollected = "contact_data_collected"
    case contactDataValidated = "contact_data_validated"
    case contactPhotoCollected = "contact_photo_collected"
    // Skeleton Timeline
    case skeletonTimeline = "skeleton_timeline"
    // Enabled Sections
    case enabledSections = "enabled_sections"
    // Dossier Seed (optional)
    case dossierSeed = "dossier_seed"
    // MARK: Phase 2 Objectives
    // Evidence Audit
    case evidenceAuditCompleted = "evidence_audit_completed"
    case evidenceAuditAnalyze = "evidence_audit_completed.analyze"
    case evidenceAuditRequest = "evidence_audit_completed.request"
    // Cards Generated
    case cardsGenerated = "cards_generated"
    case cardsGeneratedReviewDrafts = "cards_generated.review_drafts"
    case cardsGeneratedPersist = "cards_generated.persist"
    // Legacy Phase 2 (may still be referenced)
    case interviewedOneExperience = "interviewed_one_experience"
    case oneCardGenerated = "one_card_generated"
    // MARK: Phase 3 Objectives
    // Writing Sample
    case oneWritingSample = "one_writing_sample"
    case oneWritingSampleCollectionSetup = "one_writing_sample.collection_setup"
    case oneWritingSampleIngestSample = "one_writing_sample.ingest_sample"
    case oneWritingSampleStyleAnalysis = "one_writing_sample.style_analysis"
    // Dossier Complete
    case dossierComplete = "dossier_complete"
    case dossierCompleteCompileAssets = "dossier_complete.compile_assets"
    case dossierCompleteValidation = "dossier_complete.validation"
    case dossierCompletePersisted = "dossier_complete.persisted"
}
// MARK: - Data Types
/// Data types used with persist_data and artifact storage.
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
