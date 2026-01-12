//
//  PhaseTwoScript.swift
//  Sprung
//
//  Phase 2: Career Story — Section configuration, timeline collection,
//  enrichment interviews, section cards, and dossier weaving.
//
//  INTERVIEW REVITALIZATION PLAN:
//  The interviewer now has voice context from Phase 1. It should ACTIVELY interview
//  about each position (not just collect dates), weave dossier questions naturally
//  into conversation, and collect non-chronological sections.
//
//  TOOL AVAILABILITY: Defined in ToolBundlePolicy.swift (single source of truth)
//
//  FLOW:
//  1. Section configuration (FIRST - determines which cards to collect)
//  2. Timeline collection (resume upload OR conversational, gated by enabled sections)
//  3. ACTIVE interviewing about each role:
//     - "What did you build there?"
//     - "What made you leave?"
//     - "What would you do differently?"
//  4. Section cards collection (awards, publications, languages, references)
//     - Publications: offer CV/BibTeX upload OR conversational fallback
//     - Others: conversational collection
//  5. Dossier questions woven in naturally throughout
//  6. Transition to Phase 3
//
import Foundation

struct PhaseTwoScript: PhaseScript {
    let phase: InterviewPhase = .phase2CareerStory

    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .enabledSections,                // FIRST: User configures which sections to include
        .skeletonTimelineComplete,       // All chronological positions captured with dates
        .timelineEnriched,               // Each position has context beyond dates
        .sectionCardsComplete            // Non-chronological sections collected (awards, publications, etc.)
        // workPreferencesCaptured and uniqueCircumstancesDocumented are gathered throughout, not required
    ])

    var initialTodoItems: [InterviewTodoItem] {
        [
            InterviewTodoItem(
                content: "Configure enabled resume sections",
                status: .pending,
                activeForm: "Configuring resume sections"
            ),
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
                content: "Collect non-chronological section cards",
                status: .pending,
                activeForm: "Collecting section cards"
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
            // MARK: - Section Configuration (FIRST in Phase 2)
            // Determines which timeline card types and section cards to collect
            OnboardingObjectiveId.enabledSections.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.enabledSections.rawValue,
                onBegin: { _ in
                    let title = """
                        Phase 2 starting. First, configure which resume sections to include. \
                        Call configure_enabled_sections to show the section toggle UI. \
                        This determines which types of timeline cards and section cards we'll collect.
                        """
                    let details = [
                        "action": "call_configure_enabled_sections"
                    ]
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { _ in
                    let title = """
                        Sections configured. Now offer resume upload OR conversational collection: \
                        "Let's map out your career timeline. Do you have a resume or LinkedIn export I can start from? \
                        Or if you prefer, just walk me through your work history and I'll build the timeline as we talk." \
                        Call get_user_upload with upload_type='resume' to show the upload form.
                        """
                    return [.coordinatorMessage(title: title, details: ["action": "call_get_user_upload"], payload: nil)]
                }
            ),

            // MARK: - Timeline Collection
            OnboardingObjectiveId.skeletonTimelineComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.skeletonTimelineComplete.rawValue,
                dependsOn: [OnboardingObjectiveId.enabledSections.rawValue],
                autoStartWhenReady: true,
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
            OnboardingObjectiveId.timelineEnriched.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.timelineEnriched.rawValue,
                dependsOn: [OnboardingObjectiveId.skeletonTimelineComplete.rawValue],
                autoStartWhenReady: true,
                onComplete: { _ in
                    let title = """
                        Timeline enriched. Now collect non-chronological sections based on enabled sections. \
                        Check which sections are enabled (awards, publications, languages, references). \
                        For publications: offer CV/BibTeX upload OR interview fallback. \
                        For other sections: use conversational collection with create_section_card. \
                        Call display_section_cards_for_review when done to show the editor.
                        """
                    return [.coordinatorMessage(title: title, details: ["action": "collect_section_cards"], payload: nil)]
                }
            ),

            // MARK: - Section Cards Collection (Awards, Publications, Languages, References)
            OnboardingObjectiveId.sectionCardsComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.sectionCardsComplete.rawValue,
                dependsOn: [OnboardingObjectiveId.timelineEnriched.rawValue],
                autoStartWhenReady: true,
                onComplete: { _ in
                    let title = """
                        Section cards collected. All Phase 2 objectives complete. \
                        Ready to advance to Phase 3 (Evidence Collection). \
                        Call next_phase to proceed.
                        """
                    return [.coordinatorMessage(title: title, details: ["action": "call_next_phase"], payload: nil)]
                }
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
            )
        ]
    }

    var introductoryPrompt: String {
        PromptLibrary.phase2Intro
    }
}
