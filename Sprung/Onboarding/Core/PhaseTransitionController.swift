import Foundation
import SwiftyJSON
/// Manages phase transitions, advances, and system prompt updates.
/// Extracted from OnboardingInterviewCoordinator to improve maintainability.
@MainActor
final class PhaseTransitionController {
    // MARK: - Dependencies
    private let state: StateCoordinator
    private let eventBus: EventCoordinator
    private let phaseRegistry: PhaseScriptRegistry
    private let artifactRecordStore: ArtifactRecordStore
    private weak var sessionPersistenceHandler: SwiftDataSessionPersistenceHandler?
    private let resRefStore: ResRefStore

    // MARK: - Initialization
    init(
        state: StateCoordinator,
        eventBus: EventCoordinator,
        phaseRegistry: PhaseScriptRegistry,
        artifactRecordStore: ArtifactRecordStore,
        sessionPersistenceHandler: SwiftDataSessionPersistenceHandler,
        resRefStore: ResRefStore
    ) {
        self.state = state
        self.eventBus = eventBus
        self.phaseRegistry = phaseRegistry
        self.artifactRecordStore = artifactRecordStore
        self.sessionPersistenceHandler = sessionPersistenceHandler
        self.resRefStore = resRefStore
    }
    // MARK: - Phase Transition Handling
    func handlePhaseTransition(_ phaseName: String) async {
        guard let phase = InterviewPhase(rawValue: phaseName) else {
            Logger.warning("Invalid phase name: \(phaseName)", category: .ai)
            return
        }

        // Export artifacts to filesystem when entering Phase 3
        // This enables the filesystem browsing tools (read_file, list_directory, glob_search, grep_search)
        if phase == .phase3EvidenceCollection {
            await exportArtifactsForFilesystemBrowsing()
        }

        // Get the phase script's introductory prompt
        guard let script = phaseRegistry.script(for: phase) else {
            Logger.warning("No script found for phase: \(phaseName)", category: .ai)
            return
        }
        // Send introductory prompt as a developer message
        // This sets up the phase-specific rules and instructions
        let introPrompt = script.introductoryPrompt
        var introPayload = JSON()
        introPayload["text"].string = introPrompt
        introPayload["reasoningEffort"].string = "low"  // GPT-5.1 supports: none, low, medium, high

        // Don't force toolChoice - let the model output preamble text naturally before calling tools
        // The initial user message includes explicit instructions to output the welcome message

        await eventBus.publish(.llmSendDeveloperMessage(
            payload: introPayload
        ))
        // Query and surface artifacts targeted for this phase's objectives
        // Include both required objectives and all their child objectives
        let allObjectives = await state.getObjectivesForPhase(phase)
        let allObjectiveIds = allObjectives.map { $0.id }
        var targetedArtifacts: [JSON] = []
        var seenArtifactIds = Set<String>()
        for objectiveId in allObjectiveIds {
            let artifacts = await state.getArtifactsForPhaseObjective(objectiveId)
            for artifact in artifacts {
                let artifactId = artifact["id"].stringValue
                // Deduplicate artifacts that might match multiple objectives
                if !seenArtifactIds.contains(artifactId) {
                    seenArtifactIds.insert(artifactId)
                    targetedArtifacts.append(artifact)
                }
            }
        }
        // If artifacts exist for this phase, send them as a follow-up developer message
        if !targetedArtifacts.isEmpty {
            var artifactSummaries: [String] = []
            for artifact in targetedArtifacts {
                let id = artifact["id"].stringValue
                let filename = artifact["filename"].stringValue
                let purpose = artifact["metadata"]["purpose"].stringValue
                let targetObjectives = artifact["metadata"]["target_phase_objectives"].arrayValue
                    .map { $0.stringValue }
                    .joined(separator: ", ")
                artifactSummaries.append(
                    "- \(filename) (id: \(id), purpose: \(purpose), targets: \(targetObjectives))"
                )
            }
            let artifactMessage = """
            Artifacts Available for This Phase:
            The following artifacts have been pre-loaded because they target objectives in this phase:
            \(artifactSummaries.joined(separator: "\n"))
            Use list_artifacts, get_artifact, or request_raw_file to access these resources as needed.
            """
            var artifactPayload = JSON()
            artifactPayload["text"].string = artifactMessage
            await eventBus.publish(.llmSendDeveloperMessage(
                payload: artifactPayload
            ))
            Logger.info("📦 Surfaced \(targetedArtifacts.count) targeted artifacts for phase: \(phaseName)", category: .ai)
        }
        Logger.info("🔄 Phase introductory prompt sent as developer message for phase: \(phaseName)", category: .ai)
    }
    // MARK: - Phase Transition Requests
    func requestPhaseTransition(from: String, to: String, reason: String?) async {
        await eventBus.publish(.phaseTransitionRequested(
            from: from,
            to: to,
            reason: reason
        ))
    }
    // MARK: - Objective Management
    func registerObjectivesForCurrentPhase() async {
        // Objectives are now automatically registered by StateCoordinator
        // when the phase is set, so this is no longer needed
        Logger.info("📋 Objectives auto-registered by StateCoordinator for current phase", category: .ai)
    }
    func missingObjectives() async -> [String] {
        await state.getMissingObjectives()
    }

