//
//  PhaseThreeScript.swift
//  Sprung
//
//  Phase 3: Evidence Collection — Strategic document requests, git repositories,
//  card inventory, and knowledge card generation.
//
//  INTERVIEW REVITALIZATION PLAN:
//  The interviewer should be ACTIVE during document collection. Background processing
//  is batched—ONE notification when work starts and ONE when it's done. While agents
//  work, the interviewer gathers dossier insights using get_user_option.
//
//  CRITICAL: User should NEVER wait in silence. If agents are working, interviewer is conversing.
//
//  TOOL AVAILABILITY: Defined in ToolBundlePolicy.swift (single source of truth)
//
//  FLOW:
//  1. Strategic document requests based on Phase 2 timeline
//  2. Git repository selection
//  3. Card inventory + merge (batched, non-interruptive)
//  4. KC generation (batched, interview during wait)
//  5. LLM reviews generated cards, asks clarifying questions
//  6. USER clicks "Approve & Create Cards" → auto-advances to Phase 4
//
//  PHASE TRANSITION: Phase 3 is UI-driven. The interviewer does NOT call next_phase.
//  Instead, the user clicks "Approve & Create Cards" which automatically advances to Phase 4.
//
import Foundation

struct PhaseThreeScript: PhaseScript {
    let phase: InterviewPhase = .phase3EvidenceCollection

    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .evidenceDocumentsCollected,     // Supporting documents uploaded
        .knowledgeCardsGenerated         // KCs created and persisted
        // gitReposAnalyzed and cardInventoryComplete are intermediate steps, not strictly required
    ])

    var initialTodoItems: [InterviewTodoItem] {
        [
            InterviewTodoItem(
                content: "Open document collection UI",
                status: .pending,
                activeForm: "Opening document collection"
            ),
            InterviewTodoItem(
                content: "Suggest documents to upload based on timeline",
                status: .pending,
                activeForm: "Suggesting documents"
            ),
            InterviewTodoItem(
                content: "Interview about each role (while uploads process)",
                status: .pending,
                activeForm: "Interviewing about roles"
            ),
            InterviewTodoItem(
                content: "Capture work preferences and unique circumstances",
                status: .pending,
                activeForm: "Capturing work preferences"
            ),
            InterviewTodoItem(
                content: "Wait for document processing and card generation",
                status: .pending,
                activeForm: "Waiting for card generation"
            ),
            InterviewTodoItem(
                content: "Review merged knowledge cards with user",
                status: .pending,
                activeForm: "Reviewing knowledge cards"
            )
        ]
    }

    var objectiveWorkflows: [String: ObjectiveWorkflow] {
        [
            // MARK: - Document Collection
            OnboardingObjectiveId.evidenceDocumentsCollected.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.evidenceDocumentsCollected.rawValue,
                onBegin: { _ in
                    let title = """
                        Phase 3 starting. Make STRATEGIC document requests based on the timeline. \
                        Don't just show an upload form—explain what you're looking for: \
                        "Let's gather the evidence that brings your experience to life. Based on your timeline, \
                        here's what would be most valuable: \
                        - Technical reports from [specific project] \
                        - Teaching evaluations from [specific role] \
                        - Code from [specific project] \
                        What do you have access to?" \
                        Then call open_document_collection to show the upload UI.
                        """
                    let details = [
                        "action": "call_open_document_collection",
                        "approach": "strategic_requests"
                    ]
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { _ in
                    let title = """
                        Evidence documents collected. Now proceeding to git repository selection. \
                        Ask which repositories best showcase their work: \
                        "Let's look at your code. Which repositories best showcase your work? \
                        Active/recent projects, solo or lead-contributor projects, and well-documented code are ideal."
                        """
                    return [.coordinatorMessage(title: title, details: [:], payload: nil)]
                }
            ),

            // MARK: - Git Repository Analysis
            OnboardingObjectiveId.gitReposAnalyzed.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.gitReposAnalyzed.rawValue,
                dependsOn: [OnboardingObjectiveId.evidenceDocumentsCollected.rawValue],
                autoStartWhenReady: true,
                onComplete: { _ in
                    let title = """
                        Git repositories analyzed. Card inventory being generated. \
                        INTERVIEW WHILE WAITING: Use get_user_option to gather dossier insights. \
                        Good topics: availability, self-assessment of strengths, hidden skills not on resume.
                        """
                    return [.coordinatorMessage(title: title, details: ["interview_during_wait": "true"], payload: nil)]
                }
            ),

            // MARK: - Card Inventory
            OnboardingObjectiveId.cardInventoryComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.cardInventoryComplete.rawValue,
                dependsOn: [OnboardingObjectiveId.gitReposAnalyzed.rawValue],
                autoStartWhenReady: true,
                onComplete: { _ in
                    let title = """
                        Card inventory complete. Knowledge card generation starting. \
                        CONTINUE INTERVIEWING while KC generation runs (~2-3 min). \
                        This is prime time for dossier questions: concerns to address proactively, \
                        career narrative connections, availability timing. \
                        You'll get a summary when cards are ready—DO NOT acknowledge each individually.
                        """
                    let details = [
                        "batch_processing": "true",
                        "interview_during_wait": "true"
                    ]
                    return [.coordinatorMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Knowledge Cards Generated
            OnboardingObjectiveId.knowledgeCardsGenerated.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.knowledgeCardsGenerated.rawValue,
                dependsOn: [OnboardingObjectiveId.cardInventoryComplete.rawValue],
                autoStartWhenReady: true,
                onComplete: { _ in
                    let title = """
                        Knowledge cards generated and ready for review. Help the user understand \
                        what's been created and answer questions about any cards. \
                        The user can delete cards they don't want in the tool pane. \
                        IMPORTANT: DO NOT call next_phase. Phase 3 transitions automatically \
                        when the user clicks "Approve & Create Cards" in the tool pane. \
                        Your role is to review cards and answer questions while they decide.
                        """
                    return [.coordinatorMessage(title: title, details: ["action": "review_cards_await_user_approval"], payload: nil)]
                }
            )
        ]
    }

    var introductoryPrompt: String {
        PromptLibrary.phase3Intro
    }
}
