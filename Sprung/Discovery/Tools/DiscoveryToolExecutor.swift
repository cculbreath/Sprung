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
        let argsDict: [String: Any]
        if let data = arguments.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            argsDict = parsed
        } else {
            argsDict = [:]
        }

        do {
            switch toolName {
            case "generate_daily_tasks":
                return try await executeGenerateDailyTasks(args: argsDict)
            case "discover_job_sources":
                return try await executeDiscoverJobSources(args: argsDict)
            case "discover_networking_events":
                return try await executeDiscoverEvents(args: argsDict)
            case "evaluate_networking_event":
                return try await executeEvaluateEvent(args: argsDict)
            case "prepare_for_event":
                return try await executePrepareForEvent(args: argsDict)
            case "debrief_event":
                return try await executeDebriefEvent(args: argsDict)
            case "suggest_networking_actions":
                return try await executeSuggestNetworkingActions(args: argsDict)
            case "draft_outreach_message":
                return try await executeDraftOutreachMessage(args: argsDict)
            case "recommend_weekly_goals":
                return try await executeRecommendWeeklyGoals(args: argsDict)
            case "generate_weekly_reflection":
                return try await executeGenerateWeeklyReflection(args: argsDict)
            default:
                return errorResult("Unknown tool: \(toolName)")
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    // MARK: - Argument Helpers

    private func stringArg(_ args: [String: Any], _ key: String, default defaultValue: String = "") -> String {
        args[key] as? String ?? defaultValue
    }

    private func intArg(_ args: [String: Any], _ key: String, default defaultValue: Int) -> Int {
        args[key] as? Int ?? defaultValue
    }

    private func boolArg(_ args: [String: Any], _ key: String, default defaultValue: Bool) -> Bool {
        args[key] as? Bool ?? defaultValue
    }

    private func stringArrayArg(_ args: [String: Any], _ key: String) -> [String] {
        args[key] as? [String] ?? []
    }

    // MARK: - Result Building

    /// Build a JSON string from a dictionary, embedding pre-serialized JSON strings as raw values.
    /// Keys listed in `rawJsonKeys` have their String values parsed back into objects so they
    /// appear as structured JSON rather than escaped string literals.
    private func buildResult(_ dict: [String: Any], rawJsonKeys: Set<String> = []) -> String {
        var resolved: [String: Any] = [:]
        for (key, value) in dict {
            if rawJsonKeys.contains(key),
               let jsonString = value as? String,
               let data = jsonString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                resolved[key] = parsed
            } else {
                resolved[key] = value
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: resolved, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return result
    }

    // MARK: - Tool Implementations

    private func executeGenerateDailyTasks(args: [String: Any]) async throws -> String {
        let focusArea = stringArg(args, "focus_area", default: "balanced")
        let maxTasks = intArg(args, "max_tasks", default: 8)

        let context = await contextProvider.getDailyTaskContext()

        return buildResult([
            "status": "context_provided",
            "focus_area": focusArea,
            "max_tasks": maxTasks,
            "context": context,
            "instruction": """
                Based on the context provided, generate \(maxTasks) prioritized daily tasks.
                Focus area: \(focusArea).
                Return tasks as a JSON array with: task_type, title, description, priority (0-2), estimated_minutes.
                Task types: gather, customize, apply, follow_up, networking, event_prep, debrief.
                """
        ], rawJsonKeys: ["context"])
    }

    private func executeDiscoverJobSources(args: [String: Any]) async throws -> String {
        let sectors = stringArrayArg(args, "sectors")
        let location = stringArg(args, "location")
        let includeRemote = boolArg(args, "include_remote", default: true)
        let count = intArg(args, "count", default: 10)

        let context = await contextProvider.getPreferencesContext()
        let existingSources = await contextProvider.getExistingSourceUrls()

        return buildResult([
            "status": "context_provided",
            "sectors": sectors,
            "location": location,
            "include_remote": includeRemote,
            "requested_count": count,
            "existing_source_urls": existingSources,
            "preferences": context,
            "instruction": """
                Discover \(count) new job sources for sectors: \(sectors.joined(separator: ", ")) in \(location).
                Exclude URLs already in existing_source_urls.
                Include remote-friendly: \(includeRemote).
                Return sources as JSON array with: name, url, category, relevance_reason, recommended_cadence_days.
                Categories: local, industry, company_direct, aggregator, startup, staffing, networking.
                """
        ], rawJsonKeys: ["preferences"])
    }

    private func executeDiscoverEvents(args: [String: Any]) async throws -> String {
        let sectors = stringArrayArg(args, "sectors")
        let location = stringArg(args, "location")
        let daysAhead = intArg(args, "days_ahead", default: 14)
        let includeVirtual = boolArg(args, "include_virtual", default: true)

        let context = await contextProvider.getPreferencesContext()
        let existingEventUrls = await contextProvider.getExistingEventUrls()

        return buildResult([
            "status": "context_provided",
            "sectors": sectors,
            "location": location,
            "days_ahead": daysAhead,
            "include_virtual": includeVirtual,
            "existing_event_urls": existingEventUrls,
            "preferences": context,
            "instruction": """
                Search for networking events in the next \(daysAhead) days.
                Sectors: \(sectors.joined(separator: ", ")). Location: \(location).
                Include virtual: \(includeVirtual).
                Exclude URLs in existing_event_urls.
                Return events as JSON array with: name, date (ISO8601), time, location, url, event_type, organizer, estimated_attendance, cost, relevance_reason.
                Event types: meetup, happy_hour, conference, workshop, tech_talk, open_house, career_fair, panel_discussion, hackathon, virtual_event.
                """
        ], rawJsonKeys: ["preferences"])
    }

    private func executeEvaluateEvent(args: [String: Any]) async throws -> String {
        let eventId = stringArg(args, "event_id")

        let eventContext = await contextProvider.getEventContext(eventId: eventId)
        let historicalData = await contextProvider.getEventFeedbackSummary()
        let preferences = await contextProvider.getPreferencesContext()

        return buildResult([
            "status": "context_provided",
            "event_id": eventId,
            "event": eventContext,
            "historical_feedback": historicalData,
            "preferences": preferences,
            "instruction": """
                Evaluate this event for attendance value.
                Consider: relevance to target sectors, expected networking value, time investment, historical outcomes from similar events.
                Return JSON with: recommendation (strong_yes/yes/maybe/skip), rationale, expected_value, concerns (array), preparation_tips.
                """
        ], rawJsonKeys: ["event", "historical_feedback", "preferences"])
    }

    private func executePrepareForEvent(args: [String: Any]) async throws -> String {
        let eventId = stringArg(args, "event_id")
        let focusCompanies = stringArrayArg(args, "focus_companies")
        let personalGoals = args["personal_goals"] as? String

        let eventContext = await contextProvider.getEventContext(eventId: eventId)
        let preferences = await contextProvider.getPreferencesContext()
        let existingContacts = await contextProvider.getContactsAtCompanies(focusCompanies)

        return buildResult([
            "status": "context_provided",
            "event_id": eventId,
            "event": eventContext,
            "focus_companies": focusCompanies,
            "personal_goals": personalGoals ?? "Make meaningful connections",
            "existing_contacts": existingContacts,
            "preferences": preferences,
            "instruction": """
                Generate event preparation materials.
                Return JSON with:
                - goal: One sentence goal for this event
                - pitch_script: 30-second elevator pitch
                - talking_points: Array of {topic, relevance, your_angle}
                - target_companies: Array of {company, why_relevant, recent_news, open_roles, possible_openers}
                - conversation_starters: Array of conversation starters
                - things_to_avoid: Array of topics/behaviors to avoid
                """
        ], rawJsonKeys: ["event", "existing_contacts", "preferences"])
    }

    private func executeDebriefEvent(args: [String: Any]) async throws -> String {
        let eventId = stringArg(args, "event_id")
        let contactsMade = args["contacts_made"] as? [[String: Any]] ?? []
        let rating = intArg(args, "rating", default: 3)
        let wouldRecommend = boolArg(args, "would_recommend", default: false)
        let whatWorked = args["what_worked"] as? String
        let whatDidntWork = args["what_didnt_work"] as? String
        let notes = args["notes"] as? String

        let eventContext = await contextProvider.getEventContext(eventId: eventId)

        return buildResult([
            "status": "context_provided",
            "event_id": eventId,
            "event": eventContext,
            "contacts_made": contactsMade,
            "rating": rating,
            "would_recommend": wouldRecommend,
            "what_worked": whatWorked ?? "",
            "what_didnt_work": whatDidntWork ?? "",
            "notes": notes ?? "",
            "instruction": """
                Process this event debrief and generate follow-up actions.
                Return JSON with:
                - summary: Brief summary of the event outcome
                - follow_up_actions: Array of {contact_name, action, deadline (within_24_hours/within_3_days/this_week/next_week), priority (high/medium/low)}
                - lessons_learned: What to remember for future similar events
                - event_feedback: Structured feedback for learning system
                """
        ], rawJsonKeys: ["event"])
    }

    private func executeSuggestNetworkingActions(args: [String: Any]) async throws -> String {
        let focus = stringArg(args, "focus", default: "balanced")
        let maxSuggestions = intArg(args, "max_suggestions", default: 5)

        let contactsNeedingAttention = await contextProvider.getContactsNeedingAttention()
        let hotContacts = await contextProvider.getHotContacts()
        let pendingFollowUps = await contextProvider.getPendingFollowUps()
        let upcomingEvents = await contextProvider.getUpcomingEventsContext()

        return buildResult([
            "status": "context_provided",
            "focus": focus,
            "max_suggestions": maxSuggestions,
            "contacts_needing_attention": contactsNeedingAttention,
            "hot_contacts": hotContacts,
            "pending_follow_ups": pendingFollowUps,
            "upcoming_events": upcomingEvents,
            "instruction": """
                Suggest \(maxSuggestions) networking actions. Focus: \(focus).
                Return JSON array with: contact_name, contact_id, action_type (reach_out/follow_up/reconnect/invite_to_event), action_description, urgency (high/medium/low), suggested_message_opener.
                """
        ], rawJsonKeys: ["contacts_needing_attention", "hot_contacts", "pending_follow_ups", "upcoming_events"])
    }

    private func executeDraftOutreachMessage(args: [String: Any]) async throws -> String {
        let contactId = stringArg(args, "contact_id")
        let purpose = stringArg(args, "purpose")
        let channel = stringArg(args, "channel")
        let additionalContext = args["context"] as? String
        let tone = stringArg(args, "tone", default: "professional")

        let contactContext = await contextProvider.getContactContext(contactId: contactId)
        let interactionHistory = await contextProvider.getContactInteractionHistory(contactId: contactId)
        let userProfile = await contextProvider.getUserProfileContext()

        return buildResult([
            "status": "context_provided",
            "contact_id": contactId,
            "contact": contactContext,
            "interaction_history": interactionHistory,
            "user_profile": userProfile,
            "purpose": purpose,
            "channel": channel,
            "additional_context": additionalContext ?? "",
            "tone": tone,
            "instruction": """
                Draft an outreach message for \(channel).
                Purpose: \(purpose). Tone: \(tone).
                Return JSON with:
                - subject: Subject line (for email)
                - message: The draft message
                - notes: Tips for sending/timing
                """
        ], rawJsonKeys: ["contact", "interaction_history", "user_profile"])
    }

    private func executeRecommendWeeklyGoals(args: [String: Any]) async throws -> String {
        let availableHours = args["available_hours"] as? Double
        let priority = stringArg(args, "priority", default: "balanced")

        let historicalPerformance = await contextProvider.getWeeklyPerformanceHistory()
        let pipelineStatus = await contextProvider.getPipelineStatus()
        let upcomingEvents = await contextProvider.getUpcomingEventsContext()

        return buildResult([
            "status": "context_provided",
            "available_hours": availableHours ?? 20.0,
            "priority": priority,
            "historical_performance": historicalPerformance,
            "pipeline_status": pipelineStatus,
            "upcoming_events": upcomingEvents,
            "instruction": """
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
        ], rawJsonKeys: ["historical_performance", "pipeline_status", "upcoming_events"])
    }

    private func executeGenerateWeeklyReflection(args: [String: Any]) async throws -> String {
        let includeMetrics = boolArg(args, "include_metrics", default: true)
        let focus = stringArg(args, "focus", default: "balanced")

        let weeklySummary = await contextProvider.getWeeklySummaryContext()
        let goalProgress = await contextProvider.getGoalProgressContext()

        return buildResult([
            "status": "context_provided",
            "include_metrics": includeMetrics,
            "focus": focus,
            "weekly_summary": weeklySummary,
            "goal_progress": goalProgress,
            "instruction": """
                Generate a weekly reflection. Focus: \(focus). Include metrics: \(includeMetrics).
                Return JSON with:
                - reflection: 2-3 paragraph reflection text
                - achievements: Array of notable achievements
                - improvements: Array of areas to improve
                - next_week_focus: Key focus for next week
                - encouragement: Personalized encouragement message
                """
        ], rawJsonKeys: ["weekly_summary", "goal_progress"])
    }

    // MARK: - Helpers

    private func errorResult(_ message: String) -> String {
        let dict: [String: String] = ["status": "error", "error": message]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"error\"}"
        }
        return result
    }
}
