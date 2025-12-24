//
//  PhaseTwoScript.swift
//  Sprung
//
//  Phase 2: Deep Dive — Conduct detailed interviews and generate knowledge cards.
//
import Foundation
struct PhaseTwoScript: PhaseScript {
    let phase: InterviewPhase = .phase2DeepDive
    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .evidenceAuditCompleted,
        .cardsGenerated
    ])
    let allowedTools: [String] = OnboardingToolName.rawValues([
        // Multi-agent workflow tools (in order of use)
        .startPhaseTwo,           // Bootstrap: returns timeline + artifact summaries
        .openDocumentCollection,  // Show dropzone for document uploads (mandatory step)
        .proposeCardAssignments,  // Map artifacts to cards, identify gaps
        .dispatchKCAgents,        // Spawn parallel KC agents
        .submitKnowledgeCard,     // Persist each generated card

        // Document collection tools
        .getUserUpload,
        .cancelUserUpload,
        // Note: scanGitRepo removed - it's triggered by UI button, not LLM
        .listArtifacts,
        .getArtifact,
        .getContextPack,
        .requestRawFile,
        // Note: requestEvidence tool removed - users upload via dropzone instead

        // User interaction
        .getUserOption,

        // Data persistence
        .persistData,             // For dossier entries

        // Phase management
        .setObjectiveStatus,
        .nextPhase,
        .askUserSkipToNextPhase  // For when KC generation fails
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
