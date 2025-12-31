//
//  PhaseOneScript.swift
//  Sprung
//
//  Phase 1: Voice & Context — Front-load writing samples, capture voice primers,
//  understand job search context, and collect applicant profile.
//
//  INTERVIEW REVITALIZATION PLAN:
//  This phase prioritizes writing samples FIRST to enable voice analysis before
//  document collection. The interviewer should be warm, curious, and explain WHY
//  writing samples help ("...helps me craft applications that sound like you").
//
//  TOOL AVAILABILITY: Defined in ToolBundlePolicy.swift (single source of truth)
//
//  FLOW:
//  1. Welcome + explain value of writing samples
//  2. Collect writing samples (cover letters, emails, proposals)
//     └── Voice primer extraction runs in background
//  3. Initial dossier questions (job search context, priorities)
//  4. Quick profile intake (contact info)
//  5. Validate profile and transition to Phase 2
//
import Foundation

struct PhaseOneScript: PhaseScript {
    let phase: InterviewPhase = .phase1VoiceContext

    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .writingSamplesCollected,  // At least one substantial writing sample
        .jobSearchContextCaptured, // Core dossier field populated
        .applicantProfileComplete  // Contact info validated
        // voicePrimersExtracted is NOT required - it runs in background and may complete after phase advance
    ])

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            // MARK: - Writing Samples Collection
            OnboardingObjectiveId.writingSamplesCollected.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.writingSamplesCollected.rawValue,
                onBegin: { _ in
                    let title = """
                        BE WARM AND EXPLAIN VALUE: Welcome the user and explain why writing samples help. \
                        Say something like: "Before we dive into your work history, I'd love to see how you write. \
                        Cover letters, professional emails, even thoughtful LinkedIn messages—anything that shows your voice \
                        helps me craft applications that sound authentically like you." \
                        Then call get_user_upload to show the upload form, or ask if they'd like to paste text in chat.
                        """
                    let details = [
                        "action": "call_get_user_upload_or_ask_for_paste",
                        "objective": OnboardingObjectiveId.writingSamplesCollected.rawValue,
                        "upload_type": "writing_sample",
                        "allowed_types": "pdf,docx,txt,md"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { context in
                    let title = """
                        Writing sample captured. Voice primer extraction is running in background. \
                        Now gather job search context using get_user_option for structured questions. \
                        Ask about: what's driving their search, what matters most in their next role. \
                        Follow up conversationally based on their answers.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.jobSearchContextCaptured.rawValue,
                        "status": context.status.rawValue
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Voice Primers (Background)
            OnboardingObjectiveId.voicePrimersExtracted.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.voicePrimersExtracted.rawValue,
                dependsOn: [OnboardingObjectiveId.writingSamplesCollected.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    // Voice primers complete in background - no interruption needed
                    let title = """
                        Voice primer extraction complete. Voice patterns have been analyzed and stored. \
                        Continue with current workflow without interruption.
                        """
                    let details = ["status": context.status.rawValue, "background": "true"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Job Search Context
            OnboardingObjectiveId.jobSearchContextCaptured.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.jobSearchContextCaptured.rawValue,
                dependsOn: [OnboardingObjectiveId.writingSamplesCollected.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Job search context captured. Now collect contact information. \
                        Call get_applicant_profile to show the profile card, or ask for contact details. \
                        Keep it brief: name, email, phone, location are the essentials.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.applicantProfileComplete.rawValue,
                        "status": context.status.rawValue,
                        "action": "call_get_applicant_profile"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Applicant Profile
            OnboardingObjectiveId.applicantProfileComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.applicantProfileComplete.rawValue,
                dependsOn: [OnboardingObjectiveId.jobSearchContextCaptured.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Profile validated. All Phase 1 objectives are satisfied. \
                        Transition to Phase 2 to build the career timeline. \
                        Brief the user: "I have your writing samples, understand your priorities, and have your contact info. \
                        Next, let's build out your career timeline."
                        """
                    let details = [
                        "status": context.status.rawValue,
                        "action": "call_next_phase",
                        "immediate": "true"
                    ]
                    // Force next_phase tool call
                    return [.developerMessage(title: title, details: details, payload: nil, toolChoice: OnboardingToolName.nextPhase.rawValue)]
                }
            ),

            // MARK: - Legacy Objective Support (for backwards compatibility)
            OnboardingObjectiveId.contactDataValidated.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.contactDataValidated.rawValue,
                onComplete: { _ in [] }  // No-op, handled by new objectives
            ),
            OnboardingObjectiveId.contactPhotoCollected.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.contactPhotoCollected.rawValue,
                onComplete: { _ in [] }  // No-op, photo is optional in new flow
            )
        ]
    }

    var introductoryPrompt: String {
        PromptLibrary.phase1Intro
    }
}
