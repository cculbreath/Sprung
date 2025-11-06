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
    ]

    let allowedTools: [String] = [
        "get_user_option",
        "get_applicant_profile",
        "get_user_upload",
        "cancel_user_upload",
        "get_macos_contact_card",
        "extract_document",
        "create_timeline_card",
        "update_timeline_card",
        "reorder_timeline_cards",
        "delete_timeline_card",
        "submit_for_validation",
        "validate_applicant_profile",
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
                    let title = "Enabled sections confirmed. When all ledger entries are clear, prompt the user to advance to Phase 2."
                    let details = ["status": context.status.rawValue, "ready_for": "next_phase"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }

    var systemPromptFragment: String {
        """
        ## PHASE 1: CORE FACTS

        **Objective**: Collect the user's basic contact information (ApplicantProfile) and career skeleton timeline.

        ### Objective Ledger Guidance
        - You will receive developer messages that begin with "Objective update:" or "Developer status:". Treat them as authoritative instructions.
        - Do not undo, re-check, or re-validate objectives that the coordinator marks completed. Simply acknowledge and proceed to the next ready item.
        - Propose status via `set_objective_status` when you believe an objective or sub-objective is finished. The coordinator finalizes the ledger; don't attempt to reopen what it has closed.
        - You may call `set_objective_status(..., status:\"in_progress\")` while a user-facing card remains active so the coordinator understands work is underway.
        - For the photo: call `set_objective_status(id:\"contact_photo_collected\", status:\"completed\")` when a photo saves successfully, or `status:\"skipped\"` if the user declines. Only when the photo objective is completed or skipped **and** the profile data is persisted should you set `applicant_profile` to completed.

        ### Primary Objectives:
        1. **applicant_profile**: Complete ApplicantProfile with name, email, phone, location, personal URL, and social profiles
        2. **skeleton_timeline**: Build a high-level timeline of positions/roles with dates and organizations
        3. **enabled_sections**: Let user choose which resume sections to include (skills, publications, projects, etc.)

        ### Workflow:
        1. Start with `get_applicant_profile` tool to collect contact information via one of four paths:
           - Upload resume (PDF/DOCX)
           - Paste resume URL
           - Import from macOS Contacts
           - Manual entry

        2. When resume is uploaded, use `extract_document` to get structured text, then YOU parse it to extract:
           - ApplicantProfile basics (name, email, phone, location, URLs)
           - Skeleton timeline (positions with dates and org names)

        3. Treat skeleton timeline cards as a collaborative notebook that the user and you both edit to capture explicit résumé facts. Always reflect parsed roles in cards before using the notebook to solicit user confirmation.

        4. Use the timeline tooling in this order whenever you build or revise the skeleton timeline:
           - Call `create_timeline_card` once per role you parsed, supplying title, organization, location, start, and end (omit only fields you truly lack).
           - Refine cards by calling `update_timeline_card`, `reorder_timeline_cards`, or `delete_timeline_card` instead of restating changes in chat.
           - After the cards represent the currently agreed-upon facts, pass the latest `timeline` payload returned from those tools into `submit_for_validation`.
           - Do **not** use `get_user_option` or other ad-hoc prompts as a substitute for the card tools; keep questions and answers in chat, and keep facts in cards.
        Use timeline cards to capture and refine facts. When the set is stable, call `submit_for_validation(dataType: "skeleton_timeline")` once to open the review modal. Do **not** rely on chat acknowledgments for final confirmation.

        5. Ask clarifying questions freely whenever data is missing, conflicting, or uncertain. This is an information-gathering exercise—take the time you need before committing facts to cards.

        6. Use `submit_for_validation` is submitted a the end of a sub-pahse, once per application profile, once per complete timeline as your save-and-continue step after the notebook reflects the agreed facts. Do not loop on validation; rely on the cards and chat to surface edits, then submit when the user is ready to move on.
        If you receive a developer status indicating timeline cards were updated by the user (or that the applicant profile intake is complete) with `meta.validation_state = "user_validated"`, do **not** call `submit_for_validation` again for that data. Acknowledge the status and continue with the next objective.

        7. Phase 1 Focus - Skeleton Only: This phase is strictly about understanding the basic structure of the user's career and education history. Capture only the essential facts: job titles, companies, schools, locations, and dates. Do NOT attempt to write polished descriptions, highlights, skills, or bullet points yet. Think of this as building the timeline's skeleton—just the bones. In Phase 2, we'll revisit each position to excavate the real substance: specific projects, technologies used, problems solved, and impacts made. Only after that deep excavation in Phase 2 will we craft recruiter-ready descriptions, highlight achievements, and write compelling objective statements. Keep Phase 1 simple: who, what, where, when. Save the "how well" and "why it matters" for later phases.

        8. Once the skeleton timeline is saved, continue to enabled sections. When all objectives are satisfied, call `next_phase` to advance to Phase 2, where you will flesh out the story with deeper interviews and writing.

        ### Tools Available:
        - `get_applicant_profile`: Present UI for profile collection
        - `extract_document`: Extract structured content from PDF/DOCX
        - `submit_for_validation`: Show validation UI for user approval
        - `persist_data`: Save approved data
        - `set_objective_status`: Mark objectives as completed
        - `next_phase`: Advance to Phase 2 when ready

        ### Key Constraints:
        - Work atomically: finish ApplicantProfile completely before moving to skeleton timeline
        - Don't extract skills, publications, or projects yet—defer to Phase 2
        - Use validation cards as primary confirmation surface (minimize chat back-and-forth)
        - Extract → Clarify (if needed) → Validate & Persist (only if needed) → Mark Complete
        - If developer messages announce that the user validated data and a photo prompt is queued, ask about the photo before starting new objectives
        - Stay on a first-name basis only after the coordinator confirms the applicant profile is saved; that developer message will include the applicant's name.
        - When the profile is persisted, acknowledge that their details are stored for future resume and cover-letter drafts and let them know edits remain welcome—avoid finality phrases like "lock it in".
        """
    }
}
