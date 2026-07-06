//
//  DiscoveryToolSchemas.swift
//  Sprung
//
//  Anthropic tool definitions for the Discovery agent loop.
//  Input-schema keys are camelCase (keys we control); tool names stay
//  snake_case per the app-wide Anthropic tool naming convention.
//

import Foundation
import SwiftOpenAI

enum DiscoveryToolSchemas {
    // MARK: - Tool Names

    /// Completion tool: the agent submits its final response through this tool,
    /// which terminates the shared `AnthropicToolLoopRunner` loop.
    static let finalResponseToolName = "submit_final_response"

    // MARK: - Complete Tool Definitions

    /// All Discovery agent tools: the two context tools plus the completion tool.
    static let allTools: [AnthropicTool] = [
        buildPrepareForEventTool(),
        buildGenerateWeeklyReflectionTool(),
        buildSubmitFinalResponseTool()
    ]

    // MARK: - Tool Builders

    private static func buildPrepareForEventTool() -> AnthropicTool {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "eventId": [
                    "type": "string",
                    "description": "UUID of the event to prepare for"
                ],
                "focusCompanies": [
                    "type": "array",
                    "description": "Specific companies to research for this event",
                    "items": ["type": "string"]
                ],
                "personalGoals": [
                    "type": "string",
                    "description": "Personal goals for this event (e.g., make 3 contacts)"
                ]
            ],
            "required": ["eventId"],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: "prepare_for_event",
            description: """
                Generate preparation materials for an upcoming networking event.
                Creates: elevator pitch, talking points, target company context,
                conversation starters, and things to avoid.
                """,
            inputSchema: schema
        ))
    }

    private static func buildGenerateWeeklyReflectionTool() -> AnthropicTool {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "includeMetrics": [
                    "type": "boolean",
                    "description": "Include specific metrics in reflection (default: true)"
                ],
                "focus": [
                    "type": "string",
                    "description": "Reflection focus: achievements, improvements, planning",
                    "enum": ["achievements", "improvements", "planning", "balanced"]
                ]
            ],
            "required": [],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: "generate_weekly_reflection",
            description: """
                Generate a weekly reflection on job search progress.
                Analyzes achievements, areas for improvement, and provides encouragement.
                Returns 2-3 paragraph reflection with actionable suggestions.
                """,
            inputSchema: schema
        ))
    }

    private static func buildSubmitFinalResponseTool() -> AnthropicTool {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "response": [
                    "type": "string",
                    "description": "The complete final response, in exactly the output format the task requested"
                ]
            ],
            "required": ["response"],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: finalResponseToolName,
            description: """
                Submit your final response for this task. Call this exactly once, when your
                analysis is complete, passing the entire final response as `response`.
                """,
            inputSchema: schema,
            strict: true
        ))
    }
}
