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
    private static let schema: JSONSchema = {
        return JSONSchema(
            type: .object,
            description: """
                Request transition to the next interview phase (Phase 1 → Phase 2 → Phase 3 → Complete).
                Transitions immediately. If objectives are incomplete, they are listed in the response.
                RETURNS:
                - { "status": "completed", "previous_phase": "...", "new_phase": "...", "next_required_tool": "start_phase_two" or "start_phase_three" }
                - If objectives incomplete: includes "skipped_objectives" array
                - Already complete: { "status": "completed", "message": "Interview is already complete" }
                Phase transitions:
                - Phase 1 (Core Facts) → Phase 2 (Deep Dive) → call start_phase_two next
                - Phase 2 (Deep Dive) → Phase 3 (Writing Corpus) → call start_phase_three next
                - Phase 3 (Writing Corpus) → Complete
                """,
            properties: [:],
            required: [],
            additionalProperties: false
        )
    }()
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.nextPhase.rawValue }
    var description: String { "Transition to the next interview phase. Returns {status, new_phase, next_required_tool}." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        // Check if we can advance to the next phase
        let currentPhase = await coordinator.currentPhase
        let missingObjectives = await coordinator.missingObjectives()
        // Determine the next phase
        let nextPhase: InterviewPhase
        switch currentPhase {
        case .phase1CoreFacts:
            nextPhase = .phase2DeepDive
        case .phase2DeepDive:
            nextPhase = .phase3WritingCorpus
        case .phase3WritingCorpus:
            nextPhase = .complete
        case .complete:
            var response = JSON()
            response["status"].string = "completed"
            response["message"].string = "Interview is already complete"
            return .immediate(response)
        }
        // Transition immediately, regardless of objectives
        // If objectives are missing, include them in the response so LLM can inform user
        let reason = missingObjectives.isEmpty ? "All objectives completed" : "User requested advancement"
        await coordinator.requestPhaseTransition(
            from: currentPhase.rawValue,
            to: nextPhase.rawValue,
            reason: reason
        )
        var response = JSON()
        response["status"].string = "completed"
        response["previous_phase"].string = currentPhase.rawValue
        response["new_phase"].string = nextPhase.rawValue
        if missingObjectives.isEmpty {
            response["message"].string = "Phase transition completed"
        } else {
            response["message"].string = "Phase transition completed with incomplete objectives"
            response["skipped_objectives"] = JSON(missingObjectives)
        }
        // Chain to the bootstrap tool for the new phase
        if nextPhase == .phase2DeepDive {
            response["next_required_tool"].string = OnboardingToolName.startPhaseTwo.rawValue
        } else if nextPhase == .phase3WritingCorpus {
            response["next_required_tool"].string = OnboardingToolName.startPhaseThree.rawValue
        }
        return .immediate(response)
    }
}
