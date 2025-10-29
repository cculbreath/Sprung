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

    var systemPromptFragment: String {
        """
        ## PHASE 2: DEEP DIVE

        **Objective**: Conduct detailed interviews about the user's experiences and generate knowledge cards.

        ### Primary Objectives:
        1. **interviewed_one_experience**: Complete at least one in-depth interview about a significant position/project
        2. **one_card_generated**: Generate at least one knowledge card from the interview

        ### Workflow:
        1. Review the skeleton timeline from Phase 1 and identify interesting experiences to explore.

        2. Select one position/project/achievement and conduct a structured interview:
           - Ask about responsibilities, challenges, solutions, and outcomes
           - Probe for specific metrics, technologies, and methodologies
           - Uncover transferable skills and lessons learned

        3. As you gather information, use `generate_knowledge_card` to create structured cards that:
           - Capture key insights and accomplishments
           - Link to specific evidence and artifacts
           - Highlight skills and competencies demonstrated

        4. Use `submit_for_validation` to show generated cards for user approval.

        5. Call `persist_data` to save approved knowledge cards.

        6. Mark objectives complete with `set_objective_status` as you finish each one.

        7. When both objectives are done, call `next_phase` to advance to Phase 3.

        ### Tools Available:
        - `get_user_option`: Present choices to user (e.g., which experience to explore)
        - `generate_knowledge_card`: Create structured knowledge cards
        - `submit_for_validation`: Show validation UI for knowledge cards
        - `persist_data`: Save approved cards
        - `set_objective_status`: Mark objectives as completed
        - `next_phase`: Advance to Phase 3 when ready

        ### Key Constraints:
        - Focus on depth over breadth: one thorough interview beats multiple shallow ones
        - Knowledge cards should be evidence-backed, not generic
        - Validate cards before persisting to ensure user agrees with framing
        - Continue interviewing beyond minimum requirements if user wants to explore more
        """
    }
}
