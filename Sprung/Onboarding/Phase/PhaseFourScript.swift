//
//  PhaseFourScript.swift
//  Sprung
//
//  Phase 4: Strategic Synthesis — Strengths, pitfalls, dossier completion, experience defaults.
//
//  INTERVIEW REVITALIZATION PLAN:
//  This phase synthesizes everything gathered in Phases 1-3 into strategic intelligence
//  for the job search. The interviewer acts as a career strategist, identifying strengths
//  to emphasize, pitfalls to avoid, and ensuring the dossier is complete.
//
//  TOOL AVAILABILITY: Defined in ToolBundlePolicy.swift (single source of truth)
//
import Foundation

struct PhaseFourScript: PhaseScript {
    let phase: InterviewPhase = .phase4StrategicSynthesis

    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .strengthsIdentified,
        .pitfallsDocumented,
        .dossierComplete,
        .experienceDefaultsSet
    ])

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            // MARK: - Strengths Synthesis
            OnboardingObjectiveId.strengthsIdentified.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.strengthsIdentified.rawValue,
                onBegin: { _ in
                    let title = """
                        Starting Phase 4: Strategic Synthesis. Begin by analyzing all gathered evidence \
                        (writing samples, timeline, knowledge cards) to identify the candidate's key differentiators. \
                        Present 2-3 strategic strengths with evidence from the collected materials. \
                        Use get_user_option for structured feedback. Ask: "Does this resonate? What would you add?"
                        """
                    let details = [
                        "action": "synthesize_strengths",
                        "objective": OnboardingObjectiveId.strengthsIdentified.rawValue,
                        "approach": "evidence_based_analysis"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { context in
                    let title = """
                        Strengths identified. Now analyze potential concerns and pitfalls. \
                        Look for gaps in employment, transitions that need framing, or areas \
                        where the candidate might face skepticism. For each pitfall, suggest a mitigation strategy.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.pitfallsDocumented.rawValue,
                        "status": context.status.rawValue
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Pitfalls Analysis
            OnboardingObjectiveId.pitfallsDocumented.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.pitfallsDocumented.rawValue,
                dependsOn: [OnboardingObjectiveId.strengthsIdentified.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Pitfalls documented with mitigation strategies. Now fill any remaining dossier gaps. \
                        Check for: availability, work arrangement preferences, unique circumstances, \
                        and any other context needed for job applications. \
                        Use get_user_option for rapid structured questions to fill gaps.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.dossierComplete.rawValue,
                        "status": context.status.rawValue,
                        "action": "fill_dossier_gaps"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Dossier Completion
            OnboardingObjectiveId.dossierComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.dossierComplete.rawValue,
                dependsOn: [OnboardingObjectiveId.pitfallsDocumented.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Dossier complete. Now configure experience defaults for resume generation. \
                        Call submit_experience_defaults with structured data based on the skeleton timeline \
                        enriched with knowledge cards. Include work, education, skills, and projects sections.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.experienceDefaultsSet.rawValue,
                        "status": context.status.rawValue,
                        "action": "call_submit_experience_defaults"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Experience Defaults
            OnboardingObjectiveId.experienceDefaultsSet.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.experienceDefaultsSet.rawValue,
                dependsOn: [OnboardingObjectiveId.dossierComplete.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Experience defaults configured. Interview complete! \
                        Summarize what was accomplished: voice primers, knowledge cards, strategic dossier, \
                        and resume defaults. Explain next steps (resume customization, cover letter generation). \
                        Then call next_phase to complete the interview.
                        """
                    let details = [
                        "status": context.status.rawValue,
                        "action": "call_next_phase"
                    ]
                    // LLM decides when to call next_phase based on context (no forced toolChoice)
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }

    var introductoryPrompt: String {
        PromptLibrary.phase4Intro
    }
}
