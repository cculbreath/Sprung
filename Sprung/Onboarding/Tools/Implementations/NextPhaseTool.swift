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
        let properties: [String: JSONSchema] = [
            "overrides": JSONSchema(
                type: .array,
                description: "Optional. List of objectives to skip/override",
                items: JSONSchema(type: .string)
            ),
            "reason": JSONSchema(
                type: .string,
                description: "Optional. Reason for requesting to advance with unmet objectives"
            )
        ]
        return JSONSchema(
            type: .object,
            description: """
                Request transition to the next interview phase (Phase 1 → Phase 2 → Phase 3 → Complete).
                Use this when all required objectives for the current phase are completed. If objectives are missing, presents user approval dialog.
                RETURNS:
                - All objectives met: { "status": "success", "previous_phase": "phase1_core_facts", "new_phase": "phase2_deep_dive", "message": "Phase transition completed" }
                - Objectives missing: { "message": "UI presented. Awaiting user input.", "status": "completed" } (dialog shown to user)
                - Already complete: { "status": "complete", "message": "Interview is already complete" }
                USAGE: Call when Phase 1 objectives (applicant_profile, skeleton_timeline, enabled_sections) are completed. Ideally also complete dossier_seed before advancing.
                WORKFLOW:
                1. Complete all required Phase 1 objectives
                2. Optionally complete dossier_seed for better Phase 2 context
                3. Call next_phase to advance
                4. If all objectives met: Transition happens immediately
                5. If objectives missing: User sees approval dialog with list of incomplete items
                6. User approves/denies transition
                7. If approved, phase advances despite incomplete objectives
                Phase transitions:
                - Phase 1 (Core Facts) → Phase 2 (Deep Dive)
                - Phase 2 (Deep Dive) → Phase 3 (Writing Corpus)
                - Phase 3 (Writing Corpus) → Complete
                DO NOT: Call before required objectives are complete unless user explicitly requests moving forward despite incompleteness.
                """,
            properties: properties,
            additionalProperties: false
        )
    }()
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.nextPhase.rawValue }
    var description: String { "Request phase transition. If objectives complete, transitions immediately. If not, presents user approval dialog. Returns {status, new_phase}." }
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
        // If all objectives are met, transition immediately
        if missingObjectives.isEmpty {
            let reason = params["reason"].string ?? "All objectives completed"
            await coordinator.requestPhaseTransition(
                from: currentPhase.rawValue,
                to: nextPhase.rawValue,
                reason: reason
            )
            var response = JSON()
            response["status"].string = "completed"
            response["previous_phase"].string = currentPhase.rawValue
            response["new_phase"].string = nextPhase.rawValue
            response["message"].string = "Phase transition completed"
            // Chain to the bootstrap tool for the new phase
            if nextPhase == .phase2DeepDive {
                response["next_required_tool"].string = OnboardingToolName.startPhaseTwo.rawValue
            } else if nextPhase == .phase3WritingCorpus {
                response["next_required_tool"].string = OnboardingToolName.startPhaseThree.rawValue
            }
            return .immediate(response)
        }
        // If objectives are missing, present a dialog and wait for user approval
        let overrides = params["overrides"].array?.compactMap { $0.string } ?? []
        let request = OnboardingPhaseAdvanceRequest(
            currentPhase: currentPhase,
            nextPhase: nextPhase,
            missingObjectives: missingObjectives,
            reason: params["reason"].string,
            proposedOverrides: overrides
        )
        // Emit UI request to show the phase advance dialog
        await coordinator.eventBus.publish(.phaseAdvanceRequested(request: request))
        // Return completed - the tool's job is to present UI, which it has done
        // User's decision will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"
        return .immediate(response)
    }
}
