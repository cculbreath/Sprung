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
//  1. Welcome + quick profile intake (contact info) - START HERE
//  2. Collect ALL writing samples (cover letters, emails, proposals)
//     └── Voice primer extraction runs in background
//  3. Job search context questions (dossier building)
//  4. Transition to Phase 2
//
import Foundation

struct PhaseOneScript: PhaseScript {
    let phase: InterviewPhase = .phase1VoiceContext

    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .applicantProfileComplete, // Contact info validated (START HERE)
        .writingSamplesCollected,  // All available writing samples collected
        .jobSearchContextCaptured  // Core dossier field populated
        // voicePrimersExtracted is NOT required - it runs in background and may complete after phase advance
    ])

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            // MARK: - Applicant Profile (START HERE)
            OnboardingObjectiveId.applicantProfileComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.applicantProfileComplete.rawValue,
                onBegin: { _ in
                    let title = """
                        START WITH PROFILE: Welcome the user warmly and gather contact information first. \
                        Say: "Welcome! I'm excited to help you build compelling job applications. \
                        Let's start with the basics so I have your contact information ready for resumes and cover letters." \
                        Call validate_applicant_profile to show the profile form. Keep it quick—2-3 minutes max.
                        """
                    let details = [
                        "action": "call_validate_applicant_profile",
                        "objective": OnboardingObjectiveId.applicantProfileComplete.rawValue,
                        "priority": "first"
                    ]
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { context in
                    let title = """
                        Profile validated. Now offer profile photo upload. Call get_user_upload with \
                        target_key="basics.image" and upload_type="photo". If user declines or after photo is uploaded, \
                        transition to writing samples. The sidebar shows a writing sample upload panel. \
                        Encourage uploading MULTIPLE writing samples.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.writingSamplesCollected.rawValue,
                        "status": context.status.rawValue,
                        "step": "profile_photo",
                        "note": "writing_sample_panel_visible_in_sidebar"
                    ]
                    // LLM decides when to call get_user_upload based on context (no forced toolChoice)
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Writing Samples Collection
            OnboardingObjectiveId.writingSamplesCollected.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.writingSamplesCollected.rawValue,
                dependsOn: [OnboardingObjectiveId.applicantProfileComplete.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Writing samples captured. Voice primer extraction is running in background. \
                        Now gather job search context using get_user_option for structured questions. \
                        Ask about: what's driving their search, what matters most in their next role. \
                        Follow up conversationally based on their answers.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.jobSearchContextCaptured.rawValue,
                        "status": context.status.rawValue
                    ]
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
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
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Job Search Context
            OnboardingObjectiveId.jobSearchContextCaptured.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.jobSearchContextCaptured.rawValue,
                dependsOn: [OnboardingObjectiveId.writingSamplesCollected.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Job search context captured. All Phase 1 objectives are satisfied. \
                        Transition to Phase 2 to build the career timeline. \
                        Brief the user: "Perfect. I have your contact info, writing samples, and understand your priorities. \
                        Next, let's build out your career timeline." \
                        Call next_phase to proceed.
                        """
                    let details = [
                        "status": context.status.rawValue,
                        "action": "call_next_phase"
                    ]
                    // LLM decides when to call next_phase based on context (no forced toolChoice)
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }

    var introductoryPrompt: String {
        PromptLibrary.phase1Intro
    }
}
