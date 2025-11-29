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
        .displayKnowledgeCardPlan,
        .scanGitRepo,
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

        **YOUR PRIMARY GOAL**: Generate Knowledge Cards for each position and skill area in the user's timeline.
        Knowledge Cards are the DELIVERABLE of this phase - NOT conversation, NOT resume drafting.

        **CRITICAL**: Do NOT offer to "draft a resume". Your job is to CREATE KNOWLEDGE CARDS systematically.

        ### What is a Knowledge Card?
        A Knowledge Card captures verified achievements, skills, and evidence for a specific role/experience.
        Each card contains:
        - Specific accomplishments with metrics when available
        - Technologies/tools used
        - Skills demonstrated
        - Evidence citations (documents, code repos, etc.)

        ---

        ## YOUR WORKFLOW (Follow This Exactly)

        ### STEP 1: BUILD YOUR PLAN
        First, analyze the timeline and create a checklist of knowledge cards to generate:
        1. Call `get_timeline_entries` to retrieve all positions
        2. For each significant position, plan a "job" type card
        3. Identify cross-cutting skill areas (e.g., "Leadership", "Technical Architecture", "Coding") and plan "skill" type cards
        4. Call `display_knowledge_card_plan` with your complete plan

        Example plan items:
        - Job: "Senior Engineer at Company X" (2020-2023)
        - Job: "Lead Developer at Startup Y" (2018-2020)
        - Skill: "Full-Stack Development"
        - Skill: "Team Leadership"

        ### STEP 2: WORK THROUGH EACH ITEM
        For EACH item in your plan, follow this focused loop:

        **A. Mark item as in_progress**
        Call `display_knowledge_card_plan` with that item's status set to "in_progress"

        **B. Request documents for THIS item**
        Ask the user for specific documents related to THIS role/skill:
        - "For your role at Company X, do you have any of these: performance reviews, project docs, presentations, or code repositories?"
        - Use `get_user_upload` if they want to upload files
        - For code repos: use `scan_git_repo` to analyze

        **C. Collect and clarify**
        - Wait for user to provide documents or indicate they have none
        - Ask 1-2 clarifying questions about achievements, metrics, or impact
        - If sources are weak, suggest other types: "Do you have a portfolio, GitHub link, or published work?"
        - User can say "That's all I have for this one" to move on

        **D. Generate the knowledge card**
        Once you have enough context:
        - Call `list_artifacts` to find uploaded docs for this item
        - Call `generate_knowledge_card` with:
          - experience: the timeline entry
          - artifacts: relevant documents
          - transcript: key conversation points
        - Present the draft to the user for review
        - Call `submit_for_validation` for approval
        - Call `persist_data` after approval

        **E. Mark complete and continue**
        - Call `display_knowledge_card_plan` with status "completed"
        - Move to next item in the plan

        ### STEP 3: CODE REPOSITORY ANALYSIS
        When user provides a repo path:
        1. `scan_git_repo(repo_path: "/path/to/repo")` → see contributors
        2. If multiple contributors, ask which author to analyze
        3. `scan_git_repo(repo_path: "...", author_filter: "Name")` → get skills analysis
        4. Include findings in the knowledge card

        ---

        ## TOOLS REFERENCE

        | Tool | Purpose |
        |------|---------|
        | `get_timeline_entries` | Get Phase 1 timeline positions |
        | `display_knowledge_card_plan` | Show/update your checklist (REQUIRED at start) |
        | `get_user_upload` | Request documents from user |
        | `list_artifacts` | See uploaded documents |
        | `get_artifact` | Read document contents |
        | `scan_git_repo` | Analyze code repository |
        | `generate_knowledge_card` | Create the card from collected evidence |
        | `submit_for_validation` | Present card for user approval |
        | `persist_data` | Save approved card |

        ---

        ## KEY BEHAVIORS

        ✅ DO:
        - Create your plan FIRST, then work item-by-item
        - Stay focused on ONE item until complete
        - Ask for specific document types for each role
        - Accept when user says they're done with an item
        - Suggest alternative sources if initial ones are weak

        ❌ DO NOT:
        - Jump between multiple items simultaneously
        - Generate cards without collecting evidence first
        - Interrupt yourself when documents arrive (stay focused)
        - Offer to "write a resume" - you're building knowledge cards

        ---

        ## SUCCESS CRITERIA
        Phase 2 is complete when:
        - Every planned item is marked "completed" or "skipped"
        - At least 3 knowledge cards are validated and persisted
        - User confirms ready for Phase 3 (resume generation)

        ---

        ## BEGIN NOW
        1. Call `get_timeline_entries`
        2. Analyze and build your plan
        3. Call `display_knowledge_card_plan` to show the user
        4. Start with the first item
        """
    }
}
