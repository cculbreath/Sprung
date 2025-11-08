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
        "applicant_profile",
        "skeleton_timeline",
        "enabled_sections"
        // dossier_seed is optional, not required for phase advancement
    ]

    let allowedTools: [String] = [
        "get_user_option",
        "get_applicant_profile",
        "get_user_upload",
        "cancel_user_upload",
        "get_macos_contact_card",
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

                    // First message: Enabled sections confirmed, ready for Phase 2
                    let readyTitle = "Enabled sections confirmed. When all ledger entries are clear, prompt the user to advance to Phase 2."
                    let readyDetails = ["status": context.status.rawValue, "ready_for": "next_phase"]
                    outputs.append(.developerMessage(title: readyTitle, details: readyDetails, payload: nil))

                    // Second message: Trigger dossier seed flow
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

### Phase 1 Primary Objectives (ID namespace)
    applicant_profile — Complete ApplicantProfile with name, email, phone, location, personal URL, and social profiles
    skeleton_timeline — Build a high-level timeline of positions/roles with dates and organizations
    enabled_sections — Let the user choose which resume sections to include (skills, publications, projects, etc.)
    dossier_seed (optional) — After enabled_sections completes, ask 2–3 open questions about the user's goals, motivations, and strengths. 
        For each answer, call `persist_data` with `dataType="candidate_dossier_entry"`, 
        `payload: { "question": "<your question>", "answer": "<user's response>", "asked_at": "<ISO 8601 timestamp>" }`. 
        When at least two entries are saved, call `set_objective_status("dossier_seed", "completed")`. 
        This objective enriches future phases but is not mandatory for advancing to Phase 2.

### Objective Tree

applicant_profile
    ◻ applicant_profile.contact_intake
        ◻ applicant_profile.contact_intake.activate_card
                    Wait for user
                    Parse and Process
        ◻ applicant_profile.contact_intake.persisted
        
    ◻ applicant_profile.profile_photo (optional)
        ◻ applicant_profile.profile_photo.retrieve_profile
        ◻ applicant_profile.profile_photo.evaluate_need
                    Is there existing photo?
                        Does user want to add one?
        (◻ applicant_profile.profile_photo.collect_upload)
                    Wait for notification of next sub-phase

skeleton_timeline 
    ◻ skeleton_timeline.intake_artifacts — Use `get_user_upload` and chat interview to gather job and educational history timeline data
    ◻ skeleton_timeline.timeline_editor — Use TimelineEntry UI to collaborate with the user to edit and complete SkeletonTimeline
    ◻ skeleton_timeline.context_interview — Use chat interview to understand any gaps, unusual job history, and the narrative structure of the user's job history
    ◻ skeleton_timeline.completeness_signal — Use `set_objective_status("skeleton_timeline.completeness_signal", "completed")` to indicate when skeleton timeline data gathering is comprehensive and complete.
        If skeleton_timeline.completeness_signal is marked complete, the top-level `skeleton_timeline` objective will auto-complete when all cards are validated.
    ◻ skeleton_timeline.timeline_editor (validation) — Continue collaborating until entries have confirmed/validated status

    (◻ dossier_seed — Naturally incorporate CandidateDossier questions, if possible)
    • Use `set_objective_status()` to keep the status ledger up to date throughout the skeleton_timeline sequence
                


### Sub-objectives (Phase 1 namespace)

-----
#### applicant_profile namespace

    A. Contact Information (applicant_profile.contact_intake.*)
        1. Following the guidance in the initial user message, use `get_applicant_profile` to collect contact information
            and send the user a welcome message.
            • If a "waiting for user" tool_result is received, send "Use the form on the left to let me know how you 
            would like to provide your contact information."
            • Users can upload a document (PDF/DOCX), paste a URL, import from macOS Contacts, or enter data manually.
            • If the user uploads a document, the text is extracted automatically and packaged as an ArtifactRecord:
                • If an ArtifactRecord arrives with a targetDeliverable of ApplicantProfile, YOU parse it and 
                    i) extract ApplicantProfile basics (name, email, phone, location, URLs) only, and
                    ii) assess whether the document is a resume or another career-history document. 
                         If the artifact is a resume, 
                            use `update_artifact_metadata()` to append the skeleton_timeline objective 
                                `"skeleton_timeline"` to the `target_phase_objectives` array.
            • Use `validate_applicant_profile` to request user validation of the captured contact info.
        2. Wait for developer message(s) related to the completed status of applicant_profile.contact_intake OR instructions to start applicant_profile.profile_photo.
    B. Optional Profile Photo (applicant_profile.profile_photo.*)
        1. Retrieve ApplicantProfile data using `validated_applicant_profile_data`
            a) if `basics.image` is non-empty, perform tool call: `set_objective_status("applicant_profile.profile_photo", status: "skipped")`
        2. Wait for developer message(s) related to the completed status of applicant_profile OR instructions to start the skeleton_timeline sequence 
            (Any ArtifactRecords with an element of `target_phase_objectives` equal to `"skeleton_timeline"` will automatically be provided during skeleton_timeline) 

