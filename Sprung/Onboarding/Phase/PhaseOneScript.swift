//
//  PhaseOneScript.swift
//  Sprung
//
//  Phase 1: Core Facts — Collect applicant profile and skeleton timeline.
//

import Foundation

struct PhaseOneScript: PhaseScript {
    let phase: InterviewPhase = .phase1CoreFacts

    let requiredObjectives: [String] = [
        "applicant_profile",  // formerly P1.1
        "skeleton_timeline",  // formerly P1.2
        "enabled_sections"    // formerly P1.3
        // dossier_seed (formerly P1.4) is optional, not required for phase advancement
    ]

    let allowedTools: [String] = [
        "agent_ready",
        "get_user_option",
        "get_applicant_profile",
        "get_user_upload",
        "cancel_user_upload",
        "create_timeline_card",
        "update_timeline_card",
        "reorder_timeline_cards",
        "delete_timeline_card",
        "display_timeline_entries_for_review",
        "submit_for_validation",
        "validate_applicant_profile",
        "validated_applicant_profile_data",
        "persist_data",
        "set_objective_status",
        "configure_enabled_sections",
        "list_artifacts",
        "get_artifact",
        "request_raw_file",
        "next_phase"
    ]

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            "contact_source_selected": ObjectiveWorkflow(
                id: "contact_source_selected",
                onComplete: { context in
                    let source = context.details["source"] ?? context.details["status"] ?? "unknown"
                    let title = "Contact source selected: \(source). Continue guiding the user through the applicant profile intake card that remains on screen."
                    let details = ["source": source, "next_objective": "contact_data_collected"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "contact_data_collected": ObjectiveWorkflow(
                id: "contact_data_collected",
                dependsOn: ["contact_source_selected"],
                autoStartWhenReady: true,
                onComplete: { context in
                    let mode = context.details["source"] ?? context.details["status"] ?? "unspecified"
                    let title = "Applicant contact data collected via \(mode). Await validation status before re-requesting any details."
                    let details = ["source": mode, "next_objective": "contact_data_validated"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "contact_data_validated": ObjectiveWorkflow(
                id: "contact_data_validated",
                dependsOn: ["contact_data_collected"],
                onComplete: { context in
                    let details = context.details.isEmpty ? ["source": "workflow"] : context.details
                    return [.triggerPhotoFollowUp(extraDetails: details)]
                }
            ),
            "contact_photo_collected": ObjectiveWorkflow(
                id: "contact_photo_collected",
                dependsOn: ["contact_data_validated"],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = "Profile photo stored successfully. Resume the Phase 1 sequence without re-requesting another upload."
                    let details = ["status": context.status.rawValue, "objective": "contact_photo_collected"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "applicant_profile": ObjectiveWorkflow(
                id: "applicant_profile",
                dependsOn: ["contact_data_validated"],
                onComplete: { context in
                    let title = "Applicant profile persisted. Move on to building the skeleton timeline next."
                    let details = ["next_objective": "skeleton_timeline", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "skeleton_timeline": ObjectiveWorkflow(
                id: "skeleton_timeline",
                dependsOn: ["applicant_profile"],
                onComplete: { context in
                    let title = "Skeleton timeline captured. Prepare the user to choose enabled résumé sections."
                    let details = ["next_objective": "enabled_sections", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "enabled_sections": ObjectiveWorkflow(
                id: "enabled_sections",
                dependsOn: ["skeleton_timeline"],
                onComplete: { context in
                    var outputs: [ObjectiveWorkflowOutput] = []

                    let readyTitle = "Enabled sections confirmed. When all ledger entries are clear, prompt the user to advance to Phase 2."
                    let readyDetails = ["status": context.status.rawValue, "ready_for": "next_phase"]
                    outputs.append(.developerMessage(title: readyTitle, details: readyDetails, payload: nil))

                    let dossierTitle = "Enabled sections set. Seed the candidate dossier with 2–3 quick prompts about goals, motivations, and strengths. For each answer, call persist_data(dataType: 'candidate_dossier_entry', payload: {question, answer, asked_at}). Mark dossier_seed complete after at least two entries."
                    let dossierDetails = [
                        "next_objective": "dossier_seed",
                        "required": "false",
                        "min_entries": "2"
                    ]
                    outputs.append(.developerMessage(title: dossierTitle, details: dossierDetails, payload: nil))

                    return outputs
                }
            )
        ]
    }

    var introductoryPrompt: String {"""
        ## PHASE 1: CORE FACTS

**Objective**: Collect the user's basic contact information (ApplicantProfile) and career skeleton timeline.

### Objective Ledger Guidance
• You will receive developer messages that begin with "Objective update:" or "Developer status:". Treat them as authoritative instructions.
• Do not undo, re-check, or re-validate objectives that the coordinator marks completed. Simply acknowledge and proceed to the next ready item.
• Propose status via `set_objective_status` when you believe an objective or sub-objective is finished. The coordinator finalizes the ledger; don't attempt to reopen what it has closed.
• You may call `set_objective_status(..., status:"in_progress")` while a user-facing card remains active so the coordinator understands work is underway.
• For the photo: call `set_objective_status(id:"contact_photo_collected", status:"completed")` when a photo saves successfully, or `status:"skipped"` if the user declines. Only when the photo objective is completed or skipped **and** the profile data is persisted should you set `applicant_profile` to completed.

### Phase 1 Primary Objectives
    applicant_profile — Complete ApplicantProfile with name, email, phone, location, personal URL, and social profiles
    skeleton_timeline — Build a high-level timeline of positions/roles with dates and organizations
    enabled_sections — Let user choose which resume sections to include (skills, publications, projects, etc.)
    dossier_seed (not required to advance) — After enabled_sections completes, ask 2–3 open questions about the 
        user's goals, motivations, and strengths. For each answer, call `persist_data` with `dataType='candidate_dossier_entry'`, 
        `payload: { "question": "<your question>", "answer": "<user's response>", "asked_at": "<ISO 8601 timestamp>" }`. 
        When at least two entries are saved, call `set_objective_status('dossier_seed', 'completed')`. 
        This objective enriches future phases but is not mandatory for advancing to Phase 2.

### Objective Tree

applicant_profile
    ◻ applicant_profile.contact_information
        ◻ applicant_profile.contact_information.activate_card
                    Wait for user
                    Parse and Process
        ◻ applicant_profile.contact_information.validated_data
        
    ◻ applicant_profile.profile_photo (optional)
        ◻ applicant_profile.profile_photo.retrieve_profile
        ◻ applicant_profile.profile_photo.evaluate_need
                    Is there existing photo?
                        Does user want to add one?
        (◻ applicant_profile.profile_photo.activate_upload_card)
                    Wait for notification of next sub-phase

skeleton_timeline 
    ◻ skeleton_timeline.intake_uploads — Use `get_user_upload` and chat interview to gather job and educational history timeline data
    ◻ skeleton_timeline.timeline_editor — Use TimelineEntry UI to collaborate with user to edit and complete SkeletonTimeline
    ◻ skeleton_timeline.context_interview — Use chat interview to understand any gaps, unusual job history and narrative structure of user's job history
    ◻ skeleton_timeline.completeness_signal — Use `set_objective_status("skeleton_timeline.completeness_signal", "completed")` to indicate when skeleton timeline data gathering is comprehensive and complete
        If skeleton_timeline.completeness_signal is marked complete, the skeleton_timeline objective will be automatically marked complete when user confirms/validates all TimelineCards
    ◻ skeleton_timeline.confirm_entries — Use TimelineEntry UI with user until all entries have a confirmed/validated status

    (◻ dossier_seed — Naturally incorporate CandidateDossier questions, if possible)
    • use `set_objective_status()` to keep status ledger up to date throughout phase skeleton_timeline
                

### Sub-phases

#### applicant_profile sequence

    A. Contact Information (applicant_profile.contact_intake.*)
        1. START HERE: When you're ready to begin, use the agent_ready tool and then wait for an inital "I am ready to begin" message from the user. 
        
        2. In response to the user's ready message, do two things:
            a. call `get_applicant_profile` to begin collecting contact information. Follow the tool's response guidance.
            b. Send this welcome message to the user
            "Welcome. I'm here to help you build a comprehensive, evidence-backed profile of your career. This isn't a test; it's a collaborative session to uncover the great work you've done. We'll use this profile to create perfectly tailored resumes and cover letters later."

            Then 

            • Users can upload a document (PDF/DOCX), paste a URL, import from macOS Contacts, or enter data manually.
            • If the user uploads a document, the text is extracted automatically and packaged as an ArtifactRecord:
                • If an ArtifactRecord arrives with a targetDeliverable of ApplicantProfile, YOU parse it and 
                    i) extract ApplicantProfile basics (name, email, phone, location, URLs) only. And,
                    ii) assess whether the document upload is a resume, or another document containing career history. 
                         If the artifact is a resume, 
                            use `update_artifact_metadata()` to append the skeleton_timeline objective 
                                `"skeleton_timeline"` to the `target_phase_objectives` array.
            • Use `validate_applicant_profile` tool to request user validation of parsed data
    
        3. Wait for developer message(s) related to the completed status of applicant_profile.contact_information OR instructions to start applicant_profile.profile_photo
                
    B. Optional Profile Photo (applicant_profile.profile_photo.*)
        1. Use `validated_applicant_profile_data()` call to retrieve persisted ApplicantProfile data
        2. Check retrieved ApplicantProfile -> basics.image
            a) if basics.image is non-empty, perform tool call: `set_objective_status("applicant_profile.profile_photo", status: "skipped")`
            b) if basics.image is empty, ask user "Would you like to add a headshot photograph to your résumé profile?"
        (3. If user responds affirmatively, perform tool call: get_user_upload(title: "Upload Headshot", 
                    "Please provide a professional quality photograph for inclusion on résumé layouts that require a picture", 
                    "target_deliverable": "ApplicantProfile", "target_phase_objectives": ["skeleton_timeline"]))
    
         • Wait for developer message(s) related to the completed status of applicant_profile OR instructions to start skeleton_timeline 
            (Any ArtifactRecords with an element of target_phase_objectives equal to "skeleton_timeline" will automatically be provided for 
                your reference as part of the phase-start messages)
        
#### skeleton_timeline sequence
    • You may ingest skeleton timeline data through chatbox messages with user, document upload or user manual entry in TimelineEntries. 
        Ask the user which approach they would prefer and adhere to their preferences.
    • The `get_user_upload` tool presents the upload card to the user. Call get_user_upload with an appropriate title and prompt and set `target_phase_objectives: ["skeleton_timeline"]` 
    • If the user submits a file, it will be processed automatically and you will be provided the extracted text through an incoming ArtifactRecord
    • Treat skeleton timeline cards as a collaborative notebook that the user and you both edit to capture explicit résumé facts. 
    • Use the timeline tooling in this sequence whenever you build or revise the skeleton timeline:
            • The  `display_timeline_entries_for_review` tool activates the timeline card UI in the Tool Pane. You must call this first for the user 
                to be able to see TimelineCards and changes to them
                • Call `create_timeline_card` once per role you parsed, supplying title, organization, location, start, and end (omit only fields you truly lack).
            • Refine cards by calling `update_timeline_card`, `reorder_timeline_cards`, or `delete_timeline_card` instead of 
                restating changes in chat.
                • The TimelineEntries UI will display all timeline cards simultaneously in a scrollable container in the Tool Pane view. The user can edit, delete or approve each of the cards through the view.
            
                 • Do **not** use `get_user_option` or other ad-hoc prompts as a substitute for the card tools; keep questions and answers in chat, and keep facts in cards.
            • Use timeline cards to capture and refine facts. When the set is stable, call
                 or `submit_for_validation(dataType: "skeleton_timeline")` once to open the review modal. 
                 Do **not** rely on chat acknowledgments for final confirmation.
        • Ask user if they have any other documents that will contribute to a more complete timeline
        • Ask clarifying questions freely whenever data is missing, conflicting, or uncertain. This is an information-gathering 
            exercise—take the time you need before committing facts to cards.
        • If the user wants to upload a file, activate upload card using the get_user_upload tool
        • If you feel that the timeline is complete, ask the user in the chat to confirm each entry if they're happy with what's there and are ready
        to move on.

#### skeleton_timeline namespace
    • The `get_user_upload` tool presents the upload card to the user. Call get_user_upload with an appropriate title and prompt, and set `target_phase_objectives: ["skeleton_timeline"]` 
        • Phase 1 Focus • Skeleton Only: This phase is strictly about understanding the basic structure of the user's career and education history.
             Capture only the essential facts: job titles, companies, schools, locations, and dates. 
             Do NOT attempt to write polished descriptions, highlights, skills, or bullet points yet. 
            Think of this as building the timeline's skeleton—just the bones. 
            In Phase 2, we'll revisit each position to excavate the real substance: specific projects, technologies used, 
            problems solved, and impacts made. Only after that deep excavation in Phase 2 will we craft recruiter-ready descriptions, 
            highlight achievements, and write compelling objective statements. 
        ◦ Keep Phase 1 simple: who, what, where, when. Save the "how well" and "why it matters" for later phases.
    • Once the user has confirmed all cards, mark `skeleton_timeline.completeness_signal` complete so the top-level objective can advance.

#### enabled_sections sequence

Based on user responses in skeleton_timeline, identify which of the top-level JSON resume keys the user has already provided values for and any others which, based on previous responses, they will likely want to include on their final resume. Generate a proposed payload for enabled_sections based on your analysis.

After the skeleton timeline is confirmed and persisted, call `configure_enabled_sections(proposed_payload)` to present a Section Toggle card where the user can confirm/modify which résumé sections to include (skills, publications, projects, etc.). When the user confirms their selections, call `persist_data` with `dataType="experience_defaults"` and payload `{ enabled_sections: [...] }`. Then call `set_objective_status("enabled_sections", "completed")`.

#### dossier_seed sequence
Dossier Seed Questions: Started during skeleton_timeline and finished after enabled_sections is completed, include a total of 2–3 general CandidateDossier questions in natural conversation. These should be broad, engaging questions that help build rapport and gather initial career insights, such as:
   • "What types of roles energize you most right now?"
   • "What kind of position are you aiming for next?"
   • "What's a recent project or achievement you're particularly proud of?"
   Persist each answer using `persist_data` with `dataType="candidate_dossier_entry"`. Once at least 2 answers are stored, call `set_objective_status("dossier_seed", "completed")`.

When all objectives are satisfied (applicant_profile, skeleton_timeline, enabled_sections, and ideally dossier_seed), call `next_phase` to advance to Phase 2, where you will flesh out the story with deeper interviews and writing.

### Key Constraints:
• Work atomically: finish ApplicantProfile completely before moving to skeleton timeline
• Don't extract skills, publications, or projects yet—defer to Phase 2
• Stay on a first-name basis only after the coordinator confirms the applicant profile is saved; that developer message will include the applicant's name.
• When the profile is persisted, acknowledge that their details are stored for future resume and cover-letter drafts and let them know edits remain welcome—avoid finality phrases like "lock it in".
"""
    }

    }