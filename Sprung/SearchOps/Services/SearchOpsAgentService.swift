//
//  SearchOpsAgentService.swift
//  Sprung
//
//  Actor-based agent service for SearchOps LLM interactions.
//  Uses OpenAI Responses API with web_search for discovery tasks.
//  Per SEARCHOPS_AMENDMENT: Uses local context management, NOT server-managed.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

// MARK: - SearchOps Agent Service

actor SearchOpsAgentService {

    // MARK: - Dependencies

    private let llmFacade: LLMFacade
    private let toolExecutor: SearchOpsToolExecutor
    private let settingsStore: SearchOpsSettingsStore
    private let openAIAPIKey: () -> String

    // MARK: - Configuration

    private let maxIterations = 10

    // MARK: - Initialization

    init(
        llmFacade: LLMFacade,
        contextProvider: SearchOpsContextProvider,
        settingsStore: SearchOpsSettingsStore,
        openAIAPIKey: @escaping () -> String = { APIKeyManager.get(.openAI) ?? "" }
    ) {
        self.llmFacade = llmFacade
        self.toolExecutor = SearchOpsToolExecutor(contextProvider: contextProvider)
        self.settingsStore = settingsStore
        self.openAIAPIKey = openAIAPIKey
    }

    // MARK: - Model Configuration

    private var modelId: String {
        get async {
            await MainActor.run {
                settingsStore.current().llmModelId
            }
        }
    }

    private var reasoningEffort: String {
        get async {
            await MainActor.run {
                settingsStore.current().reasoningEffort
            }
        }
    }

    // MARK: - Prompt Loading

    private func loadPromptTemplate(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(name)", category: .ai)
            return "Error loading prompt template"
        }
        return content
    }

    // MARK: - Public API: Agent Conversations

    /// Run a conversational agent that can use tools to complete a task
    /// - Parameters:
    ///   - systemPrompt: System instructions for the agent
    ///   - userMessage: The user's request
    ///   - enableTools: Whether to enable tool calling (default: true)
    /// - Returns: The agent's final response
    func runAgent(
        systemPrompt: String,
        userMessage: String,
        enableTools: Bool = true
    ) async throws -> String {
        let model = await modelId

        var messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text(systemPrompt)),
            .init(role: .user, content: .text(userMessage))
        ]

        let tools = enableTools ? toolExecutor.getToolSchemas() : []

        // Agent loop
        var iterations = 0
        while iterations < maxIterations {
            iterations += 1

            let response = try await llmFacade.executeWithTools(
                messages: messages,
                tools: tools,
                toolChoice: enableTools ? .auto : nil,
                modelId: model,
                temperature: 0.7
            )

            guard let choices = response.choices,
                  let choice = choices.first,
                  let message = choice.message else {
                throw SearchOpsAgentError.noResponse
            }

            // Check for tool calls
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                // Add assistant message with tool calls to history
                let assistantContent: ChatCompletionParameters.Message.ContentType
                if let text = message.content {
                    assistantContent = .text(text)
                } else {
                    assistantContent = .text("")
                }
                messages.append(ChatCompletionParameters.Message(
                    role: .assistant,
                    content: assistantContent,
                    toolCalls: message.toolCalls
                ))

                // Execute each tool call
                for toolCall in toolCalls {
                    let toolCallId = toolCall.id ?? UUID().uuidString
                    let toolName = toolCall.function.name ?? "unknown"
                    let arguments = toolCall.function.arguments

                    Logger.debug("🔧 Executing tool: \(toolName)", category: .ai)

                    let result = await toolExecutor.execute(
                        toolName: toolName,
                        arguments: arguments
                    )

                    // Add tool result to messages
                    messages.append(ChatCompletionParameters.Message(
                        role: .tool,
                        content: .text(result),
                        toolCallID: toolCallId
                    ))
                }

                // Continue loop to get next response
                continue
            }

            // No tool calls - final response
            let responseText = message.content ?? ""
            Logger.info("✅ Agent completed with response", category: .ai)
            return responseText
        }

        throw SearchOpsAgentError.toolLoopExceeded
    }

    // MARK: - Convenience Methods for Common Tasks

    /// Generate daily tasks using the agent
    func generateDailyTasks(focusArea: String = "balanced") async throws -> DailyTasksResult {
        let systemPrompt = loadPromptTemplate(named: "searchops_generate_daily_tasks")

        let userMessage = "Generate today's job search tasks. Focus area: \(focusArea)"

        let response = try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )

        return try parseTasksResponse(response)
    }

    /// Discover job sources using Responses API with web search
    func discoverJobSources(
        sectors: [String],
        location: String,
        statusCallback: (@MainActor @Sendable (DiscoveryStatus) async -> Void)? = nil
    ) async throws -> JobSourcesResult {
        let systemPrompt = loadPromptTemplate(named: "searchops_discover_job_sources")
        let userMessage = "Discover job sources for sectors: \(sectors.joined(separator: ", ")) in \(location)"
        let model = await modelId
        let reasoning = await reasoningEffort

        let response = try await runWithWebSearch(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: model,
            reasoningEffort: reasoning,
            userLocation: location,
            statusCallback: statusCallback
        )

        return try parseSourcesResponse(response)
    }

    // MARK: - Responses API with Web Search

    /// Run a request using OpenAI Responses API with web_search tool enabled (streaming to avoid timeout)
    private func runWithWebSearch(
        systemPrompt: String,
        userMessage: String,
        modelId: String,
        reasoningEffort: String = "low",
        userLocation: String? = nil,
        statusCallback: (@MainActor @Sendable (DiscoveryStatus) async -> Void)? = nil,
        reasoningCallback: (@MainActor @Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        let apiKey = openAIAPIKey()
        guard !apiKey.isEmpty else {
            throw SearchOpsAgentError.missingAPIKey
        }

        // Strip OpenRouter prefix if present (e.g., "openai/gpt-5.2" -> "gpt-5.2")
        let openAIModelId = modelId.hasPrefix("openai/") ? String(modelId.dropFirst(7)) : modelId

        let service = OpenAIServiceFactory.service(apiKey: apiKey)

        // Build input with system prompt as developer message + user message
        let developerMessage = InputMessage(role: "developer", content: .text(systemPrompt))
        let userInputMessage = InputMessage(role: "user", content: .text(userMessage))
        let inputItems: [InputItem] = [
            .message(developerMessage),
            .message(userInputMessage)
        ]

        // Configure web search tool with optional user location
        let webSearchUserLocation: Tool.UserLocation? = userLocation.map { loc in
            Tool.UserLocation(city: loc, country: "US")
        }
        let webSearchTool = Tool.webSearch(Tool.WebSearchTool(
            type: .webSearch,
            userLocation: webSearchUserLocation
        ))

        // Configure reasoning effort (low, medium, high, minimal)
        let reasoning = Reasoning(effort: reasoningEffort)

        let parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(openAIModelId),
            reasoning: reasoning,
            store: false,
            stream: true,
            toolChoice: .auto,
            tools: [webSearchTool]
        )

        Logger.info("🔍 Running Responses API stream with web_search (model: \(openAIModelId), reasoning: \(reasoningEffort))", category: .ai)

        // Use streaming to avoid timeout during web search
        var finalResponse: ResponseModel?
        let stream = try await service.responseCreateStream(parameters)

        for try await event in stream {
            switch event {
            case .responseCompleted(let completed):
                finalResponse = completed.response
                Logger.debug("📡 Stream completed", category: .ai)
            case .webSearchCallSearching:
                Logger.debug("🌐 Web search searching...", category: .ai)
                await statusCallback?(.webSearching)
            case .webSearchCallCompleted:
                Logger.debug("🌐 Web search completed", category: .ai)
                await statusCallback?(.webSearchComplete)
            case .outputTextDelta(let delta):
                Logger.verbose("📝 Text delta: \(delta.delta.count) chars", category: .ai)
                await reasoningCallback?(delta.delta)
            case .reasoningSummaryTextDelta(let delta):
                Logger.verbose("🧠 Reasoning delta: \(delta.delta.count) chars", category: .ai)
                await reasoningCallback?(delta.delta)
            default:
                break
            }
        }

        guard let response = finalResponse,
              let outputText = extractResponseText(from: response) else {
            throw SearchOpsAgentError.noResponse
        }

        Logger.info("✅ Responses API returned \(outputText.count) chars", category: .ai)
        return outputText
    }

    /// Extract text from ResponseModel output
    private func extractResponseText(from response: ResponseModel) -> String? {
        // Try outputText convenience property first
        if let text = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        // Fall back to iterating through output items
        for item in response.output {
            if case let .message(message) = item {
                for content in message.content {
                    if case let .outputText(output) = content,
                       !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return output.text
                    }
                }
            }
        }
        return nil
    }

    /// Discover networking events using Responses API with web search
    func discoverNetworkingEvents(
        sectors: [String],
        location: String,
        daysAhead: Int = 14,
        statusCallback: (@MainActor @Sendable (DiscoveryStatus) async -> Void)? = nil,
        reasoningCallback: (@MainActor @Sendable (String) async -> Void)? = nil
    ) async throws -> NetworkingEventsResult {
        let systemPrompt = loadPromptTemplate(named: "searchops_discover_networking_events")
        let userMessage = "Find networking events for sectors: \(sectors.joined(separator: ", ")) in \(location) for the next \(daysAhead) days"
        let model = await modelId
        let reasoning = await reasoningEffort

        let response = try await runWithWebSearch(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: model,
            reasoningEffort: reasoning,
            userLocation: location,
            statusCallback: statusCallback,
            reasoningCallback: reasoningCallback
        )

        return try parseEventsResponse(response)
    }

    /// Evaluate an event for attendance
    func evaluateEvent(eventId: UUID) async throws -> EventEvaluationResult {
        let systemPrompt = loadPromptTemplate(named: "searchops_evaluate_event")

        let userMessage = "Evaluate event \(eventId.uuidString) for attendance"

        let response = try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )

        return try parseEvaluationResponse(response)
    }

    /// Prepare for an upcoming event
    func prepareForEvent(eventId: UUID, focusCompanies: [String] = [], goals: String? = nil) async throws -> EventPrepResult {
        let systemPrompt = loadPromptTemplate(named: "searchops_prepare_for_event")

        var userMessage = "Prepare me for event \(eventId.uuidString)"
        if !focusCompanies.isEmpty {
            userMessage += ". Focus on companies: \(focusCompanies.joined(separator: ", "))"
        }
        if let goals = goals {
            userMessage += ". My goals: \(goals)"
        }

        let response = try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )

        return try parsePrepResponse(response)
    }

    /// Generate debrief outcomes and suggested next steps
    func generateDebriefOutcomes(
        eventName: String,
        eventType: String,
        keyInsights: String,
        contactsMade: [String],
        notes: String
    ) async throws -> DebriefOutcomesResult {
        let systemPrompt = """
        You are a career networking coach analyzing a post-event debrief. Based on the information provided about the networking event, generate actionable outcomes and next steps.

        Return your response as JSON with this structure:
        {
            "summary": "Brief 1-2 sentence summary of the event outcomes",
            "key_takeaways": ["Insight 1", "Insight 2", "Insight 3"],
            "follow_up_actions": [
                {
                    "contact_name": "Person's name",
                    "action": "What to do",
                    "deadline": "within 24 hours / within 1 week / within 2 weeks",
                    "priority": "high / medium / low"
                }
            ],
            "opportunities_identified": ["Potential opportunity 1", "Potential opportunity 2"],
            "next_steps": ["Concrete next step 1", "Concrete next step 2", "Concrete next step 3"]
        }

        Guidelines:
        - Follow-up actions should be specific and actionable
        - Prioritize warm leads and time-sensitive opportunities
        - Suggest LinkedIn connection requests within 24-48 hours of meeting
        - Identify any job leads, referral opportunities, or informational interview possibilities
        - Be concrete and specific in next steps
        """

        var contextParts: [String] = []
        contextParts.append("Event: \(eventName) (\(eventType))")

        if !contactsMade.isEmpty {
            contextParts.append("Contacts made: \(contactsMade.joined(separator: ", "))")
        }

        if !keyInsights.isEmpty {
            contextParts.append("Key insights: \(keyInsights)")
        }

        if !notes.isEmpty {
            contextParts.append("Additional notes: \(notes)")
        }

        let userMessage = contextParts.joined(separator: "\n\n")

        let response = try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            enableTools: false
        )

        return try parseDebriefOutcomesResponse(response)
    }

    /// Generate weekly reflection
    func generateWeeklyReflection() async throws -> String {
        let systemPrompt = loadPromptTemplate(named: "searchops_generate_weekly_reflection")

        let userMessage = "Generate my weekly job search reflection"

        return try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )
    }

    /// Suggest networking actions
    func suggestNetworkingActions(focus: String = "balanced") async throws -> NetworkingActionsResult {
        let systemPrompt = loadPromptTemplate(named: "searchops_suggest_networking_actions")

        let userMessage = "Suggest networking actions. Focus: \(focus)"

        let response = try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )

        return try parseActionsResponse(response)
    }

    /// Draft an outreach message
    func draftOutreachMessage(contactId: UUID, purpose: String, channel: String, tone: String = "professional") async throws -> OutreachMessageResult {
        let systemPrompt = loadPromptTemplate(named: "searchops_draft_outreach_message")

        let userMessage = "Draft a \(channel) message to contact \(contactId.uuidString). Purpose: \(purpose). Tone: \(tone)"

        let response = try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )

        return try parseOutreachResponse(response)
    }

    /// Choose best jobs from identified pool based on user's knowledge and dossier
    /// - Parameters:
    ///   - jobs: Array of job descriptions with IDs
    ///   - knowledgeContext: User's knowledge cards (skills, experience)
    ///   - dossierContext: User's dossier (job search context, preferences)
    ///   - count: Number of jobs to select (default 5)
    /// - Returns: Selection result with reasoning
    // TODO: Context source choice - may revisit (currently using knowledge cards + dossier)
    func chooseBestJobs(
        jobs: [(id: UUID, company: String, role: String, description: String)],
        knowledgeContext: String,
        dossierContext: String,
        count: Int = 5
    ) async throws -> JobSelectionsResult {
        let systemPrompt = loadPromptTemplate(named: "searchops_choose_best_jobs")
        let model = await modelId
        let reasoning = await reasoningEffort

        // Build user message with all context
        var userMessage = "Please select the top \(count) jobs from the following opportunities.\n\n"

        userMessage += "## CANDIDATE KNOWLEDGE CARDS\n\(knowledgeContext)\n\n"
        userMessage += "## CANDIDATE DOSSIER\n\(dossierContext)\n\n"
        userMessage += "## JOB OPPORTUNITIES\n"

        for job in jobs {
            userMessage += """
            ---
            ID: \(job.id.uuidString)
            Company: \(job.company)
            Role: \(job.role)
            Description: \(job.description)

            """
        }

        let response = try await runDirectOpenAI(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: model,
            reasoningEffort: reasoning
        )

        return try parseJobSelectionsResponse(response)
    }

    // MARK: - Direct OpenAI API (no web search)

    /// Run a request using OpenAI Responses API without tools (for analysis tasks)
    private func runDirectOpenAI(
        systemPrompt: String,
        userMessage: String,
        modelId: String,
        reasoningEffort: String = "low"
    ) async throws -> String {
        let apiKey = openAIAPIKey()
        guard !apiKey.isEmpty else {
            throw SearchOpsAgentError.missingAPIKey
        }

        // Strip OpenRouter prefix if present (e.g., "openai/gpt-5.2" -> "gpt-5.2")
        let openAIModelId = modelId.hasPrefix("openai/") ? String(modelId.dropFirst(7)) : modelId

        let service = OpenAIServiceFactory.service(apiKey: apiKey)

        // Build input with system prompt as developer message + user message
        let developerMessage = InputMessage(role: "developer", content: .text(systemPrompt))
        let userInputMessage = InputMessage(role: "user", content: .text(userMessage))
        let inputItems: [InputItem] = [
            .message(developerMessage),
            .message(userInputMessage)
        ]

        // Configure reasoning effort
        let reasoning = Reasoning(effort: reasoningEffort)

        let parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(openAIModelId),
            reasoning: reasoning,
            store: false,
            stream: true
        )

        Logger.info("🎯 Running direct OpenAI request (model: \(openAIModelId), reasoning: \(reasoningEffort))", category: .ai)

        var finalResponse: ResponseModel?
        let stream = try await service.responseCreateStream(parameters)

        for try await event in stream {
            switch event {
            case .responseCompleted(let completed):
                finalResponse = completed.response
                Logger.debug("📡 Stream completed", category: .ai)
            default:
                break
            }
        }

        guard let response = finalResponse,
              let outputText = extractResponseText(from: response) else {
            throw SearchOpsAgentError.noResponse
        }

        Logger.info("✅ Direct OpenAI returned \(outputText.count) chars", category: .ai)
        return outputText
    }

    // MARK: - Response Parsing

    private func parseTasksResponse(_ response: String) throws -> DailyTasksResult {
        guard let jsonData = extractJSON(from: response),
              let data = jsonData.data(using: .utf8) else {
            throw SearchOpsAgentError.invalidResponse
        }

        let json = try JSON(data: data)
        var tasks: [GeneratedDailyTask] = []

        for taskJson in json["tasks"].arrayValue {
            let task = GeneratedDailyTask(
                taskType: taskJson["task_type"].stringValue,
                title: taskJson["title"].stringValue,
                description: taskJson["description"].string,
                priority: taskJson["priority"].intValue,
                relatedJobSourceId: taskJson["related_id"].string,
                relatedJobAppId: nil,
                relatedContactId: nil,
                relatedEventId: nil,
                estimatedMinutes: taskJson["estimated_minutes"].int
            )
            tasks.append(task)
        }

        return DailyTasksResult(tasks: tasks, summary: json["summary"].string)
    }

    private func parseSourcesResponse(_ response: String) throws -> JobSourcesResult {
        guard let jsonData = extractJSON(from: response),
              let data = jsonData.data(using: .utf8) else {
            throw SearchOpsAgentError.invalidResponse
        }

        let json = try JSON(data: data)
        var sources: [GeneratedJobSource] = []

        for sourceJson in json["sources"].arrayValue {
            let source = GeneratedJobSource(
                name: sourceJson["name"].stringValue,
                url: sourceJson["url"].stringValue,
                category: sourceJson["category"].stringValue,
                relevanceReason: sourceJson["relevance_reason"].stringValue,
                recommendedCadenceDays: sourceJson["recommended_cadence_days"].int
            )
            sources.append(source)
        }

        return JobSourcesResult(sources: sources)
    }

    private func parseEventsResponse(_ response: String) throws -> NetworkingEventsResult {
        guard let jsonData = extractJSON(from: response),
              let data = jsonData.data(using: .utf8) else {
            throw SearchOpsAgentError.invalidResponse
        }

        let json = try JSON(data: data)
        var events: [GeneratedNetworkingEvent] = []

        for eventJson in json["events"].arrayValue {
            let event = GeneratedNetworkingEvent(
                name: eventJson["name"].stringValue,
                date: eventJson["date"].stringValue,
                time: eventJson["time"].string,
                location: eventJson["location"].stringValue,
                url: eventJson["url"].stringValue,
                eventType: eventJson["event_type"].stringValue,
                organizer: eventJson["organizer"].string,
                estimatedAttendance: eventJson["estimated_attendance"].string,
                cost: eventJson["cost"].string,
                relevanceReason: eventJson["relevance_reason"].string
            )
            events.append(event)
        }

        return NetworkingEventsResult(events: events)
    }

    private func parseEvaluationResponse(_ response: String) throws -> EventEvaluationResult {
        guard let jsonData = extractJSON(from: response),
              let data = jsonData.data(using: .utf8) else {
            throw SearchOpsAgentError.invalidResponse
        }

        let json = try JSON(data: data)

        return EventEvaluationResult(
            recommendation: json["recommendation"].stringValue,
            rationale: json["rationale"].stringValue,
            expectedValue: json["expected_value"].string,
            concerns: json["concerns"].arrayValue.map { $0.stringValue },
            preparationTips: json["preparation_tips"].arrayValue.map { $0.stringValue }
        )
    }

    private func parsePrepResponse(_ response: String) throws -> EventPrepResult {
        guard let jsonData = extractJSON(from: response),
              let data = jsonData.data(using: .utf8) else {
            throw SearchOpsAgentError.invalidResponse
        }

        let json = try JSON(data: data)

        return EventPrepResult(
            goal: json["goal"].stringValue,
            pitchScript: json["pitch_script"].stringValue,
            talkingPoints: json["talking_points"].arrayValue.map {
                TalkingPointResult(
                    topic: $0["topic"].stringValue,
                    relevance: $0["relevance"].stringValue,
                    yourAngle: $0["your_angle"].stringValue
                )
            },
            targetCompanies: json["target_companies"].arrayValue.map {
                TargetCompanyResult(
                    company: $0["company"].stringValue,
                    whyRelevant: $0["why_relevant"].stringValue,
                    recentNews: $0["recent_news"].string,
                    openRoles: $0["open_roles"].arrayValue.map { $0.stringValue },
                    possibleOpeners: $0["possible_openers"].arrayValue.map { $0.stringValue }
                )
            },
            conversationStarters: json["conversation_starters"].arrayValue.map { $0.stringValue },
            thingsToAvoid: json["things_to_avoid"].arrayValue.map { $0.stringValue }
        )
    }

    private func parseDebriefOutcomesResponse(_ response: String) throws -> DebriefOutcomesResult {
        guard let jsonData = extractJSON(from: response),
              let data = jsonData.data(using: .utf8) else {
            throw SearchOpsAgentError.invalidResponse
        }

        let json = try JSON(data: data)

        return DebriefOutcomesResult(
            summary: json["summary"].stringValue,
            keyTakeaways: json["key_takeaways"].arrayValue.map { $0.stringValue },
            followUpActions: json["follow_up_actions"].arrayValue.map {
                DebriefFollowUpAction(
                    contactName: $0["contact_name"].stringValue,
                    action: $0["action"].stringValue,
                    deadline: $0["deadline"].stringValue,
                    priority: $0["priority"].stringValue
                )
            },
            opportunitiesIdentified: json["opportunities_identified"].arrayValue.map { $0.stringValue },
            nextSteps: json["next_steps"].arrayValue.map { $0.stringValue }
        )
    }

    private func parseActionsResponse(_ response: String) throws -> NetworkingActionsResult {
        guard let jsonData = extractJSON(from: response),
              let data = jsonData.data(using: .utf8) else {
            throw SearchOpsAgentError.invalidResponse
        }

        let json = try JSON(data: data)

        return NetworkingActionsResult(
            actions: json["actions"].arrayValue.map {
                NetworkingActionItem(
                    contactName: $0["contact_name"].stringValue,
                    contactId: $0["contact_id"].string,
                    actionType: $0["action_type"].stringValue,
                    actionDescription: $0["action_description"].stringValue,
                    urgency: $0["urgency"].stringValue,
                    suggestedOpener: $0["suggested_opener"].string
                )
            }
        )
    }

    private func parseOutreachResponse(_ response: String) throws -> OutreachMessageResult {
        guard let jsonData = extractJSON(from: response),
              let data = jsonData.data(using: .utf8) else {
            throw SearchOpsAgentError.invalidResponse
        }

        let json = try JSON(data: data)

        return OutreachMessageResult(
            subject: json["subject"].string,
            message: json["message"].stringValue,
            notes: json["notes"].string
        )
    }

    private func parseJobSelectionsResponse(_ response: String) throws -> JobSelectionsResult {
        guard let jsonData = extractJSON(from: response),
              let data = jsonData.data(using: .utf8) else {
            throw SearchOpsAgentError.invalidResponse
        }

        let json = try JSON(data: data)
        var selections: [JobSelection] = []

        for selectionJson in json["selections"].arrayValue {
            guard let jobId = UUID(uuidString: selectionJson["job_id"].stringValue) else {
                continue
            }
            let selection = JobSelection(
                jobId: jobId,
                company: selectionJson["company"].stringValue,
                role: selectionJson["role"].stringValue,
                matchScore: selectionJson["match_score"].doubleValue,
                reasoning: selectionJson["reasoning"].stringValue
            )
            selections.append(selection)
        }

        return JobSelectionsResult(
            selections: selections,
            overallAnalysis: json["overall_analysis"].stringValue,
            considerations: json["considerations"].arrayValue.map { $0.stringValue }
        )
    }

    /// Extract JSON from response that may contain markdown code blocks
    private func extractJSON(from response: String) -> String? {
        // Try to find JSON in code blocks first
        if let jsonMatch = response.range(of: "```json\\s*(.+?)```", options: .regularExpression) {
            var extracted = String(response[jsonMatch])
            extracted = extracted.replacingOccurrences(of: "```json", with: "")
            extracted = extracted.replacingOccurrences(of: "```", with: "")
            return extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find raw JSON (starts with { or [)
        if let jsonStart = response.firstIndex(of: "{"),
           let jsonEnd = response.lastIndex(of: "}") {
            return String(response[jsonStart...jsonEnd])
        }

        if let jsonStart = response.firstIndex(of: "["),
           let jsonEnd = response.lastIndex(of: "]") {
            return String(response[jsonStart...jsonEnd])
        }

        return nil
    }
}

// MARK: - Result Types

struct DailyTasksResult {
    let tasks: [GeneratedDailyTask]
    let summary: String?
}

struct JobSourcesResult {
    let sources: [GeneratedJobSource]
}

struct NetworkingEventsResult {
    let events: [GeneratedNetworkingEvent]
}

struct JobSelectionsResult {
    let selections: [JobSelection]
    let overallAnalysis: String
    let considerations: [String]
}

struct JobSelection {
    let jobId: UUID
    let company: String
    let role: String
    let matchScore: Double
    let reasoning: String
}

// MARK: - Generated Types (from LLM responses)

struct GeneratedDailyTask: Codable {
    let taskType: String
    let title: String
    let description: String?
    let priority: Int
    let relatedJobSourceId: String?
    let relatedJobAppId: String?
    let relatedContactId: String?
    let relatedEventId: String?
    let estimatedMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case taskType = "task_type"
        case title
        case description
        case priority
        case relatedJobSourceId = "related_job_source_id"
        case relatedJobAppId = "related_job_app_id"
        case relatedContactId = "related_contact_id"
        case relatedEventId = "related_event_id"
        case estimatedMinutes = "estimated_minutes"
    }

    func toDailyTask() -> DailyTask {
        let task = DailyTask()
        task.title = title
        task.taskDescription = description
        task.priority = priority
        task.estimatedMinutes = estimatedMinutes
        task.isLLMGenerated = true

        switch taskType.lowercased() {
        case "gather": task.taskType = .gatherLeads
        case "customize": task.taskType = .customizeMaterials
        case "apply": task.taskType = .submitApplication
        case "follow_up": task.taskType = .followUp
        case "networking": task.taskType = .networking
        case "event_prep": task.taskType = .eventPrep
        case "debrief": task.taskType = .eventDebrief
        default: task.taskType = .gatherLeads
        }

        if let sourceId = relatedJobSourceId, let uuid = UUID(uuidString: sourceId) {
            task.relatedJobSourceId = uuid
        }
        if let jobAppId = relatedJobAppId, let uuid = UUID(uuidString: jobAppId) {
            task.relatedJobAppId = uuid
        }
        if let contactId = relatedContactId, let uuid = UUID(uuidString: contactId) {
            task.relatedContactId = uuid
        }
        if let eventId = relatedEventId, let uuid = UUID(uuidString: eventId) {
            task.relatedEventId = uuid
        }

        return task
    }
}

struct GeneratedJobSource: Codable {
    let name: String
    let url: String
    let category: String
    let relevanceReason: String
    let recommendedCadenceDays: Int?

    enum CodingKeys: String, CodingKey {
        case name, url, category
        case relevanceReason = "relevance_reason"
        case recommendedCadenceDays = "recommended_cadence_days"
    }

    func toJobSource() -> JobSource {
        let source = JobSource()
        source.name = name
        source.url = url
        source.notes = relevanceReason
        source.isLLMGenerated = true

        switch category.lowercased() {
        case "local": source.category = .local
        case "industry": source.category = .industry
        case "company_direct": source.category = .companyDirect
        case "aggregator": source.category = .aggregator
        case "startup": source.category = .startup
        case "staffing": source.category = .staffing
        case "networking": source.category = .networking
        default: source.category = .aggregator
        }

        if let days = recommendedCadenceDays {
            source.recommendedCadenceDays = days
        } else {
            source.recommendedCadenceDays = source.category.defaultCadenceDays
        }

        return source
    }
}

struct GeneratedNetworkingEvent {
    let name: String
    let date: String
    let time: String?
    let location: String
    let url: String
    let eventType: String
    let organizer: String?
    let estimatedAttendance: String?
    let cost: String?
    let relevanceReason: String?

    func toNetworkingEventOpportunity() -> NetworkingEventOpportunity {
        let event = NetworkingEventOpportunity()
        event.name = name
        event.date = parseEventDate(date) ?? Date()
        event.time = time
        event.location = location
        event.url = url
        event.eventType = parseEventType(eventType)
        event.organizer = organizer
        event.estimatedAttendance = parseAttendanceSize(estimatedAttendance)
        event.cost = cost
        event.relevanceReason = relevanceReason
        event.discoveredVia = .webSearch
        return event
    }

    private func parseEventDate(_ dateString: String) -> Date? {
        // Try ISO8601 with time first
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }

        // Try date-only format (YYYY-MM-DD)
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.timeZone = TimeZone.current
        if let date = dateOnlyFormatter.date(from: dateString) {
            return date
        }

        // Try common US format (MM/DD/YYYY)
        dateOnlyFormatter.dateFormat = "MM/dd/yyyy"
        if let date = dateOnlyFormatter.date(from: dateString) {
            return date
        }

        // Try natural language formats (e.g., "January 6, 2026")
        dateOnlyFormatter.dateFormat = "MMMM d, yyyy"
        if let date = dateOnlyFormatter.date(from: dateString) {
            return date
        }

        Logger.warning("⚠️ Could not parse event date: \(dateString)", category: .ai)
        return nil
    }

    private func parseEventType(_ type: String) -> NetworkingEventType {
        NetworkingEventType(rawValue: type.replacingOccurrences(of: "_", with: " ").capitalized) ?? .meetup
    }

    private func parseAttendanceSize(_ size: String?) -> AttendanceSize {
        guard let size = size else { return .medium }
        switch size.lowercased() {
        case "intimate": return .intimate
        case "small": return .small
        case "medium": return .medium
        case "large": return .large
        case "massive": return .massive
        default: return .medium
        }
    }
}

