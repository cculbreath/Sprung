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
    private weak var lifecycleController: InterviewLifecycleController?
    // MARK: - Initialization
    init(
        state: StateCoordinator,
        eventBus: EventCoordinator,
        phaseRegistry: PhaseScriptRegistry
    ) {
        self.state = state
        self.eventBus = eventBus
        self.phaseRegistry = phaseRegistry
    }
    // MARK: - Lifecycle Controller Reference
    func setLifecycleController(_ controller: InterviewLifecycleController) {
        self.lifecycleController = controller
    }
    // MARK: - Phase Transition Handling
    func handlePhaseTransition(_ phaseName: String) async {
        guard let phase = InterviewPhase(rawValue: phaseName) else {
            Logger.warning("Invalid phase name: \(phaseName)", category: .ai)
            return
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

        // Note: Phase intro prompts are queued and may be delivered after bootstrap tools
        // have already been called. Don't force toolChoice here - let instructions guide behavior.
        // The agent_ready/start_phase_two tools are called naturally at phase start.

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
    // MARK: - Phase Advancement
    func advancePhase() async -> InterviewPhase? {
        guard let newPhase = await state.advanceToNextPhase() else { return nil }
        // Update wizard progress is handled by the coordinator
        // via state synchronization
        await registerObjectivesForCurrentPhase()
        return newPhase
    }
    func nextPhase() async -> InterviewPhase? {
        let canAdvance = await state.canAdvancePhase()
        guard canAdvance else { return nil }
        let currentPhase = await state.phase
        switch currentPhase {
        case .phase1CoreFacts:
            return .phase2DeepDive
        case .phase2DeepDive:
            return .phase3WritingCorpus
        case .phase3WritingCorpus, .complete:
            return nil
        }
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
    func getCompletedObjectiveIds() async -> Set<String> {
        let objectives = await state.getAllObjectives()
        return Set(objectives
            .filter { $0.status == .completed || $0.status == .skipped }
            .map { $0.id })
    }
    // MARK: - System Prompt Building
    func buildSystemPrompt(for phase: InterviewPhase) -> String {
        phaseRegistry.buildSystemPrompt(for: phase)
    }
}
