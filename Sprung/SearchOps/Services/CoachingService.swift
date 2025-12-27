//
//  CoachingService.swift
//  Sprung
//
//  Main orchestration service for the Job Search Coach feature.
//  Manages the coaching flow: activity report -> questions -> recommendations.
//

import Foundation
import SwiftData
import SwiftyJSON
import SwiftOpenAI

@Observable
@MainActor
final class CoachingService {
    private let modelContext: ModelContext
    private let llmService: SearchOpsLLMService
    private let activityReportService: ActivityReportService
    private let sessionStore: CoachingSessionStore
    private let settingsStore: SearchOpsSettingsStore
    private let preferencesStore: SearchPreferencesStore
    private let jobAppStore: JobAppStore
    private let interviewDataStore: InterviewDataStore

    // MARK: - Observable State

    private(set) var state: CoachingState = .idle
    private(set) var currentSession: CoachingSession?
    private(set) var currentQuestion: CoachingQuestion?

    private var conversationId: UUID?
    private var pendingQuestions: [CoachingQuestion] = []
    private var collectedAnswers: [CoachingAnswer] = []
    private var questionIndex: Int = 0
    private var pendingToolCallId: String?

    // Cached context for tool calls
    private var knowledgeCards: [KnowledgeCardDraft] = []
    private var dossierEntries: [JSON] = []

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        llmService: SearchOpsLLMService,
        activityReportService: ActivityReportService,
        sessionStore: CoachingSessionStore,
        settingsStore: SearchOpsSettingsStore,
        preferencesStore: SearchPreferencesStore,
        jobAppStore: JobAppStore,
        interviewDataStore: InterviewDataStore
    ) {
        self.modelContext = modelContext
        self.llmService = llmService
        self.activityReportService = activityReportService
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
        self.preferencesStore = preferencesStore
        self.jobAppStore = jobAppStore
        self.interviewDataStore = interviewDataStore
    }

    // MARK: - Public API

    /// Get today's completed session if it exists
    var todaysSession: CoachingSession? {
        sessionStore.todaysSession()
    }

    /// Check if coaching should auto-start (no active session and no completed session in 24+ hours)
    var shouldAutoStart: Bool {
        guard coachingModelId != nil else { return false }

        // Don't auto-start if there's already an active session in progress
        if state.isActive {
            return false
        }

        // Check if there's a recent completed session (within 24 hours)
        let twentyFourHoursAgo = Date().addingTimeInterval(-86400)
        if let lastSession = sessionStore.lastSessionDate(), lastSession > twentyFourHoursAgo {
            return false
        }

        // No active session and no recent completed session, should auto-start
        return true
    }

    /// Auto-start coaching in background if conditions are met
    /// Call this after discovery onboarding is complete
    func autoStartIfNeeded() {
        guard shouldAutoStart else { return }

        // shouldAutoStart already ensures no active session, so we can start fresh
        Logger.info("🤖 Auto-starting coaching session in background", category: .ai)

        Task {
            do {
                try await startSession()
            } catch {
                Logger.error("Failed to auto-start coaching: \(error)", category: .ai)
            }
        }
    }

    /// Check if there's a completed session for today
    var hasSessionToday: Bool {
        sessionStore.hasCompletedSessionToday
    }

    /// Get the currently selected model ID for coaching (OpenRouter model)
    /// Returns nil if no coaching model is configured
    var coachingModelId: String? {
        let id = UserDefaults.standard.string(forKey: "discoveryCoachingModelId") ?? ""
        return id.isEmpty ? nil : id
    }

    /// Start a new coaching session
    func startSession() async throws {
        // Reset state
        state = .generatingReport
        pendingQuestions = []
        collectedAnswers = []
        questionIndex = 0
        currentQuestion = nil

        // Calculate activity window: since last session that was at least 12 hours ago
        // Sessions within 12 hours don't reset context (allows multiple sessions per day)
        // If no qualifying session, show all activity
        let twelveHoursAgo = Date().addingTimeInterval(-43200)
        let sinceDate = sessionStore.lastSessionDate(before: twelveHoursAgo) ?? .distantPast

        // Generate activity snapshot
        let snapshot = activityReportService.generateSnapshot(since: sinceDate)

        // Load dossier and knowledge cards context
        await loadUserContext()

        // Create new session
        let session = CoachingSession()
        session.activitySummary = snapshot
        session.daysSinceLastSession = sessionStore.daysSinceLastSession()
        session.llmModel = coachingModelId
        currentSession = session

        // Build system prompt with full context
        let systemPrompt = buildSystemPrompt(
            activitySummary: snapshot.textSummary(),
            recentHistory: sessionStore.recentHistorySummary(),
            dossierContext: buildDossierContext(),
            knowledgeCardsList: buildKnowledgeCardsList(),
            activeJobApps: buildActiveJobAppsList()
        )

        // Start conversation with coaching tools (use OpenRouter model)
        guard let modelId = coachingModelId else {
            state = .error("No coaching model configured. Please select a model in Settings.")
            return
        }

        conversationId = llmService.startConversation(
            systemPrompt: systemPrompt,
            tools: CoachingToolSchemas.allTools,
            overrideModelId: modelId
        )

        // Send initial message to trigger tool calls
        try await sendInitialMessage()
    }

    /// Load user context from dossier and knowledge cards
    private func loadUserContext() async {
        // Load dossier entries
        dossierEntries = await interviewDataStore.list(dataType: "candidate_dossier_entry")

        // Load knowledge cards
        let knowledgeCardJSONs = await interviewDataStore.list(dataType: "knowledge_card")
        knowledgeCards = knowledgeCardJSONs.map { KnowledgeCardDraft(json: $0) }

        Logger.debug("Coaching: loaded \(dossierEntries.count) dossier entries, \(knowledgeCards.count) knowledge cards", category: .ai)
    }

    /// Submit answer to current question
    func submitAnswer(value: Int, label: String) async throws {
        guard let question = currentQuestion else {
            Logger.warning("No current question to answer", category: .ai)
            return
        }

        // Clear question immediately so UI shows loading
        currentQuestion = nil
        state = .waitingForAnswer

        // Record answer
        let answer = CoachingAnswer(
            questionId: question.id,
            selectedValue: value,
            selectedLabel: label
        )
        collectedAnswers.append(answer)
        currentSession?.answers = collectedAnswers

        // Continue conversation with the answer
        try await continueWithAnswer(answer)
    }

    /// Regenerate by deleting current session and re-running full coaching flow
    func regenerateRecommendations(for session: CoachingSession? = nil) async throws {
        // Delete the existing session
        if let targetSession = session ?? currentSession ?? todaysSession {
            sessionStore.delete(targetSession)
        }

        // Cancel any in-progress state
        cancelSession()

        // Start fresh
        try await startSession()
    }

    /// Cancel the current coaching session
    func cancelSession() {
        if let convId = conversationId {
            llmService.endConversation(convId)
        }
        conversationId = nil
        currentSession = nil
        currentQuestion = nil
        pendingQuestions = []
        collectedAnswers = []
        pendingToolCallId = nil
        state = .idle
    }

    // MARK: - Private Implementation

    private func sendInitialMessage() async throws {
        guard let convId = conversationId else { return }

        // Add initial user message
        llmService.addUserMessage(
            conversationId: convId,
            message: "Please start my coaching session for today. Ask me questions to understand how I'm doing."
        )

        // Get first response - uses .auto so LLM can research before asking first question
        try await processNextResponse()
    }

    /// Process the next LLM response, handling tool calls or final text
    private func processNextResponse() async throws {
        guard let convId = conversationId else { return }

        // Tool choice based on conversation phase:
        // - 0 answers: .auto - LLM can research + ask first question
        // - 1 answer: Force second question
        // - 2+ answers: .auto - can ask Q3, give recommendations, or research more
        let toolChoice: ToolChoice
        switch collectedAnswers.count {
        case 0:
            // First call - allow research tools alongside question
            toolChoice = .auto
        case 1:
            // After first answer - force second question
            toolChoice = .function(name: CoachingToolSchemas.multipleChoiceToolName)
        default:
            // After 2+ answers - flexible: can ask more, recommend, or research
            toolChoice = .auto
        }

        do {
            // parallelToolCalls is enabled by default in LLMRequestBuilder
            let message = try await llmService.sendMessageSingleTurn(
                conversationId: convId,
                toolChoice: toolChoice
            )

            // Handle all tool calls (may be multiple in parallel)
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                // Process background tools first, then handle question tool
                var questionToolCallId: String?
                var questionToolArgs: String?

                for toolCall in toolCalls {
                    let toolName = toolCall.function.name ?? ""
                    let toolCallId = toolCall.id ?? UUID().uuidString

                    if toolName == CoachingToolSchemas.multipleChoiceToolName {
                        // Save for after processing background tools
                        questionToolCallId = toolCallId
                        questionToolArgs = toolCall.function.arguments
                    } else {
                        // Handle background research tools immediately
                        let result = await handleBackgroundTool(name: toolName, arguments: toolCall.function.arguments)
                        llmService.addToolResult(conversationId: convId, toolCallId: toolCallId, result: result)
                    }
                }

                // Now handle the question tool if present
                if let toolCallId = questionToolCallId, let argsString = questionToolArgs {
                    let arguments = JSON(parseJSON: argsString)

                    guard let question = CoachingToolSchemas.parseQuestionFromJSON(arguments) else {
                        Logger.error("Failed to parse coaching question", category: .ai)
                        state = .error("Failed to parse question from coach")
                        return
                    }

                    // Store question and pending tool call
                    pendingQuestions.append(question)
                    currentSession?.questions = (currentSession?.questions ?? []) + [question]
                    pendingToolCallId = toolCallId

                    // Update UI state - user must answer before we continue
                    questionIndex += 1
                    currentQuestion = question
                    state = .askingQuestion(question: question, index: questionIndex, total: 3)

                    Logger.debug("Coaching: showing question \(questionIndex), waiting for user", category: .ai)
                    return
                }

                // If we handled background tools but no question, continue for next response
                if !toolCalls.isEmpty && questionToolCallId == nil {
                    try await processNextResponse()
                    return
                }
            }

            // No tool call - this is the final recommendations
            let recommendations = message.content ?? ""
            await handleFinalRecommendations(recommendations)

        } catch {
            Logger.error("Failed to get coaching response: \(error)", category: .ai)
            state = .error(error.localizedDescription)
            throw error
        }
    }

    /// Handle background research tool calls (knowledge cards, job descriptions, resumes)
    private func handleBackgroundTool(name: String, arguments: String) async -> String {
        let args = JSON(parseJSON: arguments)

        switch name {
        case CoachingToolSchemas.getKnowledgeCardToolName:
            return handleGetKnowledgeCard(args)

        case CoachingToolSchemas.getJobDescriptionToolName:
            return handleGetJobDescription(args)

        case CoachingToolSchemas.getResumeToolName:
            return await handleGetResume(args)

        default:
            return JSON(["error": "Unknown tool: \(name)"]).rawString() ?? "{}"
        }
    }

    /// Handle get_knowledge_card tool call
    private func handleGetKnowledgeCard(_ args: JSON) -> String {
        let cardId = args["card_id"].stringValue
        let startLine = args["start_line"].int
        let endLine = args["end_line"].int

        guard let card = knowledgeCards.first(where: { $0.id.uuidString == cardId }) else {
            return JSON(["error": "Knowledge card not found: \(cardId)"]).rawString() ?? "{}"
        }

        var content = card.content

        // Apply line range if specified
        if let start = startLine, let end = endLine {
            let lines = content.components(separatedBy: "\n")
            let safeStart = max(0, start - 1)  // 1-indexed to 0-indexed
            let safeEnd = min(lines.count, end)
            if safeStart < safeEnd {
                content = lines[safeStart..<safeEnd].joined(separator: "\n")
            }
        }

        var result = JSON()
        result["card_id"].string = cardId
        result["title"].string = card.title
        result["type"].string = card.cardType
        result["organization"].string = card.organization
        result["time_period"].string = card.timePeriod
        result["content"].string = content
        result["word_count"].int = card.wordCount

        return result.rawString() ?? "{}"
    }

    /// Handle get_job_description tool call
    private func handleGetJobDescription(_ args: JSON) -> String {
        let jobAppId = args["job_app_id"].stringValue

        guard let uuid = UUID(uuidString: jobAppId),
              let jobApp = jobAppStore.jobApps.first(where: { $0.id == uuid }) else {
            return JSON(["error": "Job application not found: \(jobAppId)"]).rawString() ?? "{}"
        }

        var result = JSON()
        result["job_app_id"].string = jobAppId
        result["company"].string = jobApp.companyName
        result["position"].string = jobApp.jobPosition
        result["stage"].string = jobApp.stage.rawValue
        result["job_description"].string = jobApp.jobDescription
        result["job_url"].string = jobApp.postingURL.isEmpty ? jobApp.jobApplyLink : jobApp.postingURL
        result["notes"].string = jobApp.notes
        result["applied_date"].string = jobApp.appliedDate?.ISO8601Format()

        return result.rawString() ?? "{}"
    }

    /// Handle get_resume tool call
    private func handleGetResume(_ args: JSON) async -> String {
        let resumeId = args["resume_id"].stringValue
        let section = args["section"].string

        let descriptor = FetchDescriptor<Resume>()
        guard let resumes = try? modelContext.fetch(descriptor),
              let uuid = UUID(uuidString: resumeId),
              let resume = resumes.first(where: { $0.id == uuid }) else {
            return JSON(["error": "Resume not found: \(resumeId)"]).rawString() ?? "{}"
        }

        var result = JSON()
        result["resume_id"].string = resumeId
        result["template"].string = resume.template?.name ?? "Unknown Template"

        // Get resume content from TreeNode
        if let rootNode = resume.rootNode {
            if let section = section {
                // Get specific section
                if let sectionNode = rootNode.children?.first(where: { $0.label == section }) {
                    result["section"].string = section
                    result["content"].string = extractNodeText(sectionNode)
                }
            } else {
                // Get summary of all sections
                var sections: [String] = []
                for child in rootNode.children ?? [] {
                    sections.append(child.label)
                }
                result["available_sections"].arrayObject = sections
                if let summaryNode = resume.rootNode?.children?.first(where: { $0.label == "summary" }) {
                    result["summary"].string = extractNodeText(summaryNode)
                }
            }
        }

        return result.rawString() ?? "{}"
    }

    /// Extract text content from a TreeNode and its children
    private func extractNodeText(_ node: TreeNode) -> String {
        var text = node.value
        if let children = node.children {
            for child in children.sorted(by: { $0.myIndex < $1.myIndex }) {
                let childText = extractNodeText(child)
                if !childText.isEmpty {
                    if !text.isEmpty { text += "\n" }
                    if !child.name.isEmpty {
                        text += "\(child.name): "
                    }
                    text += childText
                }
            }
        }
        return text
    }

    private func continueWithAnswer(_ answer: CoachingAnswer) async throws {
        guard let convId = conversationId,
              let toolCallId = pendingToolCallId else { return }

        state = .waitingForAnswer
        pendingToolCallId = nil

        // Send tool result with user's answer as content
        let toolResult = JSON([
            "selected_value": answer.selectedValue,
            "selected_label": answer.selectedLabel
        ])
        llmService.addToolResult(
            conversationId: convId,
            toolCallId: toolCallId,
            result: toolResult.rawString() ?? "{}"
        )

        // Get next response - tool choice is determined by collectedAnswers.count
        try await processNextResponse()
    }

    private func handleFinalRecommendations(_ recommendations: String) async {
        guard let session = currentSession else { return }

        // Update session with recommendations
        session.recommendations = recommendations
        session.questionCount = collectedAnswers.count

        // Show recommendations and request follow-up offer
        state = .showingRecommendations(recommendations: recommendations)

        // Request a contextual follow-up offer from the model
        await requestFollowUpOffer()
    }

    /// Request the model to offer a contextual follow-up action
    private func requestFollowUpOffer() async {
        guard let convId = conversationId else {
            // No conversation, just complete
            await completeSession()
            return
        }

        // Add a user message prompting for follow-up
        llmService.addUserMessage(
            conversationId: convId,
            message: "Based on our conversation, what would be most helpful for me to do next? Offer me a contextual follow-up action using the coaching_multiple_choice tool."
        )

        do {
            // Use .auto to allow research tools alongside follow-up question
            let message = try await llmService.sendMessageSingleTurn(
                conversationId: convId,
                toolChoice: .auto
            )

            // Handle any tool calls (research tools + question tool)
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                var questionToolCallId: String?
                var questionToolArgs: String?

                // Process background tools first
                for toolCall in toolCalls {
                    let toolName = toolCall.function.name ?? ""
                    let toolCallId = toolCall.id ?? UUID().uuidString

                    if toolName == CoachingToolSchemas.multipleChoiceToolName {
                        questionToolCallId = toolCallId
                        questionToolArgs = toolCall.function.arguments
                    } else {
                        // Handle research tools
                        let result = await handleBackgroundTool(name: toolName, arguments: toolCall.function.arguments)
                        llmService.addToolResult(conversationId: convId, toolCallId: toolCallId, result: result)
                    }
                }

                // Now handle the follow-up question if present
                if let toolCallId = questionToolCallId, let argsString = questionToolArgs {
                    let arguments = JSON(parseJSON: argsString)
                    if var question = CoachingToolSchemas.parseQuestionFromJSON(arguments) {
                        // Ensure it's marked as follow-up type
                        question = CoachingQuestion(
                            questionText: question.questionText,
                            options: question.options,
                            questionType: .followUp
                        )

                        pendingToolCallId = toolCallId
                        currentQuestion = question
                        state = .askingFollowUp(question: question)

                        Logger.debug("Coaching: showing follow-up question", category: .ai)
                        return
                    }
                }
            }

            // If no follow-up question, complete the session
            await completeSession()

        } catch {
            Logger.warning("Failed to get follow-up offer: \(error)", category: .ai)
            // Not critical - just complete without follow-up
            await completeSession()
        }
    }

    /// Complete the coaching session
    private func completeSession() async {
        guard let session = currentSession else { return }

        session.completedAt = Date()
        sessionStore.add(session)

        // Clean up conversation
        if let convId = conversationId {
            llmService.endConversation(convId)
        }
        conversationId = nil

        state = .complete(sessionId: session.id)
        Logger.info("Coaching session completed with \(collectedAnswers.count) questions", category: .ai)
    }

    /// Handle follow-up answer selection
    func submitFollowUpAnswer(value: Int, label: String) async throws {
        guard let question = currentQuestion,
              question.questionType == .followUp else {
            Logger.warning("No follow-up question to answer", category: .ai)
            return
        }

        currentQuestion = nil

        // Map the answer to an action
        let action = mapFollowUpAnswer(value: value, label: label)

        if action == .done {
            // User chose to end session
            await completeSession()
            return
        }

        // Execute the follow-up action
        state = .executingFollowUp(action: action)

        do {
            try await executeFollowUpAction(action)
        } catch {
            Logger.error("Failed to execute follow-up action: \(error)", category: .ai)
            // Still complete the session even if follow-up fails
            await completeSession()
        }
    }

    /// Map follow-up answer to action (based on value or label matching)
    private func mapFollowUpAnswer(value: Int, label: String) -> CoachingFollowUpAction {
        let lowerLabel = label.lowercased()

        if lowerLabel.contains("focus job") || lowerLabel.contains("prioritize") || lowerLabel.contains("pick") {
            return .chooseFocusJobs
        } else if lowerLabel.contains("task") || lowerLabel.contains("to-do") || lowerLabel.contains("todo") {
            return .generateTasks
        } else if lowerLabel.contains("stale") || lowerLabel.contains("follow-up") || lowerLabel.contains("followup") {
            return .staleAppCheck
        } else if lowerLabel.contains("network") || lowerLabel.contains("contact") || lowerLabel.contains("reach out") {
            return .networkingSuggestions
        } else if lowerLabel.contains("quick") || lowerLabel.contains("momentum") || lowerLabel.contains("easy") {
            return .quickWins
        } else if lowerLabel.contains("done") || lowerLabel.contains("good") || lowerLabel.contains("later") {
            return .done
        }

        // Default based on value (lower values = more actionable options typically)
        return value <= 2 ? .generateTasks : .done
    }

    /// Execute the selected follow-up action
    private func executeFollowUpAction(_ action: CoachingFollowUpAction) async throws {
        guard let session = currentSession else { return }

        // For now, append action result to recommendations
        // In future, these could trigger actual tool executions

        let actionResult: String

        switch action {
        case .chooseFocusJobs:
            actionResult = "\n\n---\n**Focus Jobs**: I'll help you pick your top focus jobs. Check the Pipeline view to see AI-recommended priorities."

        case .generateTasks:
            actionResult = "\n\n---\n**Task List**: Your daily tasks have been queued for generation. Check the Today view for your prioritized task list."

        case .staleAppCheck:
            actionResult = "\n\n---\n**Stale Applications**: Review applications in the Pipeline view - filter by 'Applied' stage and sort by date to find ones needing follow-up."

        case .networkingSuggestions:
            actionResult = "\n\n---\n**Networking**: Check your Contacts view for relationship health indicators. Reach out to any marked as 'Needs Attention'."

        case .quickWins:
            actionResult = "\n\n---\n**Quick Wins**:\n• Update your LinkedIn headline\n• Star 3 promising saved jobs\n• Send one brief check-in message\n• Review one pending application status"

        case .done:
            actionResult = ""
        }

        if !actionResult.isEmpty {
            session.recommendations += actionResult
            sessionStore.update(session)
        }

        await completeSession()
    }

    // MARK: - Context Building

    /// Build formatted dossier context from dossier entries
    private func buildDossierContext() -> String {
        guard !dossierEntries.isEmpty else {
            return "No dossier entries available yet."
        }

        var sections: [String] = []
        for entry in dossierEntries {
            let section = entry["section"].stringValue
            let value = entry["value"].stringValue
            if !section.isEmpty && !value.isEmpty {
                sections.append("**\(section)**: \(value)")
            }
        }

        return sections.isEmpty ? "No dossier entries available yet." : sections.joined(separator: "\n")
    }

    /// Build list of available knowledge cards with metadata
    private func buildKnowledgeCardsList() -> String {
        guard !knowledgeCards.isEmpty else {
            return "No knowledge cards available."
        }

        var lines: [String] = []
        for card in knowledgeCards {
            var line = "- ID: `\(card.id.uuidString)` | **\(card.title)**"
            if let cardType = card.cardType, !cardType.isEmpty {
                line += " (\(cardType))"
            }
            if let organization = card.organization, !organization.isEmpty {
                line += " @ \(organization)"
            }
            if let timePeriod = card.timePeriod, !timePeriod.isEmpty {
                line += " | \(timePeriod)"
            }
            line += " | \(card.wordCount) words"
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    /// Build list of active job applications (identified through applying stages)
    private func buildActiveJobAppsList() -> String {
        let activeStages: [ApplicationStage] = [.identified, .researching, .applying, .applied, .interviewing, .offer]
        let activeApps = jobAppStore.jobApps.filter { activeStages.contains($0.stage) }

        guard !activeApps.isEmpty else {
            return "No active job applications."
        }

        var lines: [String] = []
        for app in activeApps.prefix(20) {  // Limit to 20 to avoid overwhelming context
            var line = "- ID: `\(app.id.uuidString)` | **\(app.companyName)** - \(app.jobPosition)"
            line += " | Stage: \(app.stage.rawValue)"
            if let appliedDate = app.appliedDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                line += " | Applied: \(formatter.string(from: appliedDate))"
            }
            lines.append(line)
        }

        if activeApps.count > 20 {
            lines.append("... and \(activeApps.count - 20) more active applications")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(
        activitySummary: String,
        recentHistory: String,
        dossierContext: String,
        knowledgeCardsList: String,
        activeJobApps: String
    ) -> String {
        let preferences = preferencesStore.current()

        return """
            You are a supportive and insightful job search coach. Your role is to help the user stay motivated, focused, and strategic in their job search journey.

            ## Your Coaching Style
            - Be warm, encouraging, and conversational (not terse or bullet-point heavy)
            - Write in flowing paragraphs with personality
            - Acknowledge challenges without being patronizing
            - Celebrate wins enthusiastically - specific praise matters!
            - Reference the user's REAL activity data (companies, numbers, dates)
            - If they've been inactive 7+ days, offer understanding and gentle motivation

            ## Understanding the Workflows

            ### Job Application Workflow
            The user follows this pipeline for job applications:
            1. **Identified/Gathered** - Job leads are collected but no action taken yet
            2. **Researching** - Learning about the company and role
            3. **Applying** - Preparing materials (creating/customizing resumes and cover letters with AI assistance)
            4. **Applied** - Application actually submitted to the company
            5. **Interviewing** - In the interview process
            6. **Offer** - Received an offer

            IMPORTANT: "Identified" or "Gathered" means NO application has been submitted yet. These are leads to evaluate. "Applied" means they ACTUALLY submitted the application. Don't confuse gathering leads with applying!

            ### Networking Event Workflow
            The user follows this pipeline for networking events:
            1. **Discovered** - Found an event but not yet evaluated
            2. **Evaluating/Recommended** - Considering whether to attend
            3. **Planned** - Committed to attend (on their calendar)
            4. **Attended** - Actually went to the event
            5. **Debriefed** - Captured contacts and notes after attending

            IMPORTANT: "Discovered" events are NOT on their calendar - they're just leads. Only "Planned" events are committed. Don't assume discovered events are being attended!

            ## Activity Report (Context Period)
            \(activitySummary)

            ## Recent Coaching History
            \(recentHistory)

            ## User's Job Search Goals
            - Target Sectors: \(preferences.targetSectors.joined(separator: ", "))
            - Primary Location: \(preferences.primaryLocation)
            - Remote Acceptable: \(preferences.remoteAcceptable ? "Yes" : "No")
            - Weekly Application Target: \(preferences.weeklyApplicationTarget)
            - Weekly Networking Target: \(preferences.weeklyNetworkingTarget)
            - Preferred Company Size: \(preferences.companySizePreference.rawValue)

            ## Applicant Background (Dossier)
            \(dossierContext)

            ## Available Knowledge Cards
            These are detailed narratives about the user's experience. You can request full content using the `get_knowledge_card` tool.
            \(knowledgeCardsList)

            ## Active Job Applications
            The user's current job pipeline. You can get full job descriptions using the `get_job_description` tool.
            \(activeJobApps)

            ## Available Research Tools

            You have access to background research tools that can be called AT ANY TIME during the coaching session:

            - **`get_knowledge_card`**: Retrieve detailed content from a knowledge card to learn more about the user's specific experience, skills, or achievements. Use this when you want to give personalized advice referencing their actual work history.
              - Parameters: `card_id` (required), `start_line` (optional), `end_line` (optional)

            - **`get_job_description`**: Get the full job description for a specific application. Use this to give targeted advice about a particular role they're pursuing.
              - Parameters: `job_app_id` (required)

            - **`get_resume`**: Retrieve a user's resume content. Use this to understand what materials they've prepared.
              - Parameters: `resume_id` (required), `section` (optional - e.g., "summary", "work", "skills")

            **IMPORTANT**: You can call these research tools at any point - before asking questions, alongside questions, or before giving recommendations. Use them proactively to personalize your coaching. The tools return immediately and won't interrupt the coaching flow.

            ## Coaching Flow

            ### Phase 1: Check-In Questions (2-3 questions)

            You MUST call the `coaching_multiple_choice` tool 2-3 times to understand the user's current state:
            - Question 1: Energy/motivation level today
            - Question 2: Main challenge or blocker right now
            - Question 3 (optional): What they'd like to focus on, OR a clarifying question based on their answers

            You MAY also call research tools (`get_knowledge_card`, `get_job_description`, `get_resume`) at any point to gather context for more personalized coaching. These can be called alongside the question tool.

            You MAY include brief conversational text WITH your tool call to acknowledge their previous answer or add context. Keep this text short (1-2 sentences) and ensure it flows naturally into the question.

            ### Phase 2: Coaching Response (after 2-3 questions answered)

            Provide a SUBSTANTIAL coaching response (5-8 paragraphs) structured as:

            **1. Activity Review & Acknowledgment (1-2 paragraphs)**
            Start by reviewing what they've accomplished during the context period. Be specific:
            - "You've submitted 45 applications this week - that's serious momentum!"
            - "I see you added 9 networking events and created cover letters for AMD and Applied Materials."
            - If inactive: "It's been a quiet week, and that's okay. Let's use today to rebuild momentum gently."

            **2. Personalized Response to Their Check-In (1-2 paragraphs)**
            Acknowledge their stated energy level and challenges. Show you heard them:
            - "You mentioned finding the right roles is your main friction point..."
            - "Given you're feeling steady but not energized, let's keep today focused..."

            **3. Today's Action Plan (2-3 paragraphs)**
            Provide 2-4 specific, actionable recommendations:
            - Be concrete: specific job boards, search keywords, company names
            - Tailor to their energy level (low energy = smaller tasks, high energy = ambitious goals)
            - Include time estimates when helpful ("a 30-minute focused search")
            - Reference their actual data (companies they've applied to, events they've added)

            **4. Encouragement & Closing (1 paragraph)**
            End with genuine encouragement tailored to their situation. Not generic cheerleading.

            ### Important Guidelines

            - DO NOT make up activity data - only reference what's in the activity report
            - DO NOT be terse or overly bullet-pointed - write in warm, flowing prose
            - DO NOT end your coaching response with a question or offer to do more
            - Use markdown formatting: **bold** for emphasis, ### headers to organize longer sections

            ### Output Formatting Rules
            - Separate paragraphs with a blank line (double newline)
            - Use markdown headers (### or **bold**) to create visual sections
            - Each major section of your response should be separated by a blank line
            - Don't run all your text together - give it breathing room

            ## Follow-Up Offers

            After providing recommendations, you may be asked to offer a contextual follow-up action. When this happens:

            1. Use the `coaching_multiple_choice` tool with `question_type: "follow_up"`

            2. Offer ONE contextual suggestion based on what the user shared, plus alternatives:
               - If they mentioned finding roles is hard → "Pick my top focus jobs for today"
               - If they're low energy → "Give me some quick wins"
               - If they're motivated → "Generate my task list"
               - If they mentioned networking → "Suggest networking contacts to reach out to"
               - If they have many applications → "Check for applications needing follow-up"

            3. Always include "I'm good for now" as the last option
            """
    }
}