    // MARK: - Artifact Filesystem Export

    /// Export session artifacts and knowledge cards to a temporary filesystem directory for LLM browsing.
    /// Sets the ArtifactFilesystemContext root so filesystem tools can access artifacts.
    private func exportArtifactsForFilesystemBrowsing() async {
        guard let session = sessionPersistenceHandler?.currentSession else {
            Logger.warning("📁 No current session for artifact export", category: .ai)
            return
        }

        do {
            let exportRoot = try artifactRecordStore.exportArtifactsToFilesystem(session)

            // Also export knowledge cards to the same root
            let resRefs = resRefStore.resRefs
            if !resRefs.isEmpty {
                try artifactRecordStore.exportKnowledgeCards(resRefs, to: exportRoot)
            }

            await ArtifactFilesystemContext.shared.setRoot(exportRoot)
            Logger.info("📁 Artifact filesystem initialized at \(exportRoot.path) (\(resRefs.count) KCs)", category: .ai)
        } catch {
            Logger.error("📁 Failed to export artifacts for filesystem browsing: \(error)", category: .ai)
        }
    }

    /// Re-export a single artifact to the existing filesystem root (for incremental updates).
    /// Called when artifacts are added or updated during Phase 3.
    func updateArtifactInFilesystem(_ artifact: ArtifactRecord) async {
        guard let rootURL = await ArtifactFilesystemContext.shared.rootURL else {
            // Filesystem not initialized yet, nothing to update
            return
        }

        do {
            try artifactRecordStore.exportSingleArtifact(artifact, to: rootURL)
            Logger.info("📁 Updated artifact in filesystem: \(artifact.filename)", category: .ai)
        } catch {
            Logger.error("📁 Failed to update artifact in filesystem: \(error)", category: .ai)
        }
    }

    /// Export a single ResRef to the filesystem (for incremental updates when cards are created/modified).
    /// Called when knowledge cards are persisted during Phase 3+.
    func updateResRefInFilesystem(_ resRef: ResRef) async {
        guard let rootURL = await ArtifactFilesystemContext.shared.rootURL else {
            // Filesystem not initialized yet, nothing to update
            return
        }

        do {
            try artifactRecordStore.exportSingleResRef(resRef, to: rootURL)
            Logger.info("📁 Updated knowledge card in filesystem: \(resRef.name)", category: .ai)
        } catch {
            Logger.error("📁 Failed to update knowledge card in filesystem: \(error)", category: .ai)
        }
    }
}
