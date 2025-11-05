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

        // Rebuild system prompt for new phase
        let newPrompt = phaseRegistry.buildSystemPrompt(for: phase)

        // Update orchestrator's system prompt
        await lifecycleController?.updateOrchestratorSystemPrompt(newPrompt)

        Logger.info("🔄 System prompt updated for phase: \(phaseName)", category: .ai)
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
