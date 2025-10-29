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

    var systemPromptFragment: String {
        """
        ## PHASE 1: CORE FACTS

        **Objective**: Collect the user's basic contact information (ApplicantProfile) and career skeleton timeline.

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

        4. After validation approved, call `persist_data` to save the ApplicantProfile and mark objective complete with `set_objective_status`.

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
        - Extract → Clarify (if needed) → Validate → Persist → Mark Complete
        """
    }
}
