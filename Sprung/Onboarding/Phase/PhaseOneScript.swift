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
        - Continue calling `set_objective_status` when you assess that an objective (or sub-objective) is finished, but expect the coordinator to arbitrate the final state.

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

        3. Ask clarifying questions ONLY when data is missing or ambiguous. When clear, jump to `submit_for_validation`.

        4. After validation approved (or when the coordinator auto-approves), call `persist_data` only if the coordinator indicates data still needs saving. If the developer message says it is already persisted, acknowledge and continue.

        5. Repeat for skeleton timeline: extract from resume, clarify if needed, validate, persist, mark complete.

        6. Once all objectives are done, call `next_phase` to advance to Phase 2.

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
        - Extract → Clarify (if needed) → Validate → Persist (only if needed) → Mark Complete
        - If developer messages announce that the user validated data and a photo prompt is queued, ask about the photo before starting new objectives
        """
    }
}
