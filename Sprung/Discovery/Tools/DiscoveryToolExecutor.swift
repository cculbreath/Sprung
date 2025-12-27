//
//  DiscoveryToolExecutor.swift
//  Sprung
//
//  Actor-based tool executor for Discovery module.
//  Provides tool schemas and execution for LLM agent interactions.
//  Uses ChatCompletionParameters.Tool pattern per SEARCHOPS_AMENDMENT.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

// MARK: - Discovery Tool Executor

actor DiscoveryToolExecutor {

    // MARK: - Dependencies

    private let contextProvider: DiscoveryContextProvider

    // MARK: - Initialization

    init(contextProvider: DiscoveryContextProvider) {
        self.contextProvider = contextProvider
    }

    // MARK: - Public API

    /// Get all tool schemas for LLM (nonisolated - schemas are static data)
    nonisolated func getToolSchemas() -> [ChatCompletionParameters.Tool] {
        return DiscoveryToolSchemas.allTools
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

enum DiscoveryToolError: LocalizedError {
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
