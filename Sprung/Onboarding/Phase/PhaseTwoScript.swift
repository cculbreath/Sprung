//
//  PhaseTwoScript.swift
//  Sprung
//
//  Phase 2: Deep Dive — Conduct detailed interviews and generate knowledge cards.
//

import Foundation

struct PhaseTwoScript: PhaseScript {
    let phase: InterviewPhase = .phase2DeepDive

    let requiredObjectives: [String] = [
        "interviewed_one_experience",
        "one_card_generated"
    ]

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            "interviewed_one_experience": ObjectiveWorkflow(
                id: "interviewed_one_experience",
                onComplete: { context in
                    let title = "Completed a deep-dive interview. Use the captured notes to generate at least one knowledge card next."
                    let details = ["next_objective": "one_card_generated", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "one_card_generated": ObjectiveWorkflow(
                id: "one_card_generated",
                dependsOn: ["interviewed_one_experience"],
                onComplete: { context in
                    let title = "Knowledge card created and validated. If the user has more experiences to cover, repeat the interview cycle; otherwise prepare to transition to Phase 3."
                    let details = ["ready_for": "phase3", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }

    var systemPromptFragment: String {
        SystemPromptTemplates.phaseTwoFragment
    }
}
