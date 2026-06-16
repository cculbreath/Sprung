//
//  DiscoveryToolSchemas.swift
//  Sprung
//
//  JSON schemas for Discovery LLM tools.
//

import Foundation
import SwiftOpenAI

enum DiscoveryToolSchemas {
    // MARK: - Complete Tool Definitions

    /// Returns all Discovery tools as ChatCompletionParameters.Tool objects
    static let allTools: [ChatCompletionParameters.Tool] = [
        buildGenerateDailyTasksTool(),
        buildPrepareForEventTool(),
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
