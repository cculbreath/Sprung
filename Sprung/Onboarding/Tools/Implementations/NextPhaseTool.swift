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

    let service: OnboardingInterviewService

    var name: String { "next_phase" }
    var description: String { "Request advancing to the next interview phase." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Check if we can advance to the next phase
        let currentPhase = await service.coordinator.currentPhase
        let missingObjectives = await service.coordinator.missingObjectives()

        if !missingObjectives.isEmpty {
            // Check for overrides
            let overrides = params["overrides"].array?.compactMap { $0.string } ?? []
            let reason = params["reason"].string

            let unmetObjectives = missingObjectives.filter { !overrides.contains($0) }

            if !unmetObjectives.isEmpty {
                var response = JSON()
                response["status"].string = "blocked"
                response["message"].string = "Cannot advance phase due to unmet objectives"
                response["missing_objectives"] = JSON(unmetObjectives)
                response["current_phase"].string = currentPhase.rawValue
                return .immediate(response)
            }
        }

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

        // Request phase transition via coordinator (which emits events)
        let reason = params["reason"].string ?? "Tool requested phase advance"
        await service.coordinator.requestPhaseTransition(
            from: currentPhase.rawValue,
            to: nextPhase.rawValue,
            reason: reason
        )

        var response = JSON()
        response["status"].string = "success"
        response["previous_phase"].string = currentPhase.rawValue
        response["new_phase"].string = nextPhase.rawValue
        response["message"].string = "Phase transition initiated"
        return .immediate(response)
    }
}