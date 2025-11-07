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
            properties: properties
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { "next_phase" }
    var description: String { "Request advancing to the next interview phase." }
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
            response["status"].string = "complete"
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
            response["status"].string = "success"
            response["previous_phase"].string = currentPhase.rawValue
            response["new_phase"].string = nextPhase.rawValue
            response["message"].string = "Phase transition completed"
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
        await coordinator.eventBus.publish(.phaseAdvanceRequested(request: request, continuationId: UUID()))

        // Return completed - the tool's job is to present UI, which it has done
        // User's decision will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"

        return .immediate(response)
    }
}