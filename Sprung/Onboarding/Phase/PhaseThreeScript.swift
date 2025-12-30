//
//  PhaseThreeScript.swift
//  Sprung
//
//  Phase 3: Writing Corpus — Collect writing samples and complete dossier.
//
//  TOOL AVAILABILITY: Defined in ToolBundlePolicy.swift (single source of truth)
//
import Foundation
struct PhaseThreeScript: PhaseScript {
    let phase: InterviewPhase = .phase3WritingCorpus
    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .oneWritingSample,
        .dossierComplete
    ])
    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            OnboardingObjectiveId.oneWritingSample.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.oneWritingSample.rawValue,
                onComplete: { context in
                    let title = "Writing sample captured. Proceed to assemble the dossier for final validation."
                    let details = ["next_objective": OnboardingObjectiveId.dossierComplete.rawValue, "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            OnboardingObjectiveId.dossierComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.dossierComplete.rawValue,
                dependsOn: [OnboardingObjectiveId.oneWritingSample.rawValue],
                onComplete: { context in
                    let title = "Candidate dossier finalized. Congratulate the user, summarize next steps, and call next_phase to finish the interview."
                    let details = ["status": context.status.rawValue, "ready_for": "completion"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }
    var introductoryPrompt: String {
        PromptLibrary.phase3Intro
    }
}
