//
//  NextPhaseTool.swift
//  Sprung
//
//  Requests advancing to the next interview phase.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI
struct NextPhaseTool: InterviewTool {
    private static let schema: JSONSchema = PhaseSchemas.phaseTransitionSchema()
    private weak var coordinator: OnboardingInterviewCoordinator?
    private let dataStore: InterviewDataStore
    private let registry: PhaseScriptRegistry

    init(
        coordinator: OnboardingInterviewCoordinator,
        dataStore: InterviewDataStore,
        registry: PhaseScriptRegistry
    ) {
        self.coordinator = coordinator
        self.dataStore = dataStore
        self.registry = registry
    }

    var name: String { OnboardingToolName.nextPhase.rawValue }
    var description: String {
        """
        Advance to the next interview phase. THIS IS THE PRIMARY TOOL FOR PHASE TRANSITIONS. \
        Call this when phase objectives are complete or user is ready to proceed. \
        Returns {status, newPhase, next_required_tool}. If blocked, the response will \
        explain why - only then consider ask_user_skip_to_next_phase as a last resort.
        """
    }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        let currentPhase = await coordinator.currentPhase
        let missingObjectives = await coordinator.timeline.missingObjectives()

        // Validate the transition using the registry
        // Note: User approval flags are checked via coordinator.state, not via LLM parameter
        let validation = await registry.validateTransition(
            from: currentPhase,
            coordinator: coordinator,
            dataStore: dataStore
        )

        // Handle validation results
        switch validation {
        case .blocked(let reason, let message):
            var response = JSON()
            response["error"].bool = true
            response["reason"].string = reason
            response["status"].string = "incomplete"
            response["message"].string = message
            return .immediate(response)

        case .requiresConfirmation(let warning, let message):
            var response = JSON()
            response["status"].string = "incomplete"
            response["warning"].string = warning
            response["message"].string = message
            return .immediate(response)

        case .alreadyComplete:
            var response = JSON()
            response["status"].string = "completed"
            response["message"].string = "Interview is already complete"
            return .immediate(response)

        case .allowed:
            // Get the next phase from the registry
            guard let nextPhase = await registry.nextPhase(after: currentPhase) else {
                var response = JSON()
                response["status"].string = "completed"
                response["message"].string = "Interview is already complete"
                return .immediate(response)
            }

            // Transition immediately, regardless of objectives
            // Note: Todo list is populated by StateCoordinator when handling phaseTransitionRequested
            let reason = missingObjectives.isEmpty ? "All objectives completed" : "User requested advancement"
            await coordinator.timeline.requestPhaseTransition(
                from: currentPhase.rawValue,
                to: nextPhase.rawValue,
                reason: reason
            )

            var response = JSON()
            response["status"].string = "completed"
            response["previousPhase"].string = currentPhase.rawValue
            response["newPhase"].string = nextPhase.rawValue

            if missingObjectives.isEmpty {
                response["message"].string = "Phase transition completed"
            } else {
                response["message"].string = "Phase transition completed with incomplete objectives"
                response["skippedObjectives"] = JSON(missingObjectives)
            }

            // Include the first objective's workflow guidance in the response
            // This replaces coordinator messages which are now queued until user action
            if let script = await MainActor.run(body: { registry.script(for: nextPhase) }),
               let firstObjectiveId = script.requiredObjectives.first,
               let workflow = script.workflow(for: firstObjectiveId) {
                let context = ObjectiveWorkflowContext(
                    completedObjectives: [],
                    status: .inProgress,
                    details: [:]
                )
                let outputs = workflow.outputs(for: .inProgress, context: context)
                for output in outputs {
                    if case .coordinatorMessage(let title, let details, _) = output {
                        response["nextSteps"].string = title
                        if let action = details["action"] {
                            response["nextRequiredTool"].string = action.replacingOccurrences(of: "call_", with: "")
                        }
                        break
                    }
                }
            }

            return .immediate(response)
        }
    }
}
