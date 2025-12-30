import Foundation
import SwiftyJSON
/// Domain service for objective tracking and management.
/// Owns all objective state and provides async APIs for updates.
actor ObjectiveStore: OnboardingEventEmitter {
    // MARK: - Event System
    let eventBus: EventCoordinator
    // MARK: - Policy
    private let phasePolicy: PhasePolicy
    // MARK: - Objective Storage
    /// The ONLY objective tracking storage
    private var objectives: [String: ObjectiveEntry] = [:]
    struct ObjectiveEntry: Codable {
        let id: String
        let label: String
        var status: ObjectiveStatus
        let phase: InterviewPhase
        var source: String
        var completedAt: Date?
        var notes: String?
        var details: [String: String]?  // Rich metadata for workflow context
        let parentId: String?      // Parent objective ID (e.g., "applicant_profile" for "applicant_profile.contact_intake")
        let level: Int              // Hierarchy level: 0=top, 1=sub, 2=sub-sub, etc.
        init(
            id: String,
            label: String,
            status: ObjectiveStatus,
            phase: InterviewPhase,
            source: String,
            completedAt: Date? = nil,
            notes: String? = nil,
            details: [String: String]? = nil,
            parentId: String? = nil,
            level: Int = 0
        ) {
            self.id = id
            self.label = label
            self.status = status
            self.phase = phase
            self.source = source
            self.completedAt = completedAt
            self.notes = notes
            self.details = details
            self.parentId = parentId
            self.level = level
        }
    }
    // MARK: - Initialization
    init(eventBus: EventCoordinator, phasePolicy: PhasePolicy, initialPhase: InterviewPhase) {
        self.eventBus = eventBus
        self.phasePolicy = phasePolicy
        // Register initial objectives for the starting phase
        let descriptors = Self.objectivesForPhase(initialPhase)
        for descriptor in descriptors {
            objectives[descriptor.id] = ObjectiveEntry(
                id: descriptor.id,
                label: descriptor.label,
                status: .pending,
                phase: initialPhase,
                source: "initial",
                completedAt: nil,
                notes: nil,
                parentId: descriptor.parentId,
                level: descriptor.level
            )
        }
        Logger.info("🎯 ObjectiveStore initialized with \(objectives.count) objectives", category: .ai)
    }
    // MARK: - Objective Catalog
    /// Hierarchical objective metadata for each phase.
    /// Structure matches the objective tree in PhaseOneScript.swift prompt.
    private static let objectiveMetadata: [InterviewPhase: [(id: String, label: String, parentId: String?)]] = [
        .phase1CoreFacts: [
            // applicant_profile (top-level)
            (OnboardingObjectiveId.applicantProfile.rawValue, "Applicant profile", nil),
            (OnboardingObjectiveId.applicantProfileContactIntake.rawValue, "Contact information intake", OnboardingObjectiveId.applicantProfile.rawValue),
            (OnboardingObjectiveId.applicantProfileContactIntakeActivateCard.rawValue, "Activate applicant profile card", OnboardingObjectiveId.applicantProfileContactIntake.rawValue),
            (OnboardingObjectiveId.applicantProfileContactIntakePersisted.rawValue, "ApplicantProfile updated with user-validated data", OnboardingObjectiveId.applicantProfileContactIntake.rawValue),
            (OnboardingObjectiveId.applicantProfileProfilePhoto.rawValue, "Optional profile photo", OnboardingObjectiveId.applicantProfile.rawValue),
            (OnboardingObjectiveId.applicantProfileProfilePhotoRetrieveProfile.rawValue, "Retrieve ApplicantProfile", OnboardingObjectiveId.applicantProfileProfilePhoto.rawValue),
            (OnboardingObjectiveId.applicantProfileProfilePhotoEvaluateNeed.rawValue, "Check if photo upload required", OnboardingObjectiveId.applicantProfileProfilePhoto.rawValue),
            (OnboardingObjectiveId.applicantProfileProfilePhotoCollectUpload.rawValue, "Activate photo upload card", OnboardingObjectiveId.applicantProfileProfilePhoto.rawValue),
            // skeleton_timeline (top-level)
            (OnboardingObjectiveId.skeletonTimeline.rawValue, "Skeleton timeline", nil),
            (OnboardingObjectiveId.skeletonTimelineIntakeArtifacts.rawValue, "Use get_user_upload and chat interview to gather timeline data", OnboardingObjectiveId.skeletonTimeline.rawValue),
            (OnboardingObjectiveId.skeletonTimelineTimelineEditor.rawValue, "Use TimelineEntry UI to collaborate with user", OnboardingObjectiveId.skeletonTimeline.rawValue),
            (OnboardingObjectiveId.skeletonTimelineContextInterview.rawValue, "Use chat interview to understand gaps and narrative structure", OnboardingObjectiveId.skeletonTimeline.rawValue),
            (OnboardingObjectiveId.skeletonTimelineCompletenessSignal.rawValue, "Set status when skeleton timeline data gathering is complete", OnboardingObjectiveId.skeletonTimeline.rawValue),
            // enabled_sections (top-level)
            (OnboardingObjectiveId.enabledSections.rawValue, "Enabled sections", nil),
            // dossier_seed (top-level)
            (OnboardingObjectiveId.dossierSeed.rawValue, "Dossier seed questions", nil),
            (OnboardingObjectiveId.contactSourceSelected.rawValue, "Contact source selected", nil),
            (OnboardingObjectiveId.contactDataCollected.rawValue, "Contact data collected", nil),
            (OnboardingObjectiveId.contactDataValidated.rawValue, "Contact data validated", nil),
            (OnboardingObjectiveId.contactPhotoCollected.rawValue, "Contact photo collected", nil)
        ],
        .phase2DeepDive: [
            (OnboardingObjectiveId.interviewedOneExperience.rawValue, "Experience interview completed", nil),
            (OnboardingObjectiveId.interviewedOneExperiencePrepSelection.rawValue, "Select and frame experience to explore", OnboardingObjectiveId.interviewedOneExperience.rawValue),
            (OnboardingObjectiveId.interviewedOneExperienceDiscoveryInterview.rawValue, "Conduct structured deep-dive interview", OnboardingObjectiveId.interviewedOneExperience.rawValue),
            (OnboardingObjectiveId.interviewedOneExperienceCaptureNotes.rawValue, "Summarize interview takeaways for cards", OnboardingObjectiveId.interviewedOneExperience.rawValue),
            (OnboardingObjectiveId.oneCardGenerated.rawValue, "Knowledge card generated", nil),
            (OnboardingObjectiveId.oneCardGeneratedDraft.rawValue, "Draft knowledge card content", OnboardingObjectiveId.oneCardGenerated.rawValue),
            (OnboardingObjectiveId.oneCardGeneratedValidation.rawValue, "Review card with user via validation UI", OnboardingObjectiveId.oneCardGenerated.rawValue),
            (OnboardingObjectiveId.oneCardGeneratedPersisted.rawValue, "Persist approved knowledge card", OnboardingObjectiveId.oneCardGenerated.rawValue)
        ],
        .phase3WritingCorpus: [
            (OnboardingObjectiveId.oneWritingSample.rawValue, "Writing sample collected", nil),
            (OnboardingObjectiveId.oneWritingSampleCollectionSetup.rawValue, "Request writing sample and capture preferences", OnboardingObjectiveId.oneWritingSample.rawValue),
            (OnboardingObjectiveId.oneWritingSampleIngestSample.rawValue, "Collect/upload at least one writing sample", OnboardingObjectiveId.oneWritingSample.rawValue),
            (OnboardingObjectiveId.dossierComplete.rawValue, "Dossier completed", nil),
            (OnboardingObjectiveId.dossierCompleteCompileAssets.rawValue, "Compile applicant assets into dossier", OnboardingObjectiveId.dossierComplete.rawValue),
            (OnboardingObjectiveId.dossierCompleteValidation.rawValue, "Present dossier summary for validation", OnboardingObjectiveId.dossierComplete.rawValue),
            (OnboardingObjectiveId.dossierCompletePersisted.rawValue, "Persist final dossier and confirm wrap-up", OnboardingObjectiveId.dossierComplete.rawValue)
        ],
        .complete: []
    ]
    private static func objectivesForPhase(
        _ phase: InterviewPhase
    ) -> [(id: String, label: String, phase: InterviewPhase, source: String, parentId: String?, level: Int)] {
        let metadata = objectiveMetadata[phase] ?? []
        return metadata.map { meta in
            // Auto-detect level from ID format (e.g., "applicant_profile.contact_intake.persisted" → level 3)
            let parts = meta.id.split(separator: ".")
            let level = max(0, parts.count - 1)
            return (
                id: meta.id,
                label: meta.label,
                phase: phase,
                source: "system",
                parentId: meta.parentId,
                level: level
            )
        }
    }
    // MARK: - Registration
    /// Register default objectives for a given phase
    func registerDefaultObjectives(for phase: InterviewPhase) {
        let descriptors = Self.objectivesForPhase(phase)
        for descriptor in descriptors {
            registerObjective(
                descriptor.id,
                label: descriptor.label,
                phase: descriptor.phase,
                source: descriptor.source,
                parentId: descriptor.parentId,
                level: descriptor.level
            )
        }
    }
    /// Register a new objective
    func registerObjective(
        _ id: String,
        label: String,
        phase: InterviewPhase,
        source: String = "system",
        parentId: String? = nil,
        level: Int? = nil
    ) {
        guard objectives[id] == nil else {
            Logger.debug("Objective \(id) already registered, skipping", category: .ai)
            return
        }
        // Auto-detect level from ID format if not provided (e.g., "applicant_profile.contact_intake.persisted" → level 3)
        let detectedLevel: Int
        if let level = level {
            detectedLevel = level
        } else {
            // Count dots in ID: applicant_profile = level 0, applicant_profile.contact_intake = level 1, etc.
            let parts = id.split(separator: ".")
            detectedLevel = max(0, parts.count - 1)
        }
        objectives[id] = ObjectiveEntry(
            id: id,
            label: label,
            status: .pending,
            phase: phase,
            source: source,
            completedAt: nil,
            notes: nil,
            parentId: parentId,
            level: detectedLevel
        )
        Logger.info("📋 Objective registered: \(id) for \(phase)", category: .ai)
    }
    // MARK: - Status Updates
    /// Update objective status (main API)
    func setObjectiveStatus(
        _ id: String,
        status: ObjectiveStatus,
        source: String? = nil,
        notes: String? = nil,
        details: [String: String]? = nil
    ) async {
        guard var objective = objectives[id] else {
            Logger.warning("⚠️ Attempted to update unknown objective: \(id)", category: .ai)
            return
        }
        let oldStatus = objective.status
        objective.status = status
        if let source = source {
            objective.source = source
        }
        if let notes = notes {
            objective.notes = notes
        }
        if let details = details {
            objective.details = details
        }
        if status == .completed && objective.completedAt == nil {
            objective.completedAt = Date()
        }
        objectives[id] = objective
        // Emit event to notify listeners (e.g., ObjectiveWorkflowEngine, StateCoordinator)
        await emit(.objectiveStatusChanged(
            id: id,
            oldStatus: oldStatus.rawValue,
            newStatus: status.rawValue,
            phase: objective.phase.rawValue,
            source: objective.source,
            notes: objective.notes,
            details: objective.details
        ))
        Logger.info("✅ Objective \(id): \(oldStatus) → \(status)", category: .ai)
        // Auto-completion: If this objective is completed/skipped and has a parent,
        // check if all siblings are done and auto-complete parent
        if status == .completed || status == .skipped, let parentId = objective.parentId {
            await checkAndAutoCompleteParent(parentId)
        }
    }
    // MARK: - Hierarchical Logic
    /// Recursively check if parent should be auto-completed
    private func checkAndAutoCompleteParent(_ parentId: String) async {
        guard let parent = objectives[parentId] else { return }
        // Only auto-complete if parent is still pending or in-progress
        guard parent.status == .pending || parent.status == .inProgress else { return }
        // Check if all children are complete
        if areAllChildrenComplete(parentId) {
            Logger.info("🎯 Auto-completing parent objective: \(parentId)", category: .ai)
            await setObjectiveStatus(
                parentId,
                status: .completed,
                source: "auto_completed",
                notes: "All sub-objectives completed"
            )
            // Recursively check grandparent
            if let grandparentId = parent.parentId {
                await checkAndAutoCompleteParent(grandparentId)
            }
        }
    }
    /// Check if all children of a parent are completed or skipped
    private func areAllChildrenComplete(_ parentId: String) -> Bool {
        let children = getChildObjectives(parentId)
        guard !children.isEmpty else { return false }
        return children.allSatisfy { $0.status == .completed || $0.status == .skipped }
    }
    // MARK: - Query Methods
    /// Get objective status by ID
    func getObjectiveStatus(_ id: String) -> ObjectiveStatus? {
        objectives[id]?.status
    }
    /// Get all objectives
    func getAllObjectives() -> [ObjectiveEntry] {
        Array(objectives.values)
    }
    /// Get all children of a given parent objective
    func getChildObjectives(_ parentId: String) -> [ObjectiveEntry] {
        objectives.values.filter { $0.parentId == parentId }
    }
    /// Get objectives for a specific phase
    func getObjectivesForPhase(_ phase: InterviewPhase) -> [ObjectiveEntry] {
        objectives.values.filter { $0.phase == phase }
    }
    /// Get missing objectives for current phase
    func getMissingObjectives(for phase: InterviewPhase) -> [String] {
        let requiredForPhase = phasePolicy.requiredObjectives[phase] ?? []
        return requiredForPhase.filter { id in
            let status = objectives[id]?.status
            return status != .completed && status != .skipped
        }
    }
    // MARK: - State Management
    /// Reset all objectives
    func reset() {
        objectives.removeAll()
        Logger.info("🔄 ObjectiveStore reset", category: .ai)
    }
}
