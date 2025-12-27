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
    private let llmService: DiscoveryLLMService
    private let activityReportService: ActivityReportService
    private let sessionStore: CoachingSessionStore
    private let dailyTaskStore: DailyTaskStore
    private let settingsStore: DiscoverySettingsStore
    private let preferencesStore: SearchPreferencesStore
    private let jobAppStore: JobAppStore
    private let interviewDataStore: InterviewDataStore

    /// Reference to agent service for triggering workflows like chooseBestJobs
    /// Set after initialization by coordinator to avoid circular dependency
    var agentService: DiscoveryAgentService?

    // MARK: - Observable State

    private(set) var state: CoachingState = .idle
    private(set) var currentSession: CoachingSession?
    private(set) var currentQuestion: CoachingQuestion?

    private var conversationId: UUID?
    private var pendingQuestions: [CoachingQuestion] = []
    private var collectedAnswers: [CoachingAnswer] = []
    private var questionIndex: Int = 0

    /// Queue of pending question tool calls (toolCallId, question)
    private var pendingQuestionToolCalls: [(toolCallId: String, question: CoachingQuestion)] = []
    /// The tool call ID for the currently displayed question
    private var currentQuestionToolCallId: String?

    // Cached context for tool calls
    private var knowledgeCards: [KnowledgeCardDraft] = []
    private var dossierEntries: [JSON] = []

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        llmService: DiscoveryLLMService,
        activityReportService: ActivityReportService,
        sessionStore: CoachingSessionStore,
        dailyTaskStore: DailyTaskStore,
        settingsStore: DiscoverySettingsStore,
        preferencesStore: SearchPreferencesStore,
        jobAppStore: JobAppStore,
        interviewDataStore: InterviewDataStore
    ) {
        self.modelContext = modelContext
        self.llmService = llmService
        self.activityReportService = activityReportService
        self.sessionStore = sessionStore
        self.dailyTaskStore = dailyTaskStore
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
        pendingQuestionToolCalls = []
        currentQuestionToolCallId = nil
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
                // Collect question tool calls and handle research tools immediately
                var questionToolCalls: [(toolCallId: String, question: CoachingQuestion)] = []

                for toolCall in toolCalls {
                    let toolName = toolCall.function.name ?? ""
                    let toolCallId = toolCall.id ?? UUID().uuidString

                    if toolName == CoachingToolSchemas.multipleChoiceToolName {
                        // Parse and queue the question
                        let arguments = JSON(parseJSON: toolCall.function.arguments)
                        if let question = CoachingToolSchemas.parseQuestionFromJSON(arguments) {
                            questionToolCalls.append((toolCallId: toolCallId, question: question))
                        } else {
                            // Send error response for unparseable question
                            llmService.addToolResult(conversationId: convId, toolCallId: toolCallId, result: "{\"error\": \"Failed to parse question\"}")
                        }
                    } else {
                        // Handle background research tools immediately
                        let result = await handleBackgroundTool(name: toolName, arguments: toolCall.function.arguments)
                        llmService.addToolResult(conversationId: convId, toolCallId: toolCallId, result: result)
                    }
                }

                // If we have question tool calls, queue them and show the first one
                if !questionToolCalls.isEmpty {
                    pendingQuestionToolCalls = questionToolCalls
                    Logger.debug("Coaching: queued \(questionToolCalls.count) question(s)", category: .ai)
                    showNextQueuedQuestion()
                    return
                }

                // If we only handled background tools, continue for next response
                try await processNextResponse()
                return
            }

            // No tool call - this is the final recommendations
            let recommendations = message.content ?? ""
            await handleFinalRecommendations(recommendations)

        } catch {
            // Check for missing tool output error and try to recover
            if let toolCallId = extractMissingToolCallId(from: error) {
                Logger.warning("⚠️ Missing tool output for \(toolCallId), sending error response", category: .ai)
                llmService.addToolResult(
                    conversationId: convId,
                    toolCallId: toolCallId,
                    result: "{\"error\": \"Tool call was not processed. Please continue without this information.\"}"
                )
                // Retry after providing the error response
                try await processNextResponse()
                return
            }

            Logger.error("Failed to get coaching response: \(error)", category: .ai)
            state = .error(error.localizedDescription)
            throw error
        }
    }

    /// Extract tool call ID from "No tool output found" error message
    private func extractMissingToolCallId(from error: Error) -> String? {
        let errorString = String(describing: error)
        // Pattern: "No tool output found for function call call_XXXXX"
        guard errorString.contains("No tool output found for function call") else {
            return nil
        }

        // Extract the call_XXXXX identifier
        let pattern = "call_[A-Za-z0-9]+"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: errorString, range: NSRange(errorString.startIndex..., in: errorString)),
              let range = Range(match.range, in: errorString) else {
            return nil
        }

        return String(errorString[range])
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

        case CoachingToolSchemas.chooseBestJobsToolName:
            return await handleChooseBestJobs(args)

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
        result["status"].string = jobApp.status.displayName
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

    /// Handle choose_best_jobs tool call - triggers the job selection workflow
    private func handleChooseBestJobs(_ args: JSON) async -> String {
        guard let agent = agentService else {
            return JSON(["error": "Agent service not configured"]).rawString() ?? "{}"
        }

        let count = min(max(args["count"].intValue, 1), 10)
        let reason = args["reason"].stringValue

        Logger.info("🎯 Coaching: triggering choose best jobs (count: \(count), reason: \(reason))", category: .ai)

        // Get all jobs in new (identified) status
        let identifiedJobs = jobAppStore.jobApps(forStatus: .new)
        guard !identifiedJobs.isEmpty else {
            return JSON([
                "success": false,
                "error": "No jobs in Identified status to choose from",
                "identified_count": 0
            ]).rawString() ?? "{}"
        }

        // Build job tuples for agent
        let jobTuples = identifiedJobs.map { job in
            (
                id: job.id,
                company: job.companyName,
                role: job.jobPosition,
                description: job.jobDescription
            )
        }

        // Build knowledge context from cached knowledge cards
        let knowledgeContext = knowledgeCards
            .map { card in
                let typeLabel = card.cardType ?? "general"
                return "[\(typeLabel)] \(card.title):\n\(card.content)"
            }
            .joined(separator: "\n\n")

        // Build dossier context from cached dossier entries
        let dossierContext = dossierEntries
            .map { entry in
                let section = entry["section"].stringValue
                let value = entry["value"].stringValue
                return "\(section): \(value)"
            }
            .joined(separator: "\n")

        do {
            let result = try await agent.chooseBestJobs(
                jobs: jobTuples,
                knowledgeContext: knowledgeContext,
                dossierContext: dossierContext,
                count: count
            )

            // Advance selected jobs to Queued status
            for selection in result.selections {
                if let jobApp = jobAppStore.jobApp(byId: selection.jobId) {
                    jobAppStore.setStatus(jobApp, to: .queued)
                }
            }

            // Build response for LLM
            var response = JSON()
            response["success"].bool = true
            response["selected_count"].int = result.selections.count
            response["identified_count"].int = identifiedJobs.count

            var selections: [JSON] = []
            for selection in result.selections {
                var sel = JSON()
                sel["company"].string = selection.company
                sel["role"].string = selection.role
                sel["match_score"].double = selection.matchScore
                sel["reasoning"].string = selection.reasoning
                selections.append(sel)
            }
            response["selections"].arrayObject = selections.map { $0.object }
            response["overall_analysis"].string = result.overallAnalysis
            response["considerations"].arrayObject = result.considerations

            Logger.info("✅ Choose best jobs completed: \(result.selections.count) selected", category: .ai)
            return response.rawString() ?? "{}"

        } catch {
            Logger.error("Failed to choose best jobs: \(error)", category: .ai)
            return JSON([
                "success": false,
                "error": error.localizedDescription,
                "identified_count": identifiedJobs.count
            ]).rawString() ?? "{}"
        }
    }

    private func continueWithAnswer(_ answer: CoachingAnswer) async throws {
        guard let convId = conversationId else { return }

        state = .waitingForAnswer

        // Send tool result for this answer
        let toolResult = JSON([
            "selected_value": answer.selectedValue,
            "selected_label": answer.selectedLabel
        ])

        // Get the tool call ID for this question (it was just answered, so it's the one we just showed)
        // The current question's tool call ID was removed from the queue when we showed it
        // We stored it separately when showing the question
        if let toolCallId = currentQuestionToolCallId {
            llmService.addToolResult(
                conversationId: convId,
                toolCallId: toolCallId,
                result: toolResult.rawString() ?? "{}"
            )
            currentQuestionToolCallId = nil
        }

        // Check if there are more queued questions from parallel tool calls
        if !pendingQuestionToolCalls.isEmpty {
            showNextQueuedQuestion()
            return
        }

        // No more queued questions - get next response from LLM
        try await processNextResponse()
    }

    /// Show the next question from the queue
    private func showNextQueuedQuestion() {
        guard !pendingQuestionToolCalls.isEmpty else { return }

        let (toolCallId, question) = pendingQuestionToolCalls.removeFirst()
        currentQuestionToolCallId = toolCallId

        // Store question
        pendingQuestions.append(question)
        currentSession?.questions = (currentSession?.questions ?? []) + [question]

        // Update UI state
        questionIndex += 1
        currentQuestion = question
        state = .askingQuestion(question: question, index: questionIndex, total: max(3, questionIndex + pendingQuestionToolCalls.count))

        Logger.debug("Coaching: showing question \(questionIndex) (queued: \(pendingQuestionToolCalls.count) remaining)", category: .ai)
    }

    private func handleFinalRecommendations(_ recommendations: String) async {
        guard let session = currentSession else { return }

        // Store recommendations (tasks will be generated via forced tool call at end of session)
        session.recommendations = recommendations
        session.questionCount = collectedAnswers.count

        // Show recommendations and request follow-up offer
        state = .showingRecommendations(recommendations: recommendations)

        // Request a contextual follow-up offer from the model
        await requestFollowUpOffer()
    }

    /// Parse recommendations to extract prose and JSON tasks
    private func parseRecommendationsAndTasks(_ response: String) -> (prose: String, tasks: [DailyTask]) {
        // Look for JSON block at the end of response
        // Format: ```json\n{...}\n``` or just {...} at the end
        var prose = response
        var tasks: [DailyTask] = []

        // Try to find JSON block with markdown code fence
        if let jsonStart = response.range(of: "```json", options: .backwards),
           let jsonEnd = response.range(of: "```", options: .backwards, range: jsonStart.upperBound..<response.endIndex) {
            let jsonString = String(response[jsonStart.upperBound..<jsonEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            prose = String(response[..<jsonStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            tasks = parseTasksFromJSON(jsonString)
        }
        // Try to find bare JSON object at end
        else if let lastBrace = response.lastIndex(of: "}"),
                let firstBrace = response[..<lastBrace].lastIndex(of: "{"),
                response[firstBrace...].contains("daily_tasks") {
            let jsonString = String(response[firstBrace...lastBrace])
            prose = String(response[..<firstBrace]).trimmingCharacters(in: .whitespacesAndNewlines)
            tasks = parseTasksFromJSON(jsonString)
        }

        if tasks.isEmpty {
            Logger.warning("Coaching: No daily tasks found in response", category: .ai)
        } else {
            Logger.info("Coaching: Parsed \(tasks.count) daily tasks from response", category: .ai)
        }

        return (prose, tasks)
    }

    /// Parse JSON string into DailyTask array
    private func parseTasksFromJSON(_ jsonString: String) -> [DailyTask] {
        let json = JSON(parseJSON: jsonString)
        let tasksArray = json["daily_tasks"].arrayValue

        return tasksArray.compactMap { taskJSON -> DailyTask? in
            let taskTypeStr = taskJSON["task_type"].stringValue
            guard let taskType = mapTaskType(taskTypeStr) else {
                Logger.warning("Coaching: Unknown task type '\(taskTypeStr)'", category: .ai)
                return nil
            }

            let title = taskJSON["title"].stringValue
            guard !title.isEmpty else { return nil }

            let task = DailyTask()
            task.taskType = taskType
            task.title = title
            task.taskDescription = taskJSON["description"].string
            task.priority = taskJSON["priority"].intValue
            task.estimatedMinutes = taskJSON["estimated_minutes"].int
            task.isLLMGenerated = true

            // Handle related_id if present
            if let relatedIdStr = taskJSON["related_id"].string,
               let relatedId = UUID(uuidString: relatedIdStr) {
                // Assign to appropriate relationship based on task type
                switch taskType {
                case .gatherLeads:
                    task.relatedJobSourceId = relatedId
                case .customizeMaterials, .submitApplication, .followUp:
                    task.relatedJobAppId = relatedId
                case .networking:
                    task.relatedContactId = relatedId
                case .eventPrep, .eventDebrief:
                    task.relatedEventId = relatedId
                }
            }

            return task
        }
    }

    /// Map task type string from prompt to DailyTaskType enum
    private func mapTaskType(_ typeStr: String) -> DailyTaskType? {
        switch typeStr.lowercased() {
        case "gather": return .gatherLeads
        case "customize": return .customizeMaterials
        case "apply": return .submitApplication
        case "follow_up", "followup": return .followUp
        case "networking": return .networking
        case "event_prep", "eventprep": return .eventPrep
        case "debrief": return .eventDebrief
        default: return nil
        }
    }

    /// Save parsed daily tasks, clearing any existing LLM-generated tasks for today
    private func saveDailyTasks(_ tasks: [DailyTask]) {
        guard !tasks.isEmpty else { return }

        // Clear existing LLM-generated tasks for today
        for existingTask in dailyTaskStore.todaysTasks where existingTask.isLLMGenerated {
            dailyTaskStore.delete(existingTask)
        }

        // Add new tasks
        dailyTaskStore.addMultiple(tasks)

        Logger.info("Coaching: Saved \(tasks.count) daily tasks", category: .ai)
    }

    /// Request the model to offer a contextual follow-up action
    private func requestFollowUpOffer() async {
        guard let convId = conversationId else {
            // No conversation - still generate tasks before completing
            await generateDailyTasksViaToolCall()
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

                        currentQuestionToolCallId = toolCallId
                        currentQuestion = question
                        state = .askingFollowUp(question: question)

                        Logger.debug("Coaching: showing follow-up question", category: .ai)
                        return
                    }
                }
            }

            // No follow-up question offered - generate tasks and complete
            await generateDailyTasksViaToolCall()

        } catch {
            Logger.warning("Failed to get follow-up offer: \(error)", category: .ai)
            // Not critical - still generate tasks before completing
            await generateDailyTasksViaToolCall()
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
              question.questionType == .followUp,
              let convId = conversationId,
              let toolCallId = currentQuestionToolCallId else {
            Logger.warning("No follow-up question to answer or missing context", category: .ai)
            return
        }

        currentQuestion = nil
        currentQuestionToolCallId = nil

        // Send tool result for the follow-up question
        let toolResult = JSON([
            "selected_value": value,
            "selected_label": label
        ])
        llmService.addToolResult(
            conversationId: convId,
            toolCallId: toolCallId,
            result: toolResult.rawString() ?? "{}"
        )

        // Map the answer to an action
        let action = mapFollowUpAnswer(value: value, label: label)

        if action == .done {
            // User chose to end session - still generate tasks first
            await generateDailyTasksViaToolCall()
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
            actionResult = "\n\n---\n**Task List**: Your daily tasks were automatically generated from this coaching session. Check the Today view to see your prioritized task list."

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

        // Force task generation before completing
        await generateDailyTasksViaToolCall()
    }

    /// Force the LLM to generate daily tasks via tool call
    private func generateDailyTasksViaToolCall() async {
        guard let convId = conversationId else {
            await completeSession()
            return
        }

        Logger.info("📋 Requesting daily tasks from coach", category: .ai)

        // Add instruction to generate tasks
        llmService.addUserMessage(
            conversationId: convId,
            message: "Now generate my daily task list based on our coaching conversation. Use the update_daily_tasks tool to create 3-6 specific, actionable tasks."
        )

        do {
            // Force the update_daily_tasks tool
            let message = try await llmService.sendMessageSingleTurn(
                conversationId: convId,
                toolChoice: .function(name: CoachingToolSchemas.updateDailyTasksToolName)
            )

            // Handle the tool call
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                for toolCall in toolCalls {
                    let toolName = toolCall.function.name ?? ""
                    let toolCallId = toolCall.id ?? UUID().uuidString

                    if toolName == CoachingToolSchemas.updateDailyTasksToolName {
                        handleUpdateDailyTasksToolCall(arguments: toolCall.function.arguments)
                        // Send acknowledgment
                        llmService.addToolResult(
                            conversationId: convId,
                            toolCallId: toolCallId,
                            result: "{\"success\": true, \"message\": \"Tasks saved successfully\"}"
                        )
                    }
                }
            }

            Logger.info("✅ Daily tasks generated from coaching session", category: .ai)

        } catch {
            Logger.error("Failed to generate daily tasks: \(error)", category: .ai)
        }

        await completeSession()
    }

    /// Handle the update_daily_tasks tool call and save tasks
    private func handleUpdateDailyTasksToolCall(arguments: String) {
        let json = JSON(parseJSON: arguments)
        let tasksArray = json["tasks"].arrayValue

        var tasks: [DailyTask] = []
        for taskJSON in tasksArray {
            let taskTypeStr = taskJSON["task_type"].stringValue
            guard let taskType = mapTaskType(taskTypeStr) else {
                Logger.warning("Coaching: Unknown task type '\(taskTypeStr)'", category: .ai)
                continue
            }

            let title = taskJSON["title"].stringValue
            guard !title.isEmpty else { continue }

            let task = DailyTask()
            task.taskType = taskType
            task.title = title
            task.taskDescription = taskJSON["description"].string
            task.priority = taskJSON["priority"].intValue
            task.estimatedMinutes = taskJSON["estimated_minutes"].int
            task.isLLMGenerated = true

            // Handle related_id if present
            if let relatedIdStr = taskJSON["related_id"].string,
               let relatedId = UUID(uuidString: relatedIdStr) {
                switch taskType {
                case .gatherLeads:
                    task.relatedJobSourceId = relatedId
                case .customizeMaterials, .submitApplication, .followUp:
                    task.relatedJobAppId = relatedId
                case .networking:
                    task.relatedContactId = relatedId
                case .eventPrep, .eventDebrief:
                    task.relatedEventId = relatedId
                }
            }

            tasks.append(task)
        }

        if !tasks.isEmpty {
            saveDailyTasks(tasks)
            currentSession?.generatedTaskCount = tasks.count
            Logger.info("📋 Saved \(tasks.count) daily tasks from coaching", category: .ai)
        } else {
            Logger.warning("No valid tasks found in update_daily_tasks call", category: .ai)
        }
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
        let activeStatuses: [Statuses] = [.new, .queued, .inProgress, .submitted, .interview, .offer]
        let activeApps = jobAppStore.jobApps.filter { activeStatuses.contains($0.status) }

        guard !activeApps.isEmpty else {
            return "No active job applications."
        }

        var lines: [String] = []
        for app in activeApps.prefix(20) {  // Limit to 20 to avoid overwhelming context
            var line = "- ID: `\(app.id.uuidString)` | **\(app.companyName)** - \(app.jobPosition)"
            line += " | Status: \(app.status.displayName)"
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

    // MARK: - Prompt Loading

    private func loadPromptTemplate(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("🚨 Failed to load prompt template: \(name)")
            return ""
        }
        return content
    }

    // MARK: - Task Regeneration

    /// Regenerate tasks for a specific category based on user feedback
    /// Uses the coaching session's recommendations as context
    func regenerateTasksForCategory(
        _ category: TaskCategory,
        feedback: String
    ) async throws {
        guard let session = todaysSession else {
            throw DiscoveryLLMError.conversationNotFound
        }

        guard let modelId = coachingModelId else {
            throw DiscoveryLLMError.modelNotConfigured
        }

        Logger.info("🔄 Regenerating \(category.displayName) tasks with feedback", category: .ai)

        // Build the prompt with context
        let prompt = buildRegenerationPrompt(
            category: category,
            feedback: feedback,
            coachingRecommendations: session.recommendations,
            activitySummary: session.activitySummary?.textSummary() ?? "No activity data available"
        )

        // Execute structured request
        let response: TaskRegenerationResponse = try await llmService.executeStructured(
            prompt: prompt,
            systemPrompt: """
                You are a job search coach helping regenerate daily tasks based on user feedback.
                Generate practical, actionable tasks that address the user's concerns.
                Only generate tasks for the specified category: \(category.displayName).
                """,
            as: TaskRegenerationResponse.self,
            temperature: 0.7,
            backend: .openRouter,
            modelId: modelId,
            schema: CoachingToolSchemas.buildTaskRegenerationSchema(),
            schemaName: "task_regeneration"
        )

        // Clear existing tasks for this category and add new ones
        replaceTasksForCategory(category, with: response.tasks)

        Logger.info("✅ Regenerated \(response.tasks.count) \(category.displayName) tasks", category: .ai)
    }

    private func buildRegenerationPrompt(
        category: TaskCategory,
        feedback: String,
        coachingRecommendations: String,
        activitySummary: String
    ) -> String {
        """
        # Task Regeneration Request

        ## Category
        \(category.displayName) tasks

        ## User Feedback
        The user wants different suggestions because: \(feedback)

        ## Today's Coaching Context
        \(coachingRecommendations)

        ## Activity Summary
        \(activitySummary)

        ## Task Types to Generate
        Only use these task types for \(category.displayName):
        \(category.taskTypes.map { "- \($0)" }.joined(separator: "\n"))

        ## Instructions
        Generate 2-5 new tasks for the \(category.displayName) category that address the user's feedback.
        Be specific and actionable. Consider the coaching context when making suggestions.
        """
    }

    private func replaceTasksForCategory(_ category: TaskCategory, with taskJSONs: [TaskJSON]) {
        // Delete existing tasks for this category (only LLM-generated ones)
        let today = Calendar.current.startOfDay(for: Date())
        let existingTasks = dailyTaskStore.allTasks.filter { task in
            Calendar.current.isDate(task.createdAt, inSameDayAs: today) &&
            category.dailyTaskTypes.contains(task.taskType) &&
            task.isLLMGenerated
        }

        for task in existingTasks {
            dailyTaskStore.delete(task)
        }

        // Add new tasks
        for taskJSON in taskJSONs {
            guard let taskType = mapTaskType(taskJSON.taskType) else { continue }

            let task = DailyTask(type: taskType, title: taskJSON.title, description: taskJSON.description)
            task.priority = taskJSON.priority
            task.estimatedMinutes = taskJSON.estimatedMinutes
            task.relatedJobAppId = taskJSON.relatedId.flatMap { UUID(uuidString: $0) }
            task.isLLMGenerated = true
            dailyTaskStore.add(task)
        }
    }

    private func buildSystemPrompt(
        activitySummary: String,
        recentHistory: String,
        dossierContext: String,
        knowledgeCardsList: String,
        activeJobApps: String
    ) -> String {
        let preferences = preferencesStore.current()

        var template = loadPromptTemplate(named: "discovery_coaching_system")

        let substitutions: [String: String] = [
            "{{ACTIVITY_SUMMARY}}": activitySummary,
            "{{RECENT_HISTORY}}": recentHistory,
            "{{TARGET_SECTORS}}": preferences.targetSectors.joined(separator: ", "),
            "{{PRIMARY_LOCATION}}": preferences.primaryLocation,
            "{{REMOTE_ACCEPTABLE}}": preferences.remoteAcceptable ? "Yes" : "No",
            "{{WEEKLY_APPLICATION_TARGET}}": String(preferences.weeklyApplicationTarget),
            "{{WEEKLY_NETWORKING_TARGET}}": String(preferences.weeklyNetworkingTarget),
            "{{COMPANY_SIZE_PREFERENCE}}": preferences.companySizePreference.rawValue,
            "{{DOSSIER_CONTEXT}}": dossierContext,
            "{{KNOWLEDGE_CARDS_LIST}}": knowledgeCardsList,
            "{{ACTIVE_JOB_APPS}}": activeJobApps
        ]

        for (placeholder, value) in substitutions {
            template = template.replacingOccurrences(of: placeholder, with: value)
        }

        return template
    }
}