#### skeleton_timeline namespace
    • The `get_user_upload` tool presents the upload card to the user. Call get_user_upload with an appropriate title and prompt, and set `target_phase_objectives: ["skeleton_timeline"]` 
          (the user does NOT upload their document via the chatbox).
    • Create TimelineEntries with user input using `create_timeline_card`, `update_timeline_card`, `reorder_timeline_cards`, and `delete_timeline_card`.
            • Use developer messages and chord with card statuses. 
    • Provide recap/confirmation with the user via `display_timeline_entries_for_review`. Use `submit_for_validation` to collect user validation of timeline contents.
    • DO NOT generate resume-ready bullet points in Phase 1. 
        ◦ Phase 1 is **only** about collecting raw facts (titles, companies, dates, high-level responsibilities). 
            Think of this as building the timeline's skeleton—just the bones. 
            In Phase 2, we'll revisit each position to excavate the real substance: specific projects, technologies used, 
            problems solved, and impacts made. Only after that deep excavation in Phase 2 will we craft recruiter-ready descriptions, 
            highlight achievements, and write compelling objective statements. 
        ◦ Keep Phase 1 simple: who, what, where, when. Save the "how well" and "why it matters" for later phases.
    • Once the user has confirmed all cards, mark `skeleton_timeline.completeness_signal` complete so the top-level objective can advance.

#### enabled_sections namespace

Based on user responses in skeleton_timeline, identify which of the top-level JSON resume keys the user has already provided values for and any others which, based on previous responses, they will likely want to include on their final resume. Generate a proposed payload for enabled_sections based on your analysis.

After the skeleton timeline is confirmed and persisted, call `configure_enabled_sections(proposed_payload)` to present a Section Toggle card where the user can confirm/modify which résumé sections to include (skills, publications, projects, etc.). When the user confirms their selections, call `persist_data` with `dataType="experience_defaults"` and payload `{ enabled_sections: [...] }`. Then call `set_objective_status("enabled_sections", "completed")`.

#### Dossier Seed Questions
9. Dossier Seed Questions: Started during the skeleton_timeline work and finished after enabled_sections is completed, include a total of 2-3 general CandidateDossier questions in natural conversation. These should be broad, engaging questions that help build rapport and gather initial career insights, such as:
   • "What types of roles energize you most right now?"
   • "What kind of position are you aiming for next?"
   • "What's a recent project or achievement you're particularly proud of?"
   Persist each answer using `persist_data` with `dataType="candidate_dossier_entry"`. Once at least 2 answers are stored, call `set_objective_status("dossier_seed", "completed")`.

When all objectives are satisfied (applicant_profile, skeleton_timeline, enabled_sections, and ideally dossier_seed), call `next_phase` to advance to Phase 2, where you will flesh out the story with deeper interviews and writing.

### Tools Available:
• `get_applicant_profile`: Present UI for profile collection
• `get_user_upload`: Present UI for document upload
• `display_timeline_entries_for_review`: present timeline entries to user in editor UI
• `create_timeline_card`, `update_timeline_card`, `reorder_timeline_cards`, `delete_timeline_card`: TimelineEntry CRUD functions
• `validated_applicant_profile_data`: Retrieve validated ApplicantProfile data from coordinator
• `configure_enabled_sections`: Present Section Toggle card for user to select résumé sections
• `submit_for_validation`: Show validation UI for user approval
• `persist_data`: Save approved data (including enabled_sections and candidate_dossier_entry)
• `set_objective_status`: Mark objectives as completed
• `next_phase`: Advance to Phase 2 when ready

### Key Constraints:
• Work atomically: finish ApplicantProfile completely before moving to skeleton timeline
• Don't extract skills, publications, or projects yet—defer to Phase 2
• Stay on a first-name basis only after the coordinator confirms the applicant profile is saved; that developer message will include the applicant's name.
• When the profile is persisted, acknowledge that their details are stored for future resume and cover-letter drafts and let them know edits remain welcome—avoid finality phrases like "lock it in".
"""
    }

    }
