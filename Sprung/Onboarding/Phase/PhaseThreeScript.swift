//
//  PhaseThreeScript.swift
//  Sprung
//
//  Phase 3: Writing Corpus — Collect writing samples and complete dossier.
//

import Foundation

struct PhaseThreeScript: PhaseScript {
    let phase: InterviewPhase = .phase3WritingCorpus

    let requiredObjectives: [String] = [
        "one_writing_sample",
        "dossier_complete"
    ]

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            "one_writing_sample": ObjectiveWorkflow(
                id: "one_writing_sample",
                onComplete: { context in
                    let title = "Writing sample captured. Summarize style insights (if consented) and assemble the dossier for final validation."
                    let details = ["next_objective": "dossier_complete", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "dossier_complete": ObjectiveWorkflow(
                id: "dossier_complete",
                dependsOn: ["one_writing_sample"],
                onComplete: { context in
                    let title = "Candidate dossier finalized. Congratulate the user, summarize next steps, and call next_phase to finish the interview."
                    let details = ["status": context.status.rawValue, "ready_for": "completion"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }

    var systemPromptFragment: String {
        SystemPromptTemplates.phaseThreeFragment
    }
}
