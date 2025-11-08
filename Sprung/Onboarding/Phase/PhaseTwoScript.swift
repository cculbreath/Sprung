//
//  PhaseTwoScript.swift
//  Sprung
//
//  Phase 2: Deep Dive — Conduct detailed interviews and generate knowledge cards.
//

import Foundation

struct PhaseTwoScript: PhaseScript {
    let phase: InterviewPhase = .phase2DeepDive

    let requiredObjectives: [String] = [
        "interviewed_one_experience",
        "one_card_generated"
    ]

    let allowedTools: [String] = [
        "get_user_option",
        "generate_knowledge_card",
        "get_user_upload",
        "cancel_user_upload",
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
            "interviewed_one_experience": ObjectiveWorkflow(
                id: "interviewed_one_experience",
                onComplete: { context in
                    let title = "Completed a deep-dive interview. Use the captured notes to generate at least one knowledge card next."
                    let details = ["next_objective": "one_card_generated", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "one_card_generated": ObjectiveWorkflow(
                id: "one_card_generated",
                dependsOn: ["interviewed_one_experience"],
                onComplete: { context in
                    let title = "Knowledge card created and validated. If the user has more experiences to cover, repeat the interview cycle; otherwise prepare to transition to Phase 3."
                    let details = ["ready_for": "phase3", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }

    var introductoryPrompt: String {
        """
        ## PHASE 2: DEEP DIVE

        **Objective**: Conduct detailed interviews about the user's experiences and generate knowledge cards.

        ### Primary Objectives (ID namespace)
            interviewed_one_experience — Complete at least one in-depth interview about a significant position/project
                interviewed_one_experience.prep_selection — Select the experience to explore and align on scope
                interviewed_one_experience.discovery_interview — Conduct the structured deep-dive conversation
                interviewed_one_experience.capture_notes — Summarize takeaways and prep them for card drafting

            one_card_generated — Generate, validate, and persist at least one knowledge card from the interview
                one_card_generated.draft — Draft the knowledge card content using `generate_knowledge_card`
                one_card_generated.validation — Review the card with the user via validation UI
                one_card_generated.persisted — Persist the approved card for future reuse

        ### Workflow & Sub-objectives

        #### interviewed_one_experience.*
        1. `interviewed_one_experience.prep_selection`
           - Review the skeleton timeline artifacts from Phase 1.
           - Use `get_user_option` (if helpful) to let the user choose which experience to explore first.
           - Call `set_objective_status("interviewed_one_experience.prep_selection", "completed")` once the target is agreed upon.

        2. `interviewed_one_experience.discovery_interview`
           - Conduct a structured interview covering responsibilities, challenges, solutions, measurable impact, and technologies.
           - Probe for specific metrics, blockers removed, leadership moments, etc.
           - Mark this sub-objective completed when the interview has surfaced enough substance to draft at least one strong card.

        3. `interviewed_one_experience.capture_notes`
           - Summarize the conversation in your reasoning channel or scratchpad so you can reference it when drafting cards.
           - Highlight the elements that map cleanly into achievements, CAR/STAR narratives, and skill tags.
           - Set this sub-objective completed when your notes are organized and ready for `generate_knowledge_card`.

        #### one_card_generated.*
        4. `one_card_generated.draft`
           - Call `generate_knowledge_card` once you have the story. Include metrics, impact, and context from the interview notes.
           - Incorporate links to relevant artifacts or uploads when possible.
           - Mark the draft sub-objective completed after the tool returns a card that reflects the conversation accurately.

        5. `one_card_generated.validation`
           - Present the card via `submit_for_validation` so the user can confirm wording and emphasis.
           - Capture edits or corrections in follow-up messages or by re-running the generator if needed.
           - Complete this sub-objective when the user explicitly validates the card.

        6. `one_card_generated.persisted`
           - Call `persist_data` to store the approved card. Include metadata tying it back to the originating experience.
           - Set the sub-objective (and thus the parent `one_card_generated`) to completed when persistence succeeds.

        ### Closing the Phase
        - Use `set_objective_status` on each sub-objective to keep the ledger accurate; parents auto-complete when children finish.
        - When both main objectives are complete (and any additional interviews/cards the user wants have been handled), call `next_phase` to advance to Phase 3.

        ### Tools Available:
        - `get_user_option`: Present choices to the user (e.g., which experience to explore next)
        - `generate_knowledge_card`: Create structured knowledge cards
        - `submit_for_validation`: Show validation UI for knowledge cards
        - `persist_data`: Save approved cards
        - `set_objective_status`: Mark objectives as completed
        - `list_artifacts`, `get_artifact`, `request_raw_file`: Reference prior uploads
        - `next_phase`: Advance to Phase 3 when ready

        ### Key Constraints:
        - Focus on depth over breadth: one thorough interview beats multiple shallow ones
        - Knowledge cards must be evidence-backed and specific; avoid generic statements
        - Validate cards before persisting to ensure the user agrees with framing
        - Feel free to repeat the interview/card cycle beyond the minimum if the user wants more coverage
        """
    }
}
