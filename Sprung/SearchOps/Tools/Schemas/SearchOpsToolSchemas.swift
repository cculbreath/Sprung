//
//  SearchOpsToolSchemas.swift
//  Sprung
//
//  JSON schemas for SearchOps LLM tools.
//

import Foundation
import SwiftOpenAI

enum SearchOpsToolSchemas {
    // MARK: - Output Schemas (kept for reference if needed elsewhere)

    static let discoverJobSourcesSchema = SchemaLoader.loadSchema(resourceName: "discover_job_sources")
    static let jobSourceOutputSchema = SchemaLoader.loadSchema(resourceName: "job_source_output")
    static let generateDailyTasksSchema = SchemaLoader.loadSchema(resourceName: "generate_daily_tasks")
    static let dailyTaskOutputSchema = SchemaLoader.loadSchema(resourceName: "daily_task_output")
    static let generateWeeklyReflectionSchema = SchemaLoader.loadSchema(resourceName: "generate_weekly_reflection")
    static let discoverNetworkingEventsSchema = SchemaLoader.loadSchema(resourceName: "discover_networking_events")
    static let networkingEventOutputSchema = SchemaLoader.loadSchema(resourceName: "networking_event_output")
    static let evaluateNetworkingEventSchema = SchemaLoader.loadSchema(resourceName: "evaluate_networking_event")
    static let eventEvaluationOutputSchema = SchemaLoader.loadSchema(resourceName: "event_evaluation_output")
    static let prepareForEventSchema = SchemaLoader.loadSchema(resourceName: "prepare_for_event")
    static let eventPrepOutputSchema = SchemaLoader.loadSchema(resourceName: "event_prep_output")
    static let suggestNetworkingActionsSchema = SchemaLoader.loadSchema(resourceName: "suggest_networking_actions")
    static let networkingActionOutputSchema = SchemaLoader.loadSchema(resourceName: "networking_action_output")
    static let draftOutreachMessageSchema = SchemaLoader.loadSchema(resourceName: "draft_outreach_message")
    static let outreachMessageOutputSchema = SchemaLoader.loadSchema(resourceName: "outreach_message_output")

    // MARK: - Complete Tool Definitions

    /// Returns all SearchOps tools as ChatCompletionParameters.Tool objects
    static let allTools: [ChatCompletionParameters.Tool] = [
        buildGenerateDailyTasksTool(),
        buildDiscoverJobSourcesTool(),
        buildDiscoverNetworkingEventsTool(),
        buildEvaluateNetworkingEventTool(),
        buildPrepareForEventTool(),
        buildDebriefEventTool(),
        buildSuggestNetworkingActionsTool(),
        buildDraftOutreachMessageTool(),
        buildRecommendWeeklyGoalsTool(),
        buildGenerateWeeklyReflectionTool()
    ]

    // MARK: - Tool Builders

    private static func buildGenerateDailyTasksTool() -> ChatCompletionParameters.Tool {
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

    private static func buildDiscoverJobSourcesTool() -> ChatCompletionParameters.Tool {
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

    private static func buildDiscoverNetworkingEventsTool() -> ChatCompletionParameters.Tool {
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

    private static func buildEvaluateNetworkingEventTool() -> ChatCompletionParameters.Tool {
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

    private static func buildPrepareForEventTool() -> ChatCompletionParameters.Tool {
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

    private static func buildDebriefEventTool() -> ChatCompletionParameters.Tool {
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

    private static func buildSuggestNetworkingActionsTool() -> ChatCompletionParameters.Tool {
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

    private static func buildDraftOutreachMessageTool() -> ChatCompletionParameters.Tool {
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

    private static func buildRecommendWeeklyGoalsTool() -> ChatCompletionParameters.Tool {
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

    private static func buildGenerateWeeklyReflectionTool() -> ChatCompletionParameters.Tool {
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
}
