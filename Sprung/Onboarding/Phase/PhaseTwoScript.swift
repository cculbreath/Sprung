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
        // Multi-agent workflow tools (in order of use)
        .startPhaseTwo,           // Bootstrap: returns timeline + artifact summaries
        .openDocumentCollection,  // Show dropzone for document uploads (mandatory step)
        .proposeCardAssignments,  // Map artifacts to cards, identify gaps
        .dispatchKCAgents,        // Spawn parallel KC agents
        .submitKnowledgeCard,     // Persist each generated card

        // Document collection tools
        .getUserUpload,
        .cancelUserUpload,
        // Note: scanGitRepo removed - it's triggered by UI button, not LLM
        .listArtifacts,
        .getArtifact,
        .getContextPack,
        .requestRawFile,
        // Note: requestEvidence tool removed - users upload via dropzone instead

        // User interaction
        .getUserOption,

        // Data persistence
        .persistData,             // For dossier entries

        // Phase management
        .setObjectiveStatus,
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
    var introductoryPrompt: String {"""
        ## PHASE 2: KNOWLEDGE CARD GENERATOR

        Generate comprehensive Knowledge Cards (500-2000+ word prose narratives) for each timeline position.
        Cards REPLACE source documents for resume generation—if it's not in the card, it won't be in the resume.

        **Objectives**: evidence_audit_completed, cards_generated

        **Tool chain**:
        1. `start_phase_two` → get timeline entry count/IDs
        2. `open_document_collection` → show upload UI, WAIT for "Done with Uploads"
        3. After uploads complete, optionally ask about specific gaps (e.g., "Do you have performance reviews from [Company]?")
        4. `propose_card_assignments` → map docs to cards, identify gaps, present for user review
        5. WAIT for explicit user approval ("generate cards", "looks good") before proceeding
        6. `dispatch_kc_agents` → parallel agents generate comprehensive cards
        7. Cards are AUTOMATICALLY presented for user validation (no tool call needed)
        8. You will receive developer messages indicating approval/rejection status for each card
        9. `next_phase` → advance to Phase 3 after all cards are processed

        **Critical rules**:
        - After propose_card_assignments: WAIT for user to approve before dispatch_kc_agents
        - After dispatch_kc_agents: wait for validation status messages (cards auto-presented to user)
        - If a card is rejected, you may dispatch another KC agent to regenerate it
        - For gaps, be SPECIFIC: "performance reviews from Acme (2019-2022)" not "any other docs?"
        - Suggest document types by role: reviews, design docs, job descriptions, promotion emails
        - Include relevant chat_excerpts in dispatch_kc_agents if user shared info verbally
        - This is DATA COLLECTION—never offer to write resumes or cover letters

        **Communication**: Keep messages short and actionable. STOP and wait for responses.
        """}
}
