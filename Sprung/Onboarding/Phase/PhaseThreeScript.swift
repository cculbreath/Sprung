//
//  PhaseThreeScript.swift
//  Sprung
//
//  Phase 3: Writing Corpus — Collect writing samples and complete dossier.
//

import Foundation

struct PhaseThreeScript: PhaseScript {
    let phase: InterviewPhase = .phase3WritingCorpus

    let requiredObjectives: [String] = [
        "one_writing_sample",
        "dossier_complete"
    ]

    let allowedTools: [String] = [
        "get_user_option",
        "get_user_upload",
        "cancel_user_upload",
        "extract_document",
        "submit_for_validation",
        "persist_data",
        "set_objective_status",
        "list_artifacts",
        "get_artifact",
        "request_raw_file",
        "next_phase"
    ]

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            "one_writing_sample": ObjectiveWorkflow(
                id: "one_writing_sample",
                onComplete: { context in
                    let title = "Writing sample captured. Summarize style insights (if consented) and assemble the dossier for final validation."
                    let details = ["next_objective": "dossier_complete", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "dossier_complete": ObjectiveWorkflow(
                id: "dossier_complete",
                dependsOn: ["one_writing_sample"],
                onComplete: { context in
                    let title = "Candidate dossier finalized. Congratulate the user, summarize next steps, and call next_phase to finish the interview."
                    let details = ["status": context.status.rawValue, "ready_for": "completion"]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }

    var systemPromptFragment: String {
        """
        ## PHASE 3: WRITING CORPUS

        **Objective**: Collect writing samples and finalize the candidate dossier.

        ### Primary Objectives:
        1. **one_writing_sample**: Collect at least one writing sample (cover letter, email, proposal, etc.)
        2. **dossier_complete**: Finalize the comprehensive candidate dossier

        ### Workflow:
        1. Request writing samples from the user:
           - Use `get_user_upload` to collect existing samples (PDFs, documents)
           - Ask user to provide samples via paste or upload
           - Look for cover letters, professional correspondence, technical writing, etc.

        2. If user consents to writing analysis (check preferences), analyze samples for:
           - Writing style and voice
           - Tone and formality level
           - Vocabulary preferences
           - Structural patterns

        3. Create a writing style profile that can inform future resume/cover letter generation.

        4. Compile the complete candidate dossier:
           - ApplicantProfile (from Phase 1)
           - Skeleton timeline (from Phase 1)
           - Knowledge cards (from Phase 2)
           - Writing samples and style profile (from Phase 3)
           - Any additional artifacts collected

        5. Present the dossier summary using `submit_for_validation` for final review.

        6. Save the complete dossier with `persist_data`.

        7. Mark objectives complete with `set_objective_status`.

        8. Call `next_phase` to mark the interview as complete.

        ### Tools Available:
        - `get_user_upload`: Request file uploads
        - `extract_document`: Extract text from writing samples
        - `submit_for_validation`: Show dossier summary for approval
        - `persist_data`: Save writing samples and dossier
        - `set_objective_status`: Mark objectives as completed
        - `next_phase`: Mark interview complete

        ### Key Constraints:
        - Respect user's writing analysis consent preferences
        - Writing analysis is optional—focus on collection if consent not given
        - Dossier should be comprehensive but not overwhelming
        - Congratulate user on completion and explain next steps (resume/cover letter generation)
        """
    }
}
