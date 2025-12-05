//
//  PhaseOneScript.swift
//  Sprung
//
//  Phase 1: Core Facts — Collect applicant profile and skeleton timeline.
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
    let allowedTools: [String] = OnboardingToolName.rawValues([
        .agentReady,
        .getUserOption,
        .getApplicantProfile,
        .getUserUpload,
        .cancelUserUpload,
        .createTimelineCard,
        .updateTimelineCard,
        .reorderTimelineCards,
        .deleteTimelineCard,
        .displayTimelineEntriesForReview,
        .getTimelineEntries,
        .submitForValidation,
        .validateApplicantProfile,
        .validatedApplicantProfileData,
        .configureEnabledSections,
        .listArtifacts,
        .getArtifact,
        .requestRawFile,
        .nextPhase
    ])
    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            OnboardingObjectiveId.contactSourceSelected.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.contactSourceSelected.rawValue,
                onComplete: { context in
                    let source = context.details["source"] ?? context.details["status"] ?? "unknown"
                    let title = """
                        Contact source selected: \(source). \
                        Continue guiding the user through the applicant profile intake card that remains on screen.
                        """
                    let details = ["source": source, "next_objective": OnboardingObjectiveId.contactDataCollected.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            OnboardingObjectiveId.contactDataCollected.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.contactDataCollected.rawValue,
                dependsOn: [OnboardingObjectiveId.contactSourceSelected.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let mode = context.details["source"] ?? context.details["status"] ?? "unspecified"
                    let title = "Applicant contact data collected via \(mode). Await validation status before re-requesting any details."
                    let details = ["source": mode, "next_objective": OnboardingObjectiveId.contactDataValidated.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            OnboardingObjectiveId.contactDataValidated.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.contactDataValidated.rawValue,
                dependsOn: [OnboardingObjectiveId.contactDataCollected.rawValue],
                onComplete: { context in
                    // Note: Photo request is handled via contact_photo_collected.onBegin
                    // Keep this message minimal to avoid conflicting instructions
                    let title = "Contact data validated. Photo objective starting next."
                    let details = ["status": context.status.rawValue, "next_step": "contact_photo_collected"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            OnboardingObjectiveId.contactPhotoCollected.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.contactPhotoCollected.rawValue,
                dependsOn: [OnboardingObjectiveId.contactDataValidated.rawValue],
                autoStartWhenReady: true,
                onBegin: { _ in
                    // CRITICAL: This message must stop the LLM from advancing until user responds
                    let title = """
                        STOP AND WAIT FOR USER RESPONSE. \
                        Ask the user: "Would you like to add a profile photo?" and then WAIT for their response. \
                        Do NOT proceed to skeleton timeline until the user explicitly answers yes or no. \
                        If yes, call get_user_upload. If no, mark contact_photo_collected as skipped and continue.
                        """
                    let details = [
                        "action": "wait_for_user_response",
                        "objective": OnboardingObjectiveId.contactPhotoCollected.rawValue,
                        "blocking": "true"
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
                onComplete: { context in
                    // Note: This fires after contactDataValidated, but the photo flow
                    // may still be waiting for user response. DO NOT add instructions here
                    // that would cause the LLM to advance.
                    let title = "Applicant profile data persisted. (Informational only - do not change current workflow.)"
                    let details = ["status": context.status.rawValue, "informational": "true"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            OnboardingObjectiveId.skeletonTimeline.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.skeletonTimeline.rawValue,
                dependsOn: [OnboardingObjectiveId.applicantProfile.rawValue],
                onComplete: { context in
                    let title = """
                        Skeleton timeline captured. \
                        Prepare the user to choose enabled résumé sections.
                        """
                    let details = ["next_objective": OnboardingObjectiveId.enabledSections.rawValue, "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
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
                        Call next_phase NOW to transition to Phase 2.
                        """
                    let details = [
                        "status": context.status.rawValue,
                        "action": "call_next_phase",
                        "immediate": "true"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }
    var introductoryPrompt: String {"""
        ## PHASE 1: CORE FACTS

        Collect user's contact info and career timeline skeleton.

        ### Objectives
        - **applicant_profile**: Name, email, phone, location, URLs, social profiles
        - **skeleton_timeline**: High-level timeline of positions with dates and organizations
        - **enabled_sections**: User chooses which resume sections to include
        - **dossier_seed**: 2-3 questions about goals/target roles → auto-transition to Phase 2

        ### Workflow
        START: Call `agent_ready`. The tool response contains the complete step-by-step workflow.

        ### Coordinator Messages
        Developer messages with "Objective update:" or "Developer status:" are authoritative. Don't re-validate completed objectives—acknowledge and proceed.

        ### Timeline Principles
        - Phase 1 captures skeleton only: titles, companies, schools, locations, dates
        - Don't write descriptions, highlights, or bullet points yet—that's Phase 2
        - Trust user edits to timeline cards without confirming each one
        - When user requests changes via chat, act programmatically (delete/create/update cards)

        ### Constraints
        - Finish applicant_profile before skeleton_timeline
        - After enabled_sections, ask dossier questions then IMMEDIATELY call `next_phase`
        - Use first name only after profile is confirmed

        ### Communication Style
        - Move quickly through data collection—don't over-explain each step
        - Skip acknowledgments when the next action is obvious
        - Trust user-provided data without echoing it back for confirmation
        """}
    }
