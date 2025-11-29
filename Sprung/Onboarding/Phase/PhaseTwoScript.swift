//
//  PhaseTwoScript.swift
//  Sprung
//
//  Phase 2: Deep Dive — Conduct detailed interviews and generate knowledge cards.
//
import Foundation
struct PhaseTwoScript: PhaseScript {
    let phase: InterviewPhase = .phase2DeepDive
    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .evidenceAuditCompleted,
        .cardsGenerated
    ])
    let allowedTools: [String] = OnboardingToolName.rawValues([
        .getUserOption,
        .requestEvidence,
        .generateKnowledgeCard,
        .getUserUpload,
        .cancelUserUpload,
        .submitForValidation,
        .persistData,
        .setObjectiveStatus,
        .listArtifacts,
        .getArtifact,
        .requestRawFile,
        .nextPhase
    ])
    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            OnboardingObjectiveId.evidenceAuditCompleted.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.evidenceAuditCompleted.rawValue,
                onComplete: { context in
                    let title = "Evidence audit complete. Requests have been generated."
                    let details = ["next_objective": OnboardingObjectiveId.cardsGenerated.rawValue, "status": context.status.rawValue]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),
            OnboardingObjectiveId.cardsGenerated.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.cardsGenerated.rawValue,
                dependsOn: [OnboardingObjectiveId.evidenceAuditCompleted.rawValue],
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

        **IMPORTANT - Upload UI**: There is a persistent file drop zone visible in the right panel. Tell the user upfront that they can drag-and-drop files AT ANY TIME to provide supporting documentation. You do NOT need to call `get_user_upload` to enable uploads - the drop zone is always available. When files are uploaded, you will be notified automatically.

        **Process**:
        This phase is ASYNCHRONOUS. You do not need to interview the user linearly.
        1. **Introduce**: Tell the user they can upload documents anytime using the drop zone in the right panel.
        2. **Audit**: Analyze the Skeleton Timeline. Look for high-value claims (e.g., "Increased revenue by 20%").
        3. **Request**: Use `request_evidence` to create specific requests for documents (e.g., "Q3 Report", "Architecture Diagram").
        4. **Learn from Documents**: When documents are uploaded, FIRST thoroughly analyze their contents before asking additional questions. Extract as much information as possible from the documents to minimize user effort.
        5. **Monitor**: The system will process uploads in the background and generate Draft Knowledge Cards.
        6. **Review**: When drafts appear, review them with the user and finalize them.
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
