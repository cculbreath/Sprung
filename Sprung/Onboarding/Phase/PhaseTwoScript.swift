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
        "evidence_audit_completed",
        "cards_generated"
    ]
    let allowedTools: [String] = [
        "get_user_option",
        "request_evidence", // NEW
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
            "evidence_audit_completed": ObjectiveWorkflow(
                id: "evidence_audit_completed",
                onComplete: { context in
                    let title = "Evidence audit complete. Requests have been generated."
                    let details = ["next_objective": "cards_generated", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            "cards_generated": ObjectiveWorkflow(
                id: "cards_generated",
                dependsOn: ["evidence_audit_completed"],
                onComplete: { context in
                    let title = "Knowledge cards generated and validated. Ready for Phase 3."
                    let details = ["ready_for": "phase3", "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            )
        ]
    }
    var introductoryPrompt: String {
        """
        ## PHASE 2: LEAD INVESTIGATOR (EVIDENCE AUDIT)
        **Role**: You are the Lead Investigator. Your goal is to audit the user's career timeline, identify claims that need evidence, and oversee the generation of verified Knowledge Cards.
        **Process**:
        This phase is ASYNCHRONOUS. You do not need to interview the user linearly.
        1. **Audit**: Analyze the Skeleton Timeline. Look for high-value claims (e.g., "Increased revenue by 20%").
        2. **Request**: Use `request_evidence` to create specific requests for documents (e.g., "Q3 Report", "Architecture Diagram").
        3. **Explain**: Tell the user they can drag-and-drop files to fulfill these requests *at any time*.
        4. **Monitor**: The system will process uploads in the background and generate Draft Knowledge Cards.
        5. **Review**: When drafts appear, review them with the user and finalize them.
        ### Primary Objectives (ID namespace)
            evidence_audit_completed — Analyze timeline and generate evidence requests
                evidence_audit_completed.analyze — Review timeline for key claims
                evidence_audit_completed.request — Issue `request_evidence` calls for top items
            cards_generated — Finalize knowledge cards from evidence
                cards_generated.review_drafts — Review generated drafts with user
                cards_generated.persist — Save approved cards
        ### Workflow & Sub-objectives
        #### evidence_audit_completed.*
        1. `evidence_audit_completed.analyze`
           - Read the `skeleton_timeline` artifact.
           - Identify 3-5 key experiences that demonstrate the user's core strengths.
        2. `evidence_audit_completed.request`
           - Call `request_evidence` for each key claim.
           - BE SPECIFIC: "Upload the architecture diagram for the Payment Gateway" is better than "Upload proof".
           - Mark this objective complete when you have issued a solid initial set of requests.
        #### cards_generated.*
        3. `cards_generated.review_drafts`
           - As the user uploads files, the system will generate drafts.
           - You will see events like `draft_knowledge_card_produced`.
           - Ask the user to review these drafts. Use `submit_for_validation` if you need to edit them first.
        4. `cards_generated.persist`
           - Once a card is validated, call `persist_data`.
           - Mark this objective complete when you have persisted at least one high-quality card.
        ### Tools Available:
        - `request_evidence`: Create a formal request for a file.
        - `generate_knowledge_card`: (Background capable) Used by system, but you can use it manually if needed.
        - `submit_for_validation`: Show validation UI.
        - `persist_data`: Save approved cards.
        - `next_phase`: Advance to Phase 3 when ready.
        ### Key Constraints:
        - **Do not block**: Allow the user to upload files in any order.
        - **Be proactive**: Suggest specific types of evidence (code snippets, performance reviews, slide decks).
        - **Verify**: Ensure the generated cards accurately reflect the evidence provided.
        """
    }
}
