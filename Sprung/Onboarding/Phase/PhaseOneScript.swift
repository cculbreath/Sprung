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
        .getContextPack,
        .requestRawFile,
        .nextPhase
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
                onComplete: { _ in [] }  // No message - photo flow handles next step
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
    var introductoryPrompt: String {"""
        ## PHASE 1: CORE FACTS

        Collect user's contact info and career timeline skeleton.

        ### Objectives
        - **applicant_profile**: Name, email, phone, location, URLs, social profiles
        - **skeleton_timeline**: High-level timeline of positions with dates and organizations
        - **enabled_sections**: User chooses which resume sections to include
        - **dossier_seed**: 2-3 questions about goals/target roles → auto-transition to Phase 2

        ### Workflow
        START: Write a warm welcome message, then call `agent_ready`. The tool response contains the complete step-by-step workflow.
        Example: "Welcome! I'm here to help you build a clear, evidence-backed profile we'll later use for tailored resumes and cover letters. Let me get started."

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
