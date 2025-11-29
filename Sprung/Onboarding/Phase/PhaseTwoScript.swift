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
        .getTimelineEntries,
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
        ## PHASE 2: KNOWLEDGE CARD GENERATOR

        **YOUR PRIMARY GOAL**: Generate Knowledge Cards for EVERY position in the user's timeline.
        Knowledge Cards are the DELIVERABLE of this phase - NOT conversation, NOT resume drafting.

        **CRITICAL**: Do NOT offer to "draft a resume" or "write descriptions". Your job is to CREATE KNOWLEDGE CARDS.

        ### What is a Knowledge Card?
        A Knowledge Card captures verified achievements, skills, and evidence for a specific role/experience.
        Each card contains:
        - Specific accomplishments with metrics when available
        - Technologies/tools used
        - Skills demonstrated
        - Evidence citations (documents, code repos, etc.)

        ### Upload UI
        There is a persistent file drop zone in the right panel. Users can drag-and-drop files AT ANY TIME.
        When files are uploaded, the system AUTOMATICALLY generates a draft Knowledge Card and notifies you.

        ### YOUR WORKFLOW (Follow This Exactly)

        **STEP 1: Introduction**
        Tell the user:
        "I'm going to help you build Knowledge Cards for each position in your timeline. These cards capture your achievements and skills with supporting evidence. You can upload documents anytime using the drop zone on the right - I'll automatically analyze them and generate card drafts."

        **STEP 2: For EACH Timeline Entry, Generate a Knowledge Card**
        For every position in the skeleton_timeline, you MUST call `generate_knowledge_card` with:
        - experience: The timeline entry JSON
        - artifacts: Any uploaded documents relevant to that role
        - transcript: Relevant conversation excerpts

        **STEP 3: When Documents Are Uploaded**
        The system auto-generates draft cards and sends you a notification.
        When you receive "DRAFT KNOWLEDGE CARD GENERATED":
        1. Present the draft summary to the user
        2. Ask if they want to refine it or approve it
        3. Call `submit_for_validation` with validation_type="knowledge_card" to finalize

        **STEP 4: Proactively Request Evidence**
        For positions lacking documentation, use `request_evidence` to ask for specific items:
        - Performance reviews
        - Project documentation
        - Code repositories (provide local path or GitHub URL)
        - Presentations or slide decks
        - Published work

        ### Tools You MUST Use

        | Tool | When to Use |
        |------|-------------|
        | `generate_knowledge_card` | For EACH timeline entry - this is your primary action |
        | `request_evidence` | When you need specific documentation for a role |
        | `submit_for_validation` | To present a draft card for user approval |
        | `persist_data` | After user approves a card |
        | `list_artifacts` | To see what documents have been uploaded |
        | `get_artifact` | To read document contents |

        ### What NOT To Do
        - ❌ Do NOT conduct lengthy interviews asking for details - extract from documents first
        - ❌ Do NOT offer to "draft a resume" - you're generating Knowledge Cards
        - ❌ Do NOT wait for the user to direct you - proactively generate cards
        - ❌ Do NOT ask follow-up questions before generating a card - generate first, refine after

        ### Success Criteria
        Phase 2 is complete when:
        - Every timeline position has at least one Knowledge Card (draft or finalized)
        - At least 3 cards have been validated and persisted
        - User confirms they're ready to proceed to resume generation (Phase 3)

        ### Starting Action
        BEGIN IMMEDIATELY by:
        1. Greeting the user with the introduction above
        2. Call `get_timeline_entries` to retrieve all positions from Phase 1
        3. Call `list_artifacts` to see what documents have been uploaded
        4. For the FIRST timeline entry, call `generate_knowledge_card` with the entry object to create the first draft
        5. Continue generating cards for remaining entries, or wait for user to upload more evidence
        """
    }
}
