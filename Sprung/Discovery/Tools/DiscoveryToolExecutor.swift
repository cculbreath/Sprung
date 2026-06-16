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

    private let contextProvider: DiscoveryContextProviderImpl

    // MARK: - Initialization

    init(contextProvider: DiscoveryContextProviderImpl) {
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
            case "prepare_for_event":
                return try await executePrepareForEvent(args: argsDict)
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
