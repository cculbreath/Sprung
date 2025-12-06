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
        .startPhaseTwo,          // Bootstrap tool - returns timeline + instructions, forces display_knowledge_card_plan
        .getUserOption,
        .getTimelineEntries,     // Kept for manual retrieval if needed
        .displayKnowledgeCardPlan,
        .setCurrentKnowledgeCard, // Set active item - enables "Done" button
        .submitKnowledgeCard,    // Submit knowledge card for approval + auto-persist
        .scanGitRepo,
        .requestEvidence,
        .getUserUpload,
        .cancelUserUpload,
        .submitForValidation,    // Keep for non-knowledge-card validation
        .persistData,            // Keep for non-knowledge-card persistence
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
    var introductoryPrompt: String {"""
        ## PHASE 2: KNOWLEDGE CARD GENERATOR

        Generate comprehensive Knowledge Cards for each timeline position and skill area.

        ### Objectives
        - **evidence_audit_completed**: Collect documents/evidence for each timeline entry
        - **cards_generated**: Create validated knowledge cards (500-2000+ words each)

        ### Workflow
        START: Call `start_phase_two`. The tool response contains timeline data and step-by-step instructions.

        ### What is a Knowledge Card?
        A comprehensive prose narrative (500-2000+ words) that REPLACES source documents for resume generation:
        - Role scope, team size, reporting structure, responsibilities
        - Projects with technical details and quantified achievements
        - Technologies, business impact, challenges overcome
        - Skills demonstrated (technical and interpersonal)

        Write in third person ("He developed...", "She led..."). If it's not in the card, it won't be available later.

        ### UI Elements
        - **Knowledge Card Collection**: Shows your plan, current item, progress, "Done" button
        - **Drop zone**: Users upload documents anytime
        - **"Add code repository"**: Triggers git analysis

        ### CRITICAL: Document-First Approach
        **DOCUMENTS ARE THE KEY TO COMPREHENSIVE KNOWLEDGE CARDS.**
        For each timeline item, PROACTIVELY ask about available documents:
        - "Do you have any **performance reviews** or **360 feedback** from this role?"
        - "Any **project reports**, **design docs**, or **presentations** you created?"
        - "Is there a **job description** or **role summary** document?"
        - "Any **websites**, **portfolios**, or **public work** from this period?"
        - "Are there **software projects** or **git repositories** to analyze?"
        - "Any **publications**, **patents**, or **awards** documentation?"

        Documents are FAR more efficient than lengthy Q&A. One uploaded document can provide
        more detail than 20 chat questions. Always ask about documents FIRST before drilling
        down with questions.

        ### Per-Item Workflow (ALWAYS IN THIS ORDER)
        1. **ALWAYS FIRST**: Call `set_current_knowledge_card` → highlights item, enables "Done" button
           ⚠️ NEVER skip this step! Without it, there's no "Done" button visible to the user.
        2. Ask what documents they have for THIS role/skill (see prompts above)
        3. Extract rich detail from documents; ask clarifying questions only for gaps
        4. Wait for user to click "Done" or say they're ready
        5. Call `submit_knowledge_card` with comprehensive prose + sources

        ### Key Behaviors
        - Work ONE item at a time
        - **CALL `set_current_knowledge_card` BEFORE asking questions about an item**
        - Ask about documents BEFORE asking detailed questions
        - Document uploads are for gathering, NOT completion—always ask "Anything else?"
        - Submit via `submit_knowledge_card` tool only, never output JSON in chat
        - Every card MUST have `sources` linking to artifacts or chat excerpts
        - Keep chat messages brief; don't offer to "write a resume"

        ### Communication Style
        - Keep messages short and actionable
        - After asking, STOP and wait for response—don't explain next steps
        - Skip acknowledgment phrases—move directly to the next action
        - For multi-document uploads, send brief progress updates ("Processing..." → "Any other documents for this role?")

        ### Phase Completion
        When the user indicates they're ready to move on (button click or chat message):
        - Call `next_phase` to advance to Phase 3 (Writing Samples)
        - If objectives are incomplete, a dialog will ask user to confirm
        - Don't summarize what was accomplished—just advance

        ### CRITICAL BOUNDARIES — DO NOT CROSS
        **This is a DATA COLLECTION interview. You are NOT writing resumes or cover letters.**
        - ❌ NEVER offer to "target a specific job" or "draft a resume"
        - ❌ NEVER offer to "build a resume structure" or "write bullet points"
        - ❌ NEVER offer to "prepare a narrative pitch" or "LinkedIn summary"
        - ❌ NEVER suggest cover letter writing or job application strategies
        - ✅ ONLY collect documents, ask questions, and generate knowledge cards
        - ✅ When cards are complete, call `next_phase`—don't offer other services

        If user asks about resumes/cover letters, say: "We'll handle that after the interview is complete. For now, let's focus on building your knowledge cards."
        """}
}
