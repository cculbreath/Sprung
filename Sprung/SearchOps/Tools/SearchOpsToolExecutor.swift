//
//  SearchOpsToolExecutor.swift
//  Sprung
//
//  Actor-based tool executor for SearchOps module.
//  Provides tool schemas and execution for LLM agent interactions.
//  Uses ChatCompletionParameters.Tool pattern per SEARCHOPS_AMENDMENT.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

// MARK: - SearchOps Tool Executor

actor SearchOpsToolExecutor {

    // MARK: - Dependencies

    private let contextProvider: SearchOpsContextProvider

    // MARK: - Tool Cache (nonisolated since schemas are static)

    nonisolated private static let toolSchemas: [ChatCompletionParameters.Tool] = buildAllToolsStatic()

    // MARK: - Initialization

    init(contextProvider: SearchOpsContextProvider) {
        self.contextProvider = contextProvider
    }

    // MARK: - Public API

    /// Get all tool schemas for LLM (nonisolated - schemas are static data)
    nonisolated func getToolSchemas() -> [ChatCompletionParameters.Tool] {
        return Self.toolSchemas
    }

    /// Execute a tool by name with JSON arguments
    /// - Returns: JSON string result
    func execute(toolName: String, arguments: String) async -> String {
        let argsJSON: JSON
        if let data = arguments.data(using: .utf8) {
            argsJSON = (try? JSON(data: data)) ?? JSON()
        } else {
            argsJSON = JSON()
        }

        do {
            switch toolName {
            case "generate_daily_tasks":
                return try await executeGenerateDailyTasks(args: argsJSON)
            case "discover_job_sources":
                return try await executeDiscoverJobSources(args: argsJSON)
            case "discover_networking_events":
                return try await executeDiscoverEvents(args: argsJSON)
            case "evaluate_networking_event":
                return try await executeEvaluateEvent(args: argsJSON)
            case "prepare_for_event":
                return try await executePrepareForEvent(args: argsJSON)
            case "debrief_event":
                return try await executeDebriefEvent(args: argsJSON)
            case "suggest_networking_actions":
                return try await executeSuggestNetworkingActions(args: argsJSON)
            case "draft_outreach_message":
                return try await executeDraftOutreachMessage(args: argsJSON)
            case "recommend_weekly_goals":
                return try await executeRecommendWeeklyGoals(args: argsJSON)
            case "generate_weekly_reflection":
                return try await executeGenerateWeeklyReflection(args: argsJSON)
            default:
                return errorResult("Unknown tool: \(toolName)")
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    // MARK: - Build All Tools (Static)

    nonisolated private static func buildAllToolsStatic() -> [ChatCompletionParameters.Tool] {
        [
            buildGenerateDailyTasksToolStatic(),
            buildDiscoverJobSourcesToolStatic(),
            buildDiscoverEventsToolStatic(),
            buildEvaluateEventToolStatic(),
            buildPrepareForEventToolStatic(),
            buildDebriefEventToolStatic(),
            buildSuggestNetworkingActionsToolStatic(),
            buildDraftOutreachMessageToolStatic(),
            buildRecommendWeeklyGoalsToolStatic(),
            buildGenerateWeeklyReflectionToolStatic()
        ]
    }

    // MARK: - Tool Builders (Static)

    nonisolated private static func buildGenerateDailyTasksToolStatic() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Generate prioritized daily tasks for job search based on current state.
                Considers due sources, upcoming events, contacts needing attention, and weekly goals.
                Returns 5-8 actionable tasks with priorities and time estimates.
                """,
            properties: [
                "focus_area": JSONSchema(
                    type: .string,
                    description: "Optional focus area: applications, networking, follow_ups, or balanced",
                    enum: ["applications", "networking", "follow_ups", "balanced"]
                ),
                "max_tasks": JSONSchema(
                    type: .integer,
                    description: "Maximum number of tasks to generate (default: 8)"
                )
            ],
            required: [],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "generate_daily_tasks",
                strict: false,
                description: "Generate prioritized daily job search tasks",
                parameters: schema
            )
        )
    }

    nonisolated private static func buildDiscoverJobSourcesToolStatic() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Discover new job sources tailored to candidate's target sectors and location.
                Searches for job boards, company career pages, and industry-specific resources.
                Returns sources with URLs, categories, and relevance explanations.
                """,
            properties: [
                "sectors": JSONSchema(
                    type: .array,
                    description: "Target sectors to search for (e.g., robotics, aerospace)",
                    items: JSONSchema(type: .string)
                ),
                "location": JSONSchema(
                    type: .string,
                    description: "Primary location (e.g., Austin, TX)"
                ),
                "include_remote": JSONSchema(
                    type: .boolean,
                    description: "Include remote-friendly sources (default: true)"
                ),
                "count": JSONSchema(
                    type: .integer,
                    description: "Number of sources to discover (default: 10)"
                )
            ],
            required: ["sectors", "location"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "discover_job_sources",
                strict: false,
                description: "Discover job boards and sources matching target sectors",
                parameters: schema
            )
        )
    }

    nonisolated private static func buildDiscoverEventsToolStatic() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Search for upcoming networking events, meetups, conferences, and professional gatherings.
                Considers candidate's target sectors and location preferences.
                Returns events with dates, locations, URLs, and relevance scores.
                """,
            properties: [
                "sectors": JSONSchema(
                    type: .array,
                    description: "Target sectors (e.g., robotics, aerospace)",
                    items: JSONSchema(type: .string)
                ),
                "location": JSONSchema(
                    type: .string,
                    description: "Primary location (e.g., Austin, TX)"
                ),
                "days_ahead": JSONSchema(
                    type: .integer,
                    description: "Days to look ahead (default: 14)"
                ),
                "include_virtual": JSONSchema(
                    type: .boolean,
                    description: "Include virtual events (default: true)"
                )
            ],
            required: ["sectors", "location"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "discover_networking_events",
                strict: false,
                description: "Search for upcoming networking events matching target sectors",
                parameters: schema
            )
        )
    }

    nonisolated private static func buildEvaluateEventToolStatic() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Evaluate a networking event for attendance value.
                Considers event type, expected attendees, relevance to target companies,
                time investment, and historical data from similar events.
                Returns recommendation (strong_yes/yes/maybe/skip) with rationale.
                """,
            properties: [
                "event_id": JSONSchema(
                    type: .string,
                    description: "UUID of the event to evaluate"
                ),
                "event_details": JSONSchema(
                    type: .object,
                    description: "Event details if not stored (name, date, location, type, organizer)"
                )
            ],
            required: ["event_id"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "evaluate_networking_event",
                strict: false,
                description: "Evaluate whether to attend a networking event",
                parameters: schema
            )
        )
    }

    nonisolated private static func buildPrepareForEventToolStatic() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Generate preparation materials for an upcoming networking event.
                Creates: elevator pitch, talking points, target company context,
                conversation starters, and things to avoid.
                """,
            properties: [
                "event_id": JSONSchema(
                    type: .string,
                    description: "UUID of the event to prepare for"
                ),
                "focus_companies": JSONSchema(
                    type: .array,
                    description: "Specific companies to research for this event",
                    items: JSONSchema(type: .string)
                ),
                "personal_goals": JSONSchema(
                    type: .string,
                    description: "Personal goals for this event (e.g., make 3 contacts)"
                )
            ],
            required: ["event_id"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "prepare_for_event",
                strict: false,
                description: "Generate preparation materials for a networking event",
                parameters: schema
            )
        )
    }

    nonisolated private static func buildDebriefEventToolStatic() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Process post-event debrief information and generate follow-up actions.
                Captures contacts made, event rating, what worked/didn't work.
                Generates prioritized follow-up actions with deadlines.
                """,
            properties: [
                "event_id": JSONSchema(
                    type: .string,
                    description: "UUID of the event being debriefed"
                ),
                "contacts_made": JSONSchema(
                    type: .array,
                    description: "Contacts made at the event",
                    items: JSONSchema(
                        type: .object,
                        properties: [
                            "name": JSONSchema(type: .string),
                            "company": JSONSchema(type: .string),
                            "title": JSONSchema(type: .string),
                            "email": JSONSchema(type: .string),
                            "linkedin": JSONSchema(type: .string),
                            "notes": JSONSchema(type: .string),
                            "follow_up_action": JSONSchema(type: .string)
                        ],
                        required: ["name"]
                    )
                ),
                "rating": JSONSchema(
                    type: .integer,
                    description: "Event rating 1-5"
                ),
                "would_recommend": JSONSchema(
                    type: .boolean,
                    description: "Would recommend this event to others"
                ),
                "what_worked": JSONSchema(
                    type: .string,
                    description: "What worked well at this event"
                ),
                "what_didnt_work": JSONSchema(
                    type: .string,
                    description: "What didn't work or could be improved"
                ),
                "notes": JSONSchema(
                    type: .string,
                    description: "General notes about the event"
                )
            ],
            required: ["event_id", "rating"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "debrief_event",
                strict: false,
                description: "Process event debrief and generate follow-up actions",
                parameters: schema
            )
        )
    }

    nonisolated private static func buildSuggestNetworkingActionsToolStatic() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Suggest networking actions based on current contacts and relationship health.
                Considers warmth decay, pending follow-ups, and upcoming events.
                Returns prioritized list of suggested actions.
                """,
            properties: [
                "focus": JSONSchema(
                    type: .string,
                    description: "Focus area: reactivate_dormant, maintain_hot, expand_network",
                    enum: ["reactivate_dormant", "maintain_hot", "expand_network", "balanced"]
                ),
                "max_suggestions": JSONSchema(
                    type: .integer,
                    description: "Maximum suggestions to return (default: 5)"
                )
            ],
            required: [],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "suggest_networking_actions",
                strict: false,
                description: "Suggest networking actions to maintain relationships",
                parameters: schema
            )
        )
    }

    nonisolated private static func buildDraftOutreachMessageToolStatic() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Draft an outreach message to a networking contact.
                Considers relationship context, reason for outreach, and communication style.
                Returns draft message with subject line (if email).
                """,
            properties: [
                "contact_id": JSONSchema(
                    type: .string,
                    description: "UUID of the contact"
                ),
                "purpose": JSONSchema(
                    type: .string,
                    description: "Purpose of outreach",
                    enum: ["follow_up", "reconnect", "ask_for_referral", "thank_you", "share_update", "request_meeting"]
                ),
                "channel": JSONSchema(
                    type: .string,
                    description: "Communication channel",
                    enum: ["email", "linkedin", "text"]
                ),
                "context": JSONSchema(
                    type: .string,
                    description: "Additional context for the message"
                ),
                "tone": JSONSchema(
                    type: .string,
                    description: "Desired tone: professional, casual, warm",
                    enum: ["professional", "casual", "warm"]
                )
            ],
            required: ["contact_id", "purpose", "channel"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "draft_outreach_message",
                strict: false,
                description: "Draft an outreach message to a contact",
                parameters: schema
            )
        )
    }

    nonisolated private static func buildRecommendWeeklyGoalsToolStatic() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Recommend weekly goals based on job search progress and upcoming opportunities.
                Considers past performance, pipeline status, and available time.
                Returns balanced goals for applications, networking, and time investment.
                """,
            properties: [
                "available_hours": JSONSchema(
                    type: .number,
                    description: "Hours available for job search this week"
                ),
                "priority": JSONSchema(
                    type: .string,
                    description: "Current priority: volume, quality, networking, balanced",
                    enum: ["volume", "quality", "networking", "balanced"]
                )
            ],
            required: [],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "recommend_weekly_goals",
                strict: false,
                description: "Recommend weekly goals for job search",
                parameters: schema
            )
        )
    }

    nonisolated private static func buildGenerateWeeklyReflectionToolStatic() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Generate a weekly reflection on job search progress.
                Analyzes achievements, areas for improvement, and provides encouragement.
                Returns 2-3 paragraph reflection with actionable suggestions.
                """,
            properties: [
                "include_metrics": JSONSchema(
                    type: .boolean,
                    description: "Include specific metrics in reflection (default: true)"
                ),
                "focus": JSONSchema(
                    type: .string,
                    description: "Reflection focus: achievements, improvements, planning",
                    enum: ["achievements", "improvements", "planning", "balanced"]
                )
            ],
            required: [],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: "generate_weekly_reflection",
                strict: false,
                description: "Generate weekly reflection on job search progress",
                parameters: schema
            )
        )
    }

    // MARK: - Tool Implementations

    private func executeGenerateDailyTasks(args: JSON) async throws -> String {
        let focusArea = args["focus_area"].string ?? "balanced"
        let maxTasks = args["max_tasks"].int ?? 8

        // Get context from provider
        let context = await contextProvider.getDailyTaskContext()

        var result = JSON()
        result["status"].string = "context_provided"
        result["focus_area"].string = focusArea
        result["max_tasks"].int = maxTasks
        result["context"] = context
        result["instruction"].string = """
            Based on the context provided, generate \(maxTasks) prioritized daily tasks.
            Focus area: \(focusArea).
            Return tasks as a JSON array with: task_type, title, description, priority (0-2), estimated_minutes.
            Task types: gather, customize, apply, follow_up, networking, event_prep, debrief.
            """
        return result.rawString() ?? "{}"
    }

    private func executeDiscoverJobSources(args: JSON) async throws -> String {
        let sectors = args["sectors"].arrayValue.map { $0.stringValue }
        let location = args["location"].stringValue
        let includeRemote = args["include_remote"].bool ?? true
        let count = args["count"].int ?? 10

        let context = await contextProvider.getPreferencesContext()
        let existingSources = await contextProvider.getExistingSourceUrls()

        var result = JSON()
        result["status"].string = "context_provided"
        result["sectors"] = JSON(sectors)
        result["location"].string = location
        result["include_remote"].bool = includeRemote
        result["requested_count"].int = count
        result["existing_source_urls"] = JSON(existingSources)
        result["preferences"] = context
        result["instruction"].string = """
            Discover \(count) new job sources for sectors: \(sectors.joined(separator: ", ")) in \(location).
            Exclude URLs already in existing_source_urls.
            Include remote-friendly: \(includeRemote).
            Return sources as JSON array with: name, url, category, relevance_reason, recommended_cadence_days.
            Categories: local, industry, company_direct, aggregator, startup, staffing, networking.
            """
        return result.rawString() ?? "{}"
    }

    private func executeDiscoverEvents(args: JSON) async throws -> String {
        let sectors = args["sectors"].arrayValue.map { $0.stringValue }
        let location = args["location"].stringValue
        let daysAhead = args["days_ahead"].int ?? 14
        let includeVirtual = args["include_virtual"].bool ?? true

        let context = await contextProvider.getPreferencesContext()
        let existingEventUrls = await contextProvider.getExistingEventUrls()

        var result = JSON()
        result["status"].string = "context_provided"
        result["sectors"] = JSON(sectors)
        result["location"].string = location
        result["days_ahead"].int = daysAhead
        result["include_virtual"].bool = includeVirtual
        result["existing_event_urls"] = JSON(existingEventUrls)
        result["preferences"] = context
        result["instruction"].string = """
            Search for networking events in the next \(daysAhead) days.
            Sectors: \(sectors.joined(separator: ", ")). Location: \(location).
            Include virtual: \(includeVirtual).
            Exclude URLs in existing_event_urls.
            Return events as JSON array with: name, date (ISO8601), time, location, url, event_type, organizer, estimated_attendance, cost, relevance_reason.
            Event types: meetup, happy_hour, conference, workshop, tech_talk, open_house, career_fair, panel_discussion, hackathon, virtual_event.
            """
        return result.rawString() ?? "{}"
    }

    private func executeEvaluateEvent(args: JSON) async throws -> String {
        let eventId = args["event_id"].stringValue

        let eventContext = await contextProvider.getEventContext(eventId: eventId)
        let historicalData = await contextProvider.getEventFeedbackSummary()
        let preferences = await contextProvider.getPreferencesContext()

        var result = JSON()
        result["status"].string = "context_provided"
        result["event_id"].string = eventId
        result["event"] = eventContext
        result["historical_feedback"] = historicalData
        result["preferences"] = preferences
        result["instruction"].string = """
            Evaluate this event for attendance value.
            Consider: relevance to target sectors, expected networking value, time investment, historical outcomes from similar events.
            Return JSON with: recommendation (strong_yes/yes/maybe/skip), rationale, expected_value, concerns (array), preparation_tips.
            """
        return result.rawString() ?? "{}"
    }

    private func executePrepareForEvent(args: JSON) async throws -> String {
        let eventId = args["event_id"].stringValue
        let focusCompanies = args["focus_companies"].arrayValue.map { $0.stringValue }
        let personalGoals = args["personal_goals"].string

        let eventContext = await contextProvider.getEventContext(eventId: eventId)
        let preferences = await contextProvider.getPreferencesContext()
        let existingContacts = await contextProvider.getContactsAtCompanies(focusCompanies)

        var result = JSON()
        result["status"].string = "context_provided"
        result["event_id"].string = eventId
        result["event"] = eventContext
        result["focus_companies"] = JSON(focusCompanies)
        result["personal_goals"].string = personalGoals ?? "Make meaningful connections"
        result["existing_contacts"] = existingContacts
        result["preferences"] = preferences
        result["instruction"].string = """
            Generate event preparation materials.
            Return JSON with:
            - goal: One sentence goal for this event
            - pitch_script: 30-second elevator pitch
            - talking_points: Array of {topic, relevance, your_angle}
            - target_companies: Array of {company, why_relevant, recent_news, open_roles, possible_openers}
            - conversation_starters: Array of conversation starters
            - things_to_avoid: Array of topics/behaviors to avoid
            """
        return result.rawString() ?? "{}"
    }

    private func executeDebriefEvent(args: JSON) async throws -> String {
        let eventId = args["event_id"].stringValue
        let contactsMade = args["contacts_made"].arrayValue
        let rating = args["rating"].int ?? 3
        let wouldRecommend = args["would_recommend"].bool ?? false
        let whatWorked = args["what_worked"].string
        let whatDidntWork = args["what_didnt_work"].string
        let notes = args["notes"].string

        let eventContext = await contextProvider.getEventContext(eventId: eventId)

        var result = JSON()
        result["status"].string = "context_provided"
        result["event_id"].string = eventId
        result["event"] = eventContext
        result["contacts_made"] = JSON(contactsMade.map { $0.dictionaryObject ?? [:] })
        result["rating"].int = rating
        result["would_recommend"].bool = wouldRecommend
        result["what_worked"].string = whatWorked ?? ""
        result["what_didnt_work"].string = whatDidntWork ?? ""
        result["notes"].string = notes ?? ""
        result["instruction"].string = """
            Process this event debrief and generate follow-up actions.
            Return JSON with:
            - summary: Brief summary of the event outcome
            - follow_up_actions: Array of {contact_name, action, deadline (within_24_hours/within_3_days/this_week/next_week), priority (high/medium/low)}
            - lessons_learned: What to remember for future similar events
            - event_feedback: Structured feedback for learning system
            """
        return result.rawString() ?? "{}"
    }

    private func executeSuggestNetworkingActions(args: JSON) async throws -> String {
        let focus = args["focus"].string ?? "balanced"
        let maxSuggestions = args["max_suggestions"].int ?? 5

        let contactsNeedingAttention = await contextProvider.getContactsNeedingAttention()
        let hotContacts = await contextProvider.getHotContacts()
        let pendingFollowUps = await contextProvider.getPendingFollowUps()
        let upcomingEvents = await contextProvider.getUpcomingEventsContext()

        var result = JSON()
        result["status"].string = "context_provided"
        result["focus"].string = focus
        result["max_suggestions"].int = maxSuggestions
        result["contacts_needing_attention"] = contactsNeedingAttention
        result["hot_contacts"] = hotContacts
        result["pending_follow_ups"] = pendingFollowUps
        result["upcoming_events"] = upcomingEvents
        result["instruction"].string = """
            Suggest \(maxSuggestions) networking actions. Focus: \(focus).
            Return JSON array with: contact_name, contact_id, action_type (reach_out/follow_up/reconnect/invite_to_event), action_description, urgency (high/medium/low), suggested_message_opener.
            """
        return result.rawString() ?? "{}"
    }

    private func executeDraftOutreachMessage(args: JSON) async throws -> String {
        let contactId = args["contact_id"].stringValue
        let purpose = args["purpose"].stringValue
        let channel = args["channel"].stringValue
        let context = args["context"].string
        let tone = args["tone"].string ?? "professional"

        let contactContext = await contextProvider.getContactContext(contactId: contactId)
        let interactionHistory = await contextProvider.getContactInteractionHistory(contactId: contactId)
        let userProfile = await contextProvider.getUserProfileContext()

        var result = JSON()
        result["status"].string = "context_provided"
        result["contact_id"].string = contactId
        result["contact"] = contactContext
        result["interaction_history"] = interactionHistory
        result["user_profile"] = userProfile
        result["purpose"].string = purpose
        result["channel"].string = channel
        result["additional_context"].string = context ?? ""
        result["tone"].string = tone
        result["instruction"].string = """
            Draft an outreach message for \(channel).
            Purpose: \(purpose). Tone: \(tone).
            Return JSON with:
            - subject: Subject line (for email)
            - message: The draft message
            - notes: Tips for sending/timing
            """
        return result.rawString() ?? "{}"
    }

    private func executeRecommendWeeklyGoals(args: JSON) async throws -> String {
        let availableHours = args["available_hours"].double
        let priority = args["priority"].string ?? "balanced"

        let historicalPerformance = await contextProvider.getWeeklyPerformanceHistory()
        let pipelineStatus = await contextProvider.getPipelineStatus()
        let upcomingEvents = await contextProvider.getUpcomingEventsContext()

        var result = JSON()
        result["status"].string = "context_provided"
        result["available_hours"].double = availableHours ?? 20.0
        result["priority"].string = priority
        result["historical_performance"] = historicalPerformance
        result["pipeline_status"] = pipelineStatus
        result["upcoming_events"] = upcomingEvents
        result["instruction"].string = """
            Recommend weekly goals. Available hours: \(availableHours ?? 20.0). Priority: \(priority).
            Return JSON with:
            - application_target: Number of applications to submit
            - events_target: Number of events to attend
            - new_contacts_target: Number of new contacts to make
            - follow_ups_target: Number of follow-ups to send
            - time_target_hours: Hours to dedicate
            - rationale: Why these targets make sense
            - focus_areas: Array of specific focus areas for the week
            """
        return result.rawString() ?? "{}"
    }

    private func executeGenerateWeeklyReflection(args: JSON) async throws -> String {
        let includeMetrics = args["include_metrics"].bool ?? true
        let focus = args["focus"].string ?? "balanced"

        let weeklySummary = await contextProvider.getWeeklySummaryContext()
        let goalProgress = await contextProvider.getGoalProgressContext()

        var result = JSON()
        result["status"].string = "context_provided"
        result["include_metrics"].bool = includeMetrics
        result["focus"].string = focus
        result["weekly_summary"] = weeklySummary
        result["goal_progress"] = goalProgress
        result["instruction"].string = """
            Generate a weekly reflection. Focus: \(focus). Include metrics: \(includeMetrics).
            Return JSON with:
            - reflection: 2-3 paragraph reflection text
            - achievements: Array of notable achievements
            - improvements: Array of areas to improve
            - next_week_focus: Key focus for next week
            - encouragement: Personalized encouragement message
            """
        return result.rawString() ?? "{}"
    }

    // MARK: - Helpers

    private func errorResult(_ message: String) -> String {
        var result = JSON()
        result["status"].string = "error"
        result["error"].string = message
        return result.rawString() ?? "{\"status\": \"error\"}"
    }
}

// MARK: - Tool Execution Error

enum SearchOpsToolError: LocalizedError {
    case invalidParameters(String)
    case notFound(String)
    case contextUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidParameters(let msg):
            return "Invalid parameters: \(msg)"
        case .notFound(let msg):
            return "Not found: \(msg)"
        case .contextUnavailable(let msg):
            return "Context unavailable: \(msg)"
        }
    }
}
