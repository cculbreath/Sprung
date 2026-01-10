//
//  PhaseFourScript.swift
//  Sprung
//
//  Phase 4: Strategic Synthesis — Strengths, pitfalls, dossier completion, experience defaults.
//
//  WORKFLOW:
//  1. Analyze evidence and present strategic STRENGTHS (2-3 with evidence) - discuss with user
//  2. Identify potential PITFALLS and suggest mitigation strategies - discuss with user
//  3. Fill any remaining DOSSIER GAPS (availability, preferences, circumstances)
//  4. Call submit_candidate_dossier with all gathered insights
//     → This automatically satisfies: strengthsIdentified, pitfallsDocumented, dossierComplete
//  5. If custom.jobTitles was enabled:
//     → WAIT for user to complete Title Set Curation in tool pane (user-driven)
//     → You'll receive a "Title Sets Curated" notification when ready
//  6. Call generate_experience_defaults (with selected_titles if title sets were curated)
//  7. Summarize and call next_phase to complete
//
//  IMPORTANT: Do NOT rush to submit_candidate_dossier. The synthesis work (strengths analysis,
//  pitfalls analysis, gap-filling questions) must happen FIRST through conversation.
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
                content: "Analyze evidence and present strategic strengths (2-3 with evidence)",
                status: .pending,
                activeForm: "Analyzing strengths"
            ),
            InterviewTodoItem(
                content: "Identify pitfalls and suggest mitigation strategies",
                status: .pending,
                activeForm: "Analyzing pitfalls"
            ),
            InterviewTodoItem(
                content: "Fill remaining dossier gaps (availability, preferences, circumstances)",
                status: .pending,
                activeForm: "Filling dossier gaps"
            ),
            InterviewTodoItem(
                content: "Submit candidate dossier with strengths and pitfalls",
                status: .pending,
                activeForm: "Submitting dossier"
            ),
            InterviewTodoItem(
                content: "Wait for user to complete Title Set curation (if enabled)",
                status: .pending,
                activeForm: "Waiting for title sets"
            ),
            InterviewTodoItem(
                content: "Generate experience defaults",
                status: .pending,
                activeForm: "Generating experience defaults"
            ),
            InterviewTodoItem(
                content: "Summarize interview and call next_phase",
                status: .pending,
                activeForm: "Completing interview"
            )
        ]
    }

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            // MARK: - Strengths Synthesis
            // NOTE: This objective is automatically satisfied when submit_candidate_dossier is called.
            // The workflow guides the LLM to do the analysis work BEFORE calling the tool.
            OnboardingObjectiveId.strengthsIdentified.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.strengthsIdentified.rawValue,
                onBegin: { _ in
                    let title = """
                        Starting Phase 4: Strategic Synthesis.

                        IMPORTANT: Work through your todo list in order. Do NOT skip to submit_candidate_dossier.

                        First, analyze all gathered evidence (writing samples, timeline, knowledge cards) \
                        to identify 2-3 key strategic STRENGTHS with specific evidence. Present these to the user \
                        and discuss: "Does this resonate? What would you add or change?"

                        Use get_user_option for structured feedback on your analysis.
                        """
                    let details = [
                        "action": "synthesize_strengths",
                        "approach": "evidence_based_analysis",
                        "note": "Do conversational analysis BEFORE calling submit_candidate_dossier"
                    ]
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Pitfalls Analysis
            // NOTE: This objective is automatically satisfied when submit_candidate_dossier is called.
            OnboardingObjectiveId.pitfallsDocumented.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.pitfallsDocumented.rawValue,
                dependsOn: [OnboardingObjectiveId.strengthsIdentified.rawValue],
                autoStartWhenReady: false  // Don't auto-start - LLM drives via todos
            ),

            // MARK: - Dossier Completion
            // NOTE: This objective is satisfied when submit_candidate_dossier is called.
            // submit_candidate_dossier also marks strengthsIdentified and pitfallsDocumented complete.
            OnboardingObjectiveId.dossierComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.dossierComplete.rawValue,
                dependsOn: [OnboardingObjectiveId.pitfallsDocumented.rawValue],
                autoStartWhenReady: false,  // Don't auto-start - LLM drives via todos
                onBegin: { _ in
                    let title = """
                        Ready to compile the candidate dossier. QUALITY REQUIREMENTS:

                        BEFORE calling submit_candidate_dossier, ensure you have:

                        1. **jobSearchContext** (200+ chars REQUIRED): Target roles, industries, \
                        motivation for searching, non-negotiables

                        2. **strengthsToEmphasize** (500+ chars recommended): 2-4 PARAGRAPHS with \
                        specific evidence, not bullet points. Include positioning advice for each strength.

                        3. **pitfallsToAvoid** (500+ chars recommended): 2-4 PARAGRAPHS with mitigation \
                        strategies for each concern. Include talking points for interviews.

                        4. **notes** (200+ chars if relevant): Communication style, cultural fit, deal-breakers

                        TARGET: 1,500+ total words. This is a strategy document, not a summary.
                        The tool will validate minimum lengths and return warnings if content is thin.
                        """
                    let details = [
                        "action": "compile_comprehensive_dossier",
                        "minimums": "jobSearchContext=200, strengths=500, pitfalls=500, notes=200",
                        "target": "1500+ total words"
                    ]
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { _ in
                    let title = """
                        Dossier submitted! Next step depends on whether custom.jobTitles was enabled:

                        IF custom.jobTitles was enabled:
                        → The tool pane now shows Title Set Curation
                        → WAIT for the user to generate, select, and save their title sets
                        → You'll receive a "Title Sets Curated" notification with the approved titles
                        → THEN call generate_experience_defaults with the selected_titles parameter

                        IF custom.jobTitles was NOT enabled:
                        → Proceed directly to generate_experience_defaults (no selected_titles needed)
                        """
                    return [.coordinatorMessage(title: title, details: ["action": "await_title_curation_or_generate_defaults"], payload: nil)]
                }
            ),

            // MARK: - Experience Defaults
            OnboardingObjectiveId.experienceDefaultsSet.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.experienceDefaultsSet.rawValue,
                dependsOn: [OnboardingObjectiveId.dossierComplete.rawValue],
                autoStartWhenReady: false,  // Don't auto-start - wait for title curation if needed
                onComplete: { _ in
                    let title = """
                        Experience defaults generated! Interview is nearly complete.

                        Summarize what was accomplished:
                        - Voice primers extracted from writing samples
                        - Knowledge cards generated from evidence
                        - Strategic dossier with strengths and pitfall mitigations
                        - Resume defaults ready for customization

                        Explain next steps (resume customization, cover letter generation, job applications).
                        Then call next_phase to complete the onboarding interview.
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
