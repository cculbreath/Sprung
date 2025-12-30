//
//  PhaseTwoScript.swift
//  Sprung
//
//  Phase 2: Deep Dive — Conduct detailed interviews and generate knowledge cards.
//
//  TOOL AVAILABILITY: Defined in ToolBundlePolicy.swift (single source of truth)
//
import Foundation
struct PhaseTwoScript: PhaseScript {
    let phase: InterviewPhase = .phase2DeepDive
    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .evidenceAuditCompleted,
        .cardsGenerated
    ])
    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            OnboardingObjectiveId.evidenceAuditCompleted.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.evidenceAuditCompleted.rawValue,
                onComplete: { context in
                    let title = "Evidence audit complete. Requests have been generated."
                    let details = ["next_objective": OnboardingObjectiveId.cardsGenerated.rawValue, "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            OnboardingObjectiveId.cardsGenerated.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.cardsGenerated.rawValue,
                dependsOn: [OnboardingObjectiveId.evidenceAuditCompleted.rawValue],
                onComplete: { context in
                    let title = "Knowledge cards generated and validated. Ready for Phase 3."
                    let details = ["ready_for": "phase3", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }
    var introductoryPrompt: String {
        PromptLibrary.phase2Intro
    }
}
