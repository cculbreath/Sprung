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
                        "objective": OnboardingObjectiveId.skeletonTimelineComplete.rawValue,
                        "upload_type": "resume"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { context in
                    let title = """
                        Skeleton timeline captured. Now ACTIVELY INTERVIEW about each position. \
                        For each role, ask at least one probing question: \
                        - Recent role: "What have you built that you're most proud of?" \
                        - Past roles: "What made you move on from [Company]?" \
                        - Academic roles: "What was your teaching philosophy?" \
                        - Gaps: "I notice about [duration] between roles. What were you focused on?" \
                        Use get_user_option for structured dossier questions when topics arise naturally.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.timelineEnriched.rawValue,
                        "status": context.status.rawValue,
                        "interview_approach": "active_probing"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Timeline Enrichment (Active Interviewing)
            OnboardingObjectiveId.timelineEnriched.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.timelineEnriched.rawValue,
                dependsOn: [OnboardingObjectiveId.skeletonTimelineComplete.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Timeline enriched with context. Now configure enabled sections. \
                        Call configure_enabled_sections with recommendations based on the user's background. \
                        "Based on your experience, I'd suggest including these sections: [list]. Does that sound right?"
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.enabledSections.rawValue,
                        "status": context.status.rawValue,
                        "action": "call_configure_enabled_sections"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil, toolChoice: OnboardingToolName.configureEnabledSections.rawValue)]
                }
            ),

            // MARK: - Work Preferences (Dossier Weaving)
            OnboardingObjectiveId.workPreferencesCaptured.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.workPreferencesCaptured.rawValue,
                // Not required, captured opportunistically during timeline enrichment
                onComplete: { context in
                    let title = "Work preferences captured (remote/location/arrangement)."
                    let details = ["status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Unique Circumstances (Dossier Weaving)
            OnboardingObjectiveId.uniqueCircumstancesDocumented.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.uniqueCircumstancesDocumented.rawValue,
                // Not required, captured opportunistically when gaps/pivots arise
                onComplete: { context in
                    let title = "Unique circumstances documented (gaps, pivots, constraints)."
                    let details = ["status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Section Configuration
            OnboardingObjectiveId.enabledSections.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.enabledSections.rawValue,
                dependsOn: [OnboardingObjectiveId.timelineEnriched.rawValue],
                onComplete: { context in
                    let title = """
                        Enabled sections confirmed. Before transitioning to Phase 3, suggest specific documents: \
                        "To really bring your experience to life, here's what would help: \
                        - For [Position]: Technical reports, design docs \
                        - For [Position]: Performance reviews, teaching evaluations \
                        - Code from your projects \
                        What do you have access to? We'll collect these in the next phase." \
                        Then call next_phase to proceed.
                        """
                    let details = [
                        "status": context.status.rawValue,
                        "action": "suggest_documents_then_next_phase"
                    ]
                    // Force next_phase tool call
                    return [.developerMessage(title: title, details: details, payload: nil, toolChoice: OnboardingToolName.nextPhase.rawValue)]
                }
            )
        ]
    }

    var introductoryPrompt: String {
        PromptLibrary.phase2Intro
    }
}
