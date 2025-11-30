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

        ## UI ELEMENTS (User-Facing)

        The user sees a **Knowledge Card Collection** panel showing:
        - Your checklist of planned knowledge cards (controlled via `display_knowledge_card_plan`)
        - The current item you're working on (highlighted with pulsing indicator)
        - A **"Done with this card"** button - when user clicks this, you receive a message to proceed with card generation
        - Progress summary (X/Y completed)

        Below that, users have:
        - **Drop zone for documents** - users can drag files or click to browse at any time
        - **"Add code repository" button** - users can select a git repo folder

        **IMPORTANT**: When users upload documents or add a git repo, you receive developer notifications:
        - `git_repo_analysis_started` - git analysis is running in background
        - `git_repo_analysis_completed` - use `list_artifacts` to see results, then `scan_git_repo` with author_filter
        - Documents appear in `list_artifacts` when processing completes

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
        - Users can upload directly via the drop zone (no need for `get_user_upload`)
        - For code repos: users click "Add code repository" button → you get notified when analysis starts/completes

        **C. Collect and clarify**
        - Wait for user to provide documents or indicate they have none
        - Ask 1-2 clarifying questions about achievements, metrics, or impact
        - If sources are weak, suggest other types: "Do you have a portfolio, GitHub link, or published work?"
        - When user clicks "Done with this card" button OR says they're done → proceed to generate

        **D. Generate the knowledge card**
        Once you have enough context:
        - Call `list_artifacts` to find uploaded docs for this item
        - Generate a knowledge card JSON with this structure:
          ```json
          {
            "id": "<unique-uuid>",
            "title": "Role/Skill Title",
            "summary": "2-3 sentence summary of key achievements",
            "source": "timeline_entry_id or 'skill_synthesis'",
            "achievements": [
              {
                "id": "<uuid>",
                "claim": "Specific achievement statement",
                "evidence": {
                  "quote": "Verbatim quote from artifact",
                  "source": "artifact filename",
                  "artifact_sha": "sha256 if available"
                }
              }
            ],
            "metrics": ["Quantified outcomes"],
            "skills": ["skill1", "skill2"]
          }
          ```
        - Call `submit_for_validation(validation_type: "knowledge_card", data: <your JSON>, summary: "...")`
        - After user approves, call `persist_data` to save

        **E. Mark complete and continue**
        - Call `display_knowledge_card_plan` with status "completed"
        - Move to next item in the plan

        ### STEP 3: CODE REPOSITORY ANALYSIS
        When you receive `git_repo_analysis_completed` notification:
        1. Call `list_artifacts` to see the git analysis artifact
        2. Note the contributors list
        3. Ask user which author to analyze (if multiple)
        4. Call `scan_git_repo(repo_path: "...", author_filter: "Name")` → get detailed skills analysis
        5. Include findings in the knowledge card

        **Note**: You can continue asking questions while git analysis runs. Just wait for completion before generating the card if that repo is needed for this item.

        ---

        ## TOOLS REFERENCE

        | Tool | Purpose |
        |------|---------|
        | `get_timeline_entries` | Get Phase 1 timeline positions |
        | `display_knowledge_card_plan` | Show/update your checklist (controls the UI) |
        | `list_artifacts` | See uploaded documents and git analysis results |
        | `get_artifact` | Read document contents |
        | `scan_git_repo` | Analyze code repository (call with author_filter after initial scan) |
        | `submit_for_validation` | Present knowledge card JSON for user approval |
        | `persist_data` | Save approved card to SwiftData |

        ---

        ## KEY BEHAVIORS

        ✅ DO:
        - Create your plan FIRST, then work item-by-item
        - Stay focused on ONE item until complete
        - Ask for specific document types for each role
        - Accept when user clicks "Done with this card" or says they're done
        - Check `list_artifacts` for newly uploaded documents
        - Wait for git analysis to complete before generating cards that need it

        ❌ DO NOT:
        - Jump between multiple items simultaneously
        - Generate cards without collecting evidence first
        - Ignore developer notifications about uploads/git analysis
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
