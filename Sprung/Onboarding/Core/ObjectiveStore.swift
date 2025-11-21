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

    // MARK: - Synchronous Caches (for SwiftUI)
    /// Sync cache of all objectives for SwiftUI access
    nonisolated(unsafe) private(set) var objectivesSync: [String: ObjectiveEntry] = [:]

    // MARK: - Initialization
    init(eventBus: EventCoordinator, phasePolicy: PhasePolicy, initialPhase: InterviewPhase) {
        self.eventBus = eventBus
        self.phasePolicy = phasePolicy

        // Register initial objectives for the starting phase
        let descriptors = Self.objectivesForPhase(initialPhase, policy: phasePolicy)
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

        objectivesSync = objectives
        Logger.info("🎯 ObjectiveStore initialized with \(objectives.count) objectives", category: .ai)
    }

    // MARK: - Objective Catalog
    /// Hierarchical objective metadata for each phase.
    /// Structure matches the objective tree in PhaseOneScript.swift prompt.
    private static let objectiveMetadata: [InterviewPhase: [(id: String, label: String, parentId: String?)]] = [
        .phase1CoreFacts: [
            // applicant_profile (top-level)
            ("applicant_profile", "Applicant profile", nil),
            ("applicant_profile.contact_intake", "Contact information intake", "applicant_profile"),
            ("applicant_profile.contact_intake.activate_card", "Activate applicant profile card", "applicant_profile.contact_intake"),
            ("applicant_profile.contact_intake.persisted", "ApplicantProfile updated with user-validated data", "applicant_profile.contact_intake"),
            ("applicant_profile.profile_photo", "Optional profile photo", "applicant_profile"),
            ("applicant_profile.profile_photo.retrieve_profile", "Retrieve ApplicantProfile", "applicant_profile.profile_photo"),
            ("applicant_profile.profile_photo.evaluate_need", "Check if photo upload required", "applicant_profile.profile_photo"),
            ("applicant_profile.profile_photo.collect_upload", "Activate photo upload card", "applicant_profile.profile_photo"),

            // skeleton_timeline (top-level)
            ("skeleton_timeline", "Skeleton timeline", nil),
            ("skeleton_timeline.intake_artifacts", "Use get_user_upload and chat interview to gather timeline data", "skeleton_timeline"),
            ("skeleton_timeline.timeline_editor", "Use TimelineEntry UI to collaborate with user", "skeleton_timeline"),
            ("skeleton_timeline.context_interview", "Use chat interview to understand gaps and narrative structure", "skeleton_timeline"),
            ("skeleton_timeline.completeness_signal", "Set status when skeleton timeline data gathering is complete", "skeleton_timeline"),

            // enabled_sections (top-level)
            ("enabled_sections", "Enabled sections", nil),

            // dossier_seed (top-level)
            ("dossier_seed", "Dossier seed questions", nil),

            ("contact_source_selected", "Contact source selected", nil),
            ("contact_data_collected", "Contact data collected", nil),
            ("contact_data_validated", "Contact data validated", nil),
            ("contact_photo_collected", "Contact photo collected", nil)
        ],
        .phase2DeepDive: [
            ("interviewed_one_experience", "Experience interview completed", nil),
            ("interviewed_one_experience.prep_selection", "Select and frame experience to explore", "interviewed_one_experience"),
            ("interviewed_one_experience.discovery_interview", "Conduct structured deep-dive interview", "interviewed_one_experience"),
            ("interviewed_one_experience.capture_notes", "Summarize interview takeaways for cards", "interviewed_one_experience"),
            ("one_card_generated", "Knowledge card generated", nil),
            ("one_card_generated.draft", "Draft knowledge card content", "one_card_generated"),
            ("one_card_generated.validation", "Review card with user via validation UI", "one_card_generated"),
            ("one_card_generated.persisted", "Persist approved knowledge card", "one_card_generated")
        ],
        .phase3WritingCorpus: [
            ("one_writing_sample", "Writing sample collected", nil),
            ("one_writing_sample.collection_setup", "Request writing sample and capture consent/preferences", "one_writing_sample"),
            ("one_writing_sample.ingest_sample", "Collect/upload at least one writing sample", "one_writing_sample"),
            ("one_writing_sample.style_analysis", "Analyze writing style when consented", "one_writing_sample"),
            ("dossier_complete", "Dossier completed", nil),
            ("dossier_complete.compile_assets", "Compile applicant assets into dossier", "dossier_complete"),
            ("dossier_complete.validation", "Present dossier summary for validation", "dossier_complete"),
            ("dossier_complete.persisted", "Persist final dossier and confirm wrap-up", "dossier_complete")
        ],
        .complete: []
    ]

    private static func objectivesForPhase(
        _ phase: InterviewPhase,
        policy: PhasePolicy
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
        let descriptors = Self.objectivesForPhase(phase, policy: phasePolicy)
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

        objectivesSync = objectives // Update sync cache
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
        objectivesSync = objectives // Update sync cache

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
        if (status == .completed || status == .skipped), let parentId = objective.parentId {
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

    /// Check if phase can advance (all required objectives complete)
    func canAdvancePhase(from phase: InterviewPhase) -> Bool {
        guard let requiredObjectives = phasePolicy.requiredObjectives[phase] else {
            return false
        }
        return requiredObjectives.allSatisfy { objectiveId in
            objectives[objectiveId]?.status == .completed ||
            objectives[objectiveId]?.status == .skipped
        }
    }

    // MARK: - Scratchpad Summary
    /// Build a condensed scratchpad summary for LLM metadata
    func scratchpadSummary(for phase: InterviewPhase) -> String {
        let phaseObjectives = getObjectivesForPhase(phase)
            .sorted { $0.id < $1.id }
            .map { "\($0.id)=\($0.status.rawValue)" }

        if phaseObjectives.isEmpty {
            return "objectives[\(phase.rawValue)]=none"
        } else {
            return "objectives[\(phase.rawValue)]=\(phaseObjectives.joined(separator: ", "))"
        }
    }

    // MARK: - State Management
    /// Restore objectives from snapshot
    func restore(objectives: [String: ObjectiveEntry]) {
        self.objectives = objectives
        self.objectivesSync = objectives
        Logger.info("📥 Objectives restored from snapshot (\(objectives.count) objectives)", category: .ai)
    }

    /// Reset all objectives
    func reset() {
        objectives.removeAll()
        objectivesSync = [:]
        Logger.info("🔄 ObjectiveStore reset", category: .ai)
    }
}
