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

    var initialTodoItems: [InterviewTodoItem] {
        [
            InterviewTodoItem(
                content: "Synthesize strategic strengths with evidence",
                status: .pending,
                activeForm: "Synthesizing strengths"
            ),
            InterviewTodoItem(
                content: "Document pitfalls with mitigation strategies",
                status: .pending,
                activeForm: "Documenting pitfalls"
            ),
            InterviewTodoItem(
                content: "Fill remaining dossier gaps",
                status: .pending,
                activeForm: "Completing dossier"
            ),
            InterviewTodoItem(
                content: "Generate and curate identity title sets (if enabled)",
                status: .pending,
                activeForm: "Generating title sets"
            ),
            InterviewTodoItem(
                content: "Generate experience defaults",
                status: .pending,
                activeForm: "Generating experience defaults"
            ),
            InterviewTodoItem(
                content: "Submit dossier for validation",
                status: .pending,
                activeForm: "Submitting dossier"
            ),
            InterviewTodoItem(
                content: "Summarize interview and complete onboarding",
                status: .pending,
                activeForm: "Completing interview"
            )
        ]
    }

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
                        "approach": "evidence_based_analysis"
                    ]
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { _ in
                    let title = """
                        Strengths identified. Now analyze potential concerns and pitfalls. \
                        Look for gaps in employment, transitions that need framing, or areas \
                        where the candidate might face skepticism. For each pitfall, suggest a mitigation strategy.
                        """
                    return [.coordinatorMessage(title: title, details: [:], payload: nil)]
                }
            ),

            // MARK: - Pitfalls Analysis
            OnboardingObjectiveId.pitfallsDocumented.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.pitfallsDocumented.rawValue,
                dependsOn: [OnboardingObjectiveId.strengthsIdentified.rawValue],
                autoStartWhenReady: true,
                onComplete: { _ in
                    let title = """
                        Pitfalls documented with mitigation strategies. Now fill any remaining dossier gaps. \
                        Check for: availability, work arrangement preferences, unique circumstances, \
                        and any other context needed for job applications. \
                        Use get_user_option for rapid structured questions to fill gaps.
                        """
                    return [.coordinatorMessage(title: title, details: ["action": "fill_dossier_gaps"], payload: nil)]
                }
            ),

            // MARK: - Dossier Completion
            OnboardingObjectiveId.dossierComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.dossierComplete.rawValue,
                dependsOn: [OnboardingObjectiveId.pitfallsDocumented.rawValue],
                autoStartWhenReady: true,
                onComplete: { _ in
                    let title = """
                        Dossier complete. Next is experience defaults generation. \
                        If custom.jobTitles was enabled in configure_enabled_sections, \
                        have the user curate identity title sets in the tool pane before calling generate_experience_defaults. \
                        Otherwise, call generate_experience_defaults to launch the Experience Defaults agent. \
                        The agent has access to all knowledge cards, skills, and timeline data, \
                        and will generate high-quality, resume-ready content automatically.
                        """
                    return [.coordinatorMessage(title: title, details: ["action": "call_generate_experience_defaults"], payload: nil)]
                }
            ),

            // MARK: - Experience Defaults
            OnboardingObjectiveId.experienceDefaultsSet.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.experienceDefaultsSet.rawValue,
                dependsOn: [OnboardingObjectiveId.dossierComplete.rawValue],
                autoStartWhenReady: true,
                onBegin: { _ in
                    let title = """
                        Starting experience defaults generation. \
                        If custom.jobTitles was enabled, first guide the user to curate identity title sets \
                        in the tool pane, then proceed with generate_experience_defaults. \
                        If custom.jobTitles is not enabled, proceed directly to generate_experience_defaults.
                        """
                    return [.coordinatorMessage(title: title, details: ["action": "prepare_experience_defaults"], payload: nil)]
                },
                onComplete: { _ in
                    let title = """
                        Experience defaults configured. Interview complete! \
                        Summarize what was accomplished: voice primers, knowledge cards, strategic dossier, \
                        and resume defaults. Explain next steps (resume customization, cover letter generation). \
                        Then call next_phase to complete the interview.
                        """
                    return [.coordinatorMessage(title: title, details: ["action": "call_next_phase"], payload: nil)]
                }
            )
        ]
    }

    var introductoryPrompt: String {
        PromptLibrary.phase4Intro
    }
}
