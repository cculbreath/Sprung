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
        let parentId: String?      // Parent objective ID (e.g., "P1.1" for "P1.1.A")
        let level: Int              // Hierarchy level: 0=top, 1=sub, 2=sub-sub, etc.

        init(
            id: String,
            label: String,
            status: ObjectiveStatus,
            phase: InterviewPhase,
            source: String,
            completedAt: Date? = nil,
            notes: String? = nil,
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
            // P1.1 applicant_profile (top-level)
            ("P1.1", "Applicant profile", nil),
            ("P1.1.A", "Contact Information", "P1.1"),
            ("P1.1.A.1", "Activate applicant profile card", "P1.1.A"),
            ("P1.1.A.2", "ApplicantProfile updated with user-validated data", "P1.1.A"),
            ("P1.1.B", "Optional Profile Photo", "P1.1"),
            ("P1.1.B.1", "Retrieve ApplicantProfile", "P1.1.B"),
            ("P1.1.B.2", "Check if photo upload required", "P1.1.B"),
            ("P1.1.B.3", "Activate photo upload card", "P1.1.B"),

            // P1.2 skeleton_timeline (top-level)
            ("P1.2", "Skeleton timeline", nil),
            ("P1.2.A", "Use get_user_upload and chat interview to gather timeline data", "P1.2"),
            ("P1.2.B", "Use TimelineEntry UI to collaborate with user", "P1.2"),
            ("P1.2.C", "Use chat interview to understand gaps and narrative structure", "P1.2"),
            ("P1.2.D", "Set status when skeleton timeline data gathering is complete", "P1.2"),

            // P1.3 enabled_sections (top-level)
            ("P1.3", "Enabled sections", nil),

            // P1.4 dossier_seed (top-level)
            ("P1.4", "Dossier seed questions", nil),

            // Legacy flat IDs for backward compatibility (mapped to hierarchical)
            ("applicant_profile", "Applicant profile (legacy)", nil),
            ("skeleton_timeline", "Skeleton timeline (legacy)", nil),
            ("enabled_sections", "Enabled sections (legacy)", nil),
            ("dossier_seed", "Dossier seed (legacy)", nil),
            ("contact_source_selected", "Contact source selected", nil),
            ("contact_data_collected", "Contact data collected", nil),
            ("contact_data_validated", "Contact data validated", nil),
            ("contact_photo_collected", "Contact photo collected", nil)
        ],
        .phase2DeepDive: [
            ("interviewed_one_experience", "Experience interview completed", nil),
            ("one_card_generated", "Knowledge card generated", nil)
        ],
        .phase3WritingCorpus: [
            ("one_writing_sample", "Writing sample collected", nil),
            ("dossier_complete", "Dossier completed", nil)
        ],
        .complete: []
    ]

    private static func objectivesForPhase(
        _ phase: InterviewPhase,
        policy: PhasePolicy
    ) -> [(id: String, label: String, phase: InterviewPhase, source: String, parentId: String?, level: Int)] {
        let metadata = objectiveMetadata[phase] ?? []
        return metadata.map { meta in
            // Auto-detect level from ID format (e.g., "P1.1.A.2" → level 3)
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

        // Auto-detect level from ID format if not provided (e.g., "P1.1.A.2" → level 3)
        let detectedLevel: Int
        if let level = level {
            detectedLevel = level
        } else {
            // Count dots in ID: P1.1 = 1 dot = level 1, P1.1.A = 2 parts after P = level 2
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
        notes: String? = nil
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
            notes: objective.notes
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