struct EventEvaluationResult {
    let recommendation: String
    let rationale: String
    let expectedValue: String?
    let concerns: [String]
    let preparationTips: [String]

    var attendanceRecommendation: AttendanceRecommendation {
        switch recommendation.lowercased() {
        case "strong_yes": return .strongYes
        case "yes": return .yes
        case "maybe": return .maybe
        case "skip": return .skip
        default: return .maybe
        }
    }
}

struct EventPrepResult {
    let goal: String
    let pitchScript: String
    let talkingPoints: [TalkingPointResult]
    let targetCompanies: [TargetCompanyResult]
    let conversationStarters: [String]
    let thingsToAvoid: [String]
}

struct DebriefOutcomesResult {
    let summary: String
    let keyTakeaways: [String]
    let followUpActions: [DebriefFollowUpAction]
    let opportunitiesIdentified: [String]
    let nextSteps: [String]
}

struct DebriefFollowUpAction {
    let contactName: String
    let action: String
    let deadline: String
    let priority: String
}

struct TalkingPointResult {
    let topic: String
    let relevance: String
    let yourAngle: String

    func toTalkingPoint() -> TalkingPoint {
        TalkingPoint(topic: topic, relevance: relevance, yourAngle: yourAngle)
    }
}

struct TargetCompanyResult {
    let company: String
    let whyRelevant: String
    let recentNews: String?
    let openRoles: [String]
    let possibleOpeners: [String]

    func toTargetCompanyContext() -> TargetCompanyContext {
        TargetCompanyContext(
            company: company,
            whyRelevant: whyRelevant,
            recentNews: recentNews,
            openRoles: openRoles,
            possibleOpeners: possibleOpeners
        )
    }
}

struct NetworkingActionsResult {
    let actions: [NetworkingActionItem]
}

struct NetworkingActionItem {
    let contactName: String
    let contactId: String?
    let actionType: String
    let actionDescription: String
    let urgency: String
    let suggestedOpener: String?
}

struct OutreachMessageResult {
    let subject: String?
    let message: String
    let notes: String?
}

// MARK: - Errors

enum SearchOpsAgentError: Error, LocalizedError {
    case noResponse
    case toolLoopExceeded
    case invalidResponse
    case toolExecutionFailed(String)
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .noResponse:
            return "No response from LLM"
        case .missingAPIKey:
            return "OpenAI API key is required for job source discovery"
        case .toolLoopExceeded:
            return "Tool call loop exceeded maximum iterations"
        case .invalidResponse:
            return "Could not parse LLM response"
        case .toolExecutionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}
