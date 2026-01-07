//
//  PhaseTwoScript.swift
//  Sprung
//
//  Phase 2: Career Story — Active timeline collection, enrichment interviews,
//  dossier weaving, and document suggestions.
//
//  INTERVIEW REVITALIZATION PLAN:
//  The interviewer now has voice context from Phase 1. It should ACTIVELY interview
//  about each position (not just collect dates), weave dossier questions naturally
//  into conversation, and suggest specific documents based on timeline gaps.
//
//  TOOL AVAILABILITY: Defined in ToolBundlePolicy.swift (single source of truth)
//
//  FLOW:
//  1. Timeline collection (resume upload OR conversational)
//  2. ACTIVE interviewing about each role:
//     - "What did you build there?"
//     - "What made you leave?"
//     - "What would you do differently?"
//  3. Dossier questions woven in naturally:
//     - Work arrangement preferences (when discussing locations)
//     - Unique circumstances (when discussing gaps/pivots)
//  4. Section configuration
//  5. Document suggestions based on timeline gaps
//  6. Transition to Phase 3
//
import Foundation

struct PhaseTwoScript: PhaseScript {
    let phase: InterviewPhase = .phase2CareerStory

    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .skeletonTimelineComplete,       // All positions captured with dates
        .timelineEnriched,               // Each position has context beyond dates
        .enabledSections                 // User has configured sections
        // workPreferencesCaptured and uniqueCircumstancesDocumented are gathered throughout, not required
    ])

    var initialTodoItems: [InterviewTodoItem] {
        [
            InterviewTodoItem(
                content: "Offer resume/LinkedIn upload or conversational timeline",
                status: .pending,
                activeForm: "Offering timeline input options"
            ),
            InterviewTodoItem(
                content: "Generate timeline cards from input",
                status: .pending,
                activeForm: "Generating timeline cards"
            ),
            InterviewTodoItem(
                content: "Tune timeline cards based on user feedback",
                status: .pending,
                activeForm: "Tuning timeline cards"
            ),
            InterviewTodoItem(
                content: "Submit timeline for validation",
                status: .pending,
                activeForm: "Submitting timeline for validation"
            ),
            InterviewTodoItem(
                content: "Configure enabled resume sections",
                status: .pending,
                activeForm: "Configuring resume sections"
            ),
            InterviewTodoItem(
                content: "Advance to Phase 3",
                status: .pending,
                activeForm: "Advancing to Phase 3"
            )
        ]
    }

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            // MARK: - Timeline Collection
            OnboardingObjectiveId.skeletonTimelineComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.skeletonTimelineComplete.rawValue,
                onBegin: { _ in
                    let title = """
                        Phase 2 starting. Offer resume upload OR conversational collection: \
                        "Let's map out your career timeline. Do you have a resume or LinkedIn export I can start from? \
                        Or if you prefer, just walk me through your work history and I'll build the timeline as we talk." \
                        Call get_user_upload with upload_type='resume' to show the upload form.
                        """
                    let details = [
                        "action": "call_get_user_upload",
                        "upload_type": "resume"
                    ]
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { _ in
                    let title = """
                        Skeleton timeline captured. Now ACTIVELY INTERVIEW about each position. \
                        For each role, ask at least one probing question: \
                        - Recent role: "What have you built that you're most proud of?" \
                        - Past roles: "What made you move on from [Company]?" \
                        - Academic roles: "What was your teaching philosophy?" \
                        - Gaps: "I notice about [duration] between roles. What were you focused on?" \
                        Use get_user_option for structured dossier questions when topics arise naturally.
                        """
                    return [.coordinatorMessage(title: title, details: ["interview_approach": "active_probing"], payload: nil)]
                }
            ),

            // MARK: - Timeline Enrichment (Active Interviewing)
            // NOTE: No onComplete handler here. configure_enabled_sections is triggered by
            // next_phase validation blocking (in PhaseScriptRegistry.validatePhaseTwoToThree).
            // This avoids the race condition where timelineEnriched.onComplete fired before
            // the user actually validated the timeline in the popup.
            OnboardingObjectiveId.timelineEnriched.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.timelineEnriched.rawValue,
                dependsOn: [OnboardingObjectiveId.skeletonTimelineComplete.rawValue],
                autoStartWhenReady: true
            ),

            // MARK: - Work Preferences (Dossier Weaving)
            OnboardingObjectiveId.workPreferencesCaptured.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.workPreferencesCaptured.rawValue,
                // Not required, captured opportunistically during timeline enrichment
                onComplete: { _ in
                    let title = "Work preferences captured (remote/location/arrangement)."
                    return [.coordinatorMessage(title: title, details: [:], payload: nil)]
                }
            ),

            // MARK: - Unique Circumstances (Dossier Weaving)
            OnboardingObjectiveId.uniqueCircumstancesDocumented.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.uniqueCircumstancesDocumented.rawValue,
                // Not required, captured opportunistically when gaps/pivots arise
                onComplete: { _ in
                    let title = "Unique circumstances documented (gaps, pivots, constraints)."
                    return [.coordinatorMessage(title: title, details: [:], payload: nil)]
                }
            ),

            // MARK: - Section Configuration
            // NOTE: No onComplete handler needed here. The instruction text in the tool response
            // (from confirmSectionToggle in UIResponseCoordinator) guides Claude to call next_phase.
            // This follows Anthropic's recommended pattern of including guidance WITH tool results
            // rather than using forced toolChoice or developer messages.
            OnboardingObjectiveId.enabledSections.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.enabledSections.rawValue,
                dependsOn: [OnboardingObjectiveId.timelineEnriched.rawValue]
            )
        ]
    }

    var introductoryPrompt: String {
        PromptLibrary.phase2Intro
    }
}
