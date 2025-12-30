//
//  PhaseOneScript.swift
//  Sprung
//
//  Phase 1: Core Facts — Collect applicant profile and skeleton timeline.
//
//  TOOL AVAILABILITY: Defined in ToolBundlePolicy.swift (single source of truth)
//
//  FLOW:
//  1. Collect contact info → validate applicant profile
//  2. Collect timeline (resume upload or manual) → user edits in UI → user clicks "Done with Timeline"
//  3. submit_for_validation → user approves timeline
//  4. configure_enabled_sections → user toggles sections → user clicks "Approve"
//  5. Optional: dossier seed questions
//  6. next_phase to Phase 2
//
import Foundation
struct PhaseOneScript: PhaseScript {
    let phase: InterviewPhase = .phase1CoreFacts
    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .applicantProfile,   // formerly P1.1
        .skeletonTimeline,   // formerly P1.2
        .enabledSections     // formerly P1.3
        // dossierSeed (formerly P1.4) is optional, not required for phase advancement
    ])
    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            // Note: contactSourceSelected and contactDataCollected don't emit developer messages
            // because when contacts import validates the profile, all these objectives complete
            // simultaneously and the user message already contains all needed context.
            OnboardingObjectiveId.contactSourceSelected.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.contactSourceSelected.rawValue,
                onComplete: { _ in [] }  // No message - bundled with user message
            ),
            OnboardingObjectiveId.contactDataCollected.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.contactDataCollected.rawValue,
                dependsOn: [OnboardingObjectiveId.contactSourceSelected.rawValue],
                autoStartWhenReady: true,
                onComplete: { _ in [] }  // No message - bundled with user message
            ),
            OnboardingObjectiveId.contactDataValidated.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.contactDataValidated.rawValue,
                dependsOn: [OnboardingObjectiveId.contactDataCollected.rawValue],
                onComplete: { _ in [] }  // No message - photo prompt handled by onBegin below
            ),
            OnboardingObjectiveId.contactPhotoCollected.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.contactPhotoCollected.rawValue,
                dependsOn: [OnboardingObjectiveId.contactDataValidated.rawValue],
                autoStartWhenReady: true,
                onBegin: { _ in
                    // Proactive: Show the upload form immediately rather than asking first
                    let title = """
                        BE PROACTIVE: IMMEDIATELY call get_user_upload to show the photo upload form. \
                        Tell user: "Next, let's add a profile photo. Upload one here, or say 'skip' to continue without." \
                        The upload UI must be visible BEFORE you mention it. Never describe UI the user can't see yet.
                        """
                    let details = [
                        "action": "call_get_user_upload_immediately",
                        "objective": OnboardingObjectiveId.contactPhotoCollected.rawValue,
                        "upload_type": "generic",
                        "allowed_types": "jpg,jpeg,png",
                        "target_key": "basics.image"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { context in
                    let title = """
                        Profile photo stored successfully. \
                        Resume the Phase 1 sequence without re-requesting another upload.
                        """
                    let details = ["status": context.status.rawValue, "objective": OnboardingObjectiveId.contactPhotoCollected.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            OnboardingObjectiveId.applicantProfile.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.applicantProfile.rawValue,
                dependsOn: [OnboardingObjectiveId.contactDataValidated.rawValue],
                onComplete: { _ in [] }  // No message - photo flow handles next step
            ),
            OnboardingObjectiveId.skeletonTimeline.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.skeletonTimeline.rawValue,
                dependsOn: [OnboardingObjectiveId.contactPhotoCollected.rawValue],
                autoStartWhenReady: true,
                onBegin: { _ in
                    let title = """
                        Skeleton timeline collection starting. Call get_user_upload with upload_type='resume' \
                        and explain: "I've opened an upload form for your resume or LinkedIn profile. This helps me \
                        extract your job history quickly. If you don't have one handy, just tell me your work history \
                        in chat and I'll create the timeline cards manually."
                        """
                    let details = [
                        "action": "call_get_user_upload",
                        "upload_type": "resume",
                        "fallback": "User can dictate job history via chat instead of uploading"
                    ]
                    // Force get_user_upload to ensure resume upload is offered before timeline editing
                    return [.developerMessage(title: title, details: details, payload: nil, toolChoice: OnboardingToolName.getUserUpload.rawValue)]
                },
                onComplete: { context in
                    let title = """
                        Skeleton timeline captured. \
                        Now call configure_enabled_sections to show the section toggle UI. \
                        Based on user's data, propose which sections to enable (work, education, skills, etc.). \
                        Do NOT use get_user_option—use configure_enabled_sections which has the proper section toggle UI.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.enabledSections.rawValue,
                        "status": context.status.rawValue,
                        "action": "call_configure_enabled_sections",
                        "tool": "configure_enabled_sections"
                    ]
                    // Force configure_enabled_sections tool call - weaker models may not execute without forcing
                    return [.developerMessage(title: title, details: details, payload: nil, toolChoice: OnboardingToolName.configureEnabledSections.rawValue)]
                }
            ),
            OnboardingObjectiveId.enabledSections.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.enabledSections.rawValue,
                dependsOn: [OnboardingObjectiveId.skeletonTimeline.rawValue],
                onComplete: { context in
                    var outputs: [ObjectiveWorkflowOutput] = []
                    let dossierTitle = """
                        Enabled sections confirmed. Now ask 2–3 quick questions about the user's goals, motivations, and target roles. \
                        For each answer, call persist_data(dataType: 'candidate_dossier_entry', payload: {question, answer, asked_at}). \
                        After collecting at least 2 answers, mark dossier_seed complete, then IMMEDIATELY call next_phase to advance.
                        """
                    let dossierDetails = [
                        "next_objective": OnboardingObjectiveId.dossierSeed.rawValue,
                        "required": "false",
                        "min_entries": "2",
                        "auto_advance": "true"
                    ]
                    outputs.append(.developerMessage(title: dossierTitle, details: dossierDetails, payload: nil))
                    return outputs
                }
            ),
            OnboardingObjectiveId.dossierSeed.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.dossierSeed.rawValue,
                dependsOn: [OnboardingObjectiveId.enabledSections.rawValue],
                onComplete: { context in
                    let title = """
                        Dossier seed complete. All Phase 1 objectives are satisfied. \
                        Transitioning to Phase 2.
                        """
                    let details = [
                        "status": context.status.rawValue,
                        "action": "call_next_phase",
                        "immediate": "true"
                    ]
                    // Force next_phase tool call - weaker models may acknowledge but not execute without forcing
                    return [.developerMessage(title: title, details: details, payload: nil, toolChoice: OnboardingToolName.nextPhase.rawValue)]
                }
            )
        ]
    }
    var introductoryPrompt: String {
        PromptLibrary.phase1Intro
    }
    }
