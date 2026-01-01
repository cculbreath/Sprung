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
//  6. Transition to Phase 4
//
import Foundation

struct PhaseThreeScript: PhaseScript {
    let phase: InterviewPhase = .phase3EvidenceCollection

    let requiredObjectives: [String] = OnboardingObjectiveId.rawValues([
        .evidenceDocumentsCollected,     // Supporting documents uploaded
        .knowledgeCardsGenerated         // KCs created and persisted
        // gitReposAnalyzed and cardInventoryComplete are intermediate steps, not strictly required
    ])

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
                        "objective": OnboardingObjectiveId.evidenceDocumentsCollected.rawValue,
                        "approach": "strategic_requests"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                },
                onComplete: { context in
                    let title = """
                        Evidence documents collected. Now proceeding to git repository selection. \
                        Ask which repositories best showcase their work: \
                        "Let's look at your code. Which repositories best showcase your work? \
                        Active/recent projects, solo or lead-contributor projects, and well-documented code are ideal."
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.gitReposAnalyzed.rawValue,
                        "status": context.status.rawValue
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Git Repository Analysis
            OnboardingObjectiveId.gitReposAnalyzed.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.gitReposAnalyzed.rawValue,
                dependsOn: [OnboardingObjectiveId.evidenceDocumentsCollected.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Git repositories analyzed. Card inventory being generated. \
                        INTERVIEW WHILE WAITING: Use get_user_option to gather dossier insights. \
                        Good topics: availability, self-assessment of strengths, hidden skills not on resume.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.cardInventoryComplete.rawValue,
                        "status": context.status.rawValue,
                        "interview_during_wait": "true"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Card Inventory
            OnboardingObjectiveId.cardInventoryComplete.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.cardInventoryComplete.rawValue,
                dependsOn: [OnboardingObjectiveId.gitReposAnalyzed.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Card inventory complete. Knowledge card generation starting. \
                        CONTINUE INTERVIEWING while KC generation runs (~2-3 min). \
                        This is prime time for dossier questions: concerns to address proactively, \
                        career narrative connections, availability timing. \
                        You'll get a summary when cards are ready—DO NOT acknowledge each individually.
                        """
                    let details = [
                        "next_objective": OnboardingObjectiveId.knowledgeCardsGenerated.rawValue,
                        "status": context.status.rawValue,
                        "batch_processing": "true",
                        "interview_during_wait": "true"
                    ]
                    return [.developerMessage(title: title, details: details, payload: nil)]
                }
            ),

            // MARK: - Knowledge Cards Generated
            OnboardingObjectiveId.knowledgeCardsGenerated.rawValue: ObjectiveWorkflow(
                id: OnboardingObjectiveId.knowledgeCardsGenerated.rawValue,
                dependsOn: [OnboardingObjectiveId.cardInventoryComplete.rawValue],
                autoStartWhenReady: true,
                onComplete: { context in
                    let title = """
                        Knowledge cards generated. Review the cards and ask clarifying questions \
                        if any seem thin or generic. Example: "The 'Industrial Automation' skill card \
                        seems generic. Can you tell me more about what makes your automation work distinctive?" \
                        Then transition to Phase 4 for strategic synthesis.
                        """
                    let details = [
                        "status": context.status.rawValue,
                        "action": "review_cards_then_next_phase"
                    ]
                    // Force next_phase tool call
                    return [.developerMessage(title: title, details: details, payload: nil, toolChoice: OnboardingToolName.nextPhase.rawValue)]
                }
            )
        ]
    }

    var introductoryPrompt: String {
        PromptLibrary.phase3Intro
    }
}
