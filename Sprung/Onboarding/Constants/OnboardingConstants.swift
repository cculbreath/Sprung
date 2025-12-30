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
    case updateDossierNotes = "update_dossier_notes"
    case listArtifacts = "list_artifacts"
    case getArtifact = "get_artifact"
    case getContextPack = "get_context_pack"
    case requestRawFile = "request_raw_file"
    case nextPhase = "next_phase"
    case askUserSkipToNextPhase = "ask_user_skip_to_next_phase"
    // Phase 2 Tools
    case startPhaseTwo = "start_phase_two"
    case getTimelineEntries = "get_timeline_entries"
    case displayKnowledgeCardPlan = "display_knowledge_card_plan"
    case openDocumentCollection = "open_document_collection"
    case setCurrentKnowledgeCard = "set_current_knowledge_card"
    case requestEvidence = "request_evidence"
    case submitKnowledgeCard = "submit_knowledge_card"
    case persistData = "persist_data"
    case setObjectiveStatus = "set_objective_status"

    // Multi-Agent Tools (Phase 2)
    // NOTE: propose_card_assignments removed - merge now triggered by "Done with Uploads" button
    case dispatchKCAgents = "dispatch_kc_agents"

    // Web Browsing Tools
    case createWebArtifact = "create_web_artifact"

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
    case applicantProfileProfilePhotoRetrieveProfile = "applicant_profile.profile_photo.retrieve_profile"
    case applicantProfileProfilePhotoEvaluateNeed = "applicant_profile.profile_photo.evaluate_need"
    case applicantProfileProfilePhotoCollectUpload = "applicant_profile.profile_photo.collect_upload"
    // Contact Flow
    case contactSourceSelected = "contact_source_selected"
    case contactDataCollected = "contact_data_collected"
    case contactDataValidated = "contact_data_validated"
    case contactPhotoCollected = "contact_photo_collected"
    // Skeleton Timeline
    case skeletonTimeline = "skeleton_timeline"
    case skeletonTimelineIntakeArtifacts = "skeleton_timeline.intake_artifacts"
    case skeletonTimelineTimelineEditor = "skeleton_timeline.timeline_editor"
    case skeletonTimelineContextInterview = "skeleton_timeline.context_interview"
    case skeletonTimelineCompletenessSignal = "skeleton_timeline.completeness_signal"
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
    case interviewedOneExperiencePrepSelection = "interviewed_one_experience.prep_selection"
    case interviewedOneExperienceDiscoveryInterview = "interviewed_one_experience.discovery_interview"
    case interviewedOneExperienceCaptureNotes = "interviewed_one_experience.capture_notes"
    case oneCardGenerated = "one_card_generated"
    case oneCardGeneratedDraft = "one_card_generated.draft"
    case oneCardGeneratedValidation = "one_card_generated.validation"
    case oneCardGeneratedPersisted = "one_card_generated.persisted"
    // MARK: Phase 3 Objectives
    // Writing Sample
    case oneWritingSample = "one_writing_sample"
    case oneWritingSampleCollectionSetup = "one_writing_sample.collection_setup"
    case oneWritingSampleIngestSample = "one_writing_sample.ingest_sample"
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

// MARK: - Interview Subphases
/// Granular subphases for precise tool bundling.
/// Each subphase maps to a specific set of tools the model needs.
enum InterviewSubphase: String, CaseIterable, Codable {
    // MARK: Phase 1: Core Facts
    case p1_profileIntake = "p1_profile_intake"           // Collecting contact info
    case p1_photoCollection = "p1_photo_collection"       // Offering/collecting profile photo
    case p1_resumeUpload = "p1_resume_upload"             // Offering resume upload before timeline
    case p1_timelineEditing = "p1_timeline_editing"       // Building skeleton timeline
    case p1_timelineValidation = "p1_timeline_validation" // Reviewing timeline before submission
    case p1_sectionConfig = "p1_section_config"           // Configuring enabled sections
    case p1_dossierSeed = "p1_dossier_seed"               // Asking 2-3 questions about goals
    case p1_phaseTransition = "p1_phase_transition"       // Ready to advance to Phase 2

    // MARK: Phase 2: Deep Dive
    case p2_bootstrap = "p2_bootstrap"                     // Calling start_phase_two
    case p2_documentCollection = "p2_document_collection" // Dropzone open, collecting documents
    case p2_cardAssignment = "p2_card_assignment"         // Proposing card-to-artifact assignments
    case p2_userApprovalWait = "p2_user_approval_wait"   // Waiting for user approval
    case p2_kcGeneration = "p2_kc_generation"             // Dispatching KC agents
    case p2_cardSubmission = "p2_card_submission"         // Submitting generated cards
    case p2_phaseTransition = "p2_phase_transition"       // Ready to advance to Phase 3

    // MARK: Phase 3: Writing Corpus
    case p3_bootstrap = "p3_bootstrap"                     // Calling start_phase_three
    case p3_writingCollection = "p3_writing_collection"   // Collecting writing samples
    case p3_sampleReview = "p3_sample_review"             // Evaluating sample quality
    case p3_dossierCompilation = "p3_dossier_compilation" // Compiling Phase 1-3 assets
    case p3_dossierValidation = "p3_dossier_validation"   // User reviewing dossier
    case p3_dataSubmission = "p3_data_submission"         // Submitting final data
    case p3_interviewComplete = "p3_interview_complete"   // Interview finished

    /// The parent phase for this subphase
    var phase: InterviewPhase {
        switch self {
        case .p1_profileIntake, .p1_photoCollection, .p1_resumeUpload,
             .p1_timelineEditing, .p1_timelineValidation, .p1_sectionConfig,
             .p1_dossierSeed, .p1_phaseTransition:
            return .phase1CoreFacts
        case .p2_bootstrap, .p2_documentCollection, .p2_cardAssignment,
             .p2_userApprovalWait, .p2_kcGeneration, .p2_cardSubmission,
             .p2_phaseTransition:
            return .phase2DeepDive
        case .p3_bootstrap, .p3_writingCollection, .p3_sampleReview,
             .p3_dossierCompilation, .p3_dossierValidation, .p3_dataSubmission,
             .p3_interviewComplete:
            return .phase3WritingCorpus
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
