//
//  CoachingToolSchemas.swift
//  Sprung
//
//  Anthropic tool definitions for the Job Search Coach LLM tools.
//  Defines the coaching_multiple_choice tool that allows the LLM
//  to ask the user structured questions during coaching sessions.
//  All JSON keys we control are camelCase; tool names stay snake_case
//  per the app-wide Anthropic tool naming convention.
//

import Foundation
import SwiftOpenAI

// MARK: - Tool Argument Codable Structs

struct CoachingMultipleChoiceArgs: Codable {
    let question: String
    let options: [CoachingMultipleChoiceOptionArgs]
    let questionCategory: String
}

struct CoachingMultipleChoiceOptionArgs: Codable {
    let value: Int
    let label: String
    let emoji: String?
    let actionId: String?
}

struct GetKnowledgeCardArgs: Codable {
    let cardId: String
    let startLine: Int?
    let endLine: Int?
}

struct GetJobDescriptionArgs: Codable {
    let jobAppId: String
}

struct GetResumeArgs: Codable {
    let resumeId: String
    let section: String?
}

struct UpdateDailyTasksArgs: Codable {
    /// The coach's directive for the shared daily-task generator: what today's
    /// list should emphasize, grounded in the session conversation.
    let directive: String
}

struct ChooseBestJobsArgs: Codable {
    let count: Int
    let reason: String
}

// MARK: - Tool Result Codable Structs

struct KnowledgeCardToolResult: Encodable {
    let cardId: String
    let title: String
    let type: String?
    let organization: String?
    let dateRange: String?
    let content: String
    let wordCount: Int
}

struct JobDescriptionToolResult: Encodable {
    let jobAppId: String
    let company: String
    let position: String
    let status: String
    let jobDescription: String
    let jobUrl: String
    let notes: String
    let appliedDate: String?
}

struct CoachingResumeToolResult: Encodable {
    let resumeId: String
    let template: String
    let section: String?
    let content: String?
    let availableSections: [String]?
    let summary: String?
}

struct ChooseBestJobsToolResult: Encodable {
    let success: Bool
    let selectedCount: Int?
    let identifiedCount: Int?
    let selections: [ChooseBestJobsSelectionResult]?
    let overallAnalysis: String?
    let considerations: [String]?
    let error: String?
}

struct ChooseBestJobsSelectionResult: Encodable {
    let company: String
    let role: String
    let matchScore: Double
    let reasoning: String
}

struct ToolAnswerResult: Encodable {
    let selectedValue: Int
    let selectedLabel: String
}

struct ToolErrorResult: Encodable {
    let error: String
}

enum CoachingToolSchemas {

    // MARK: - Tool Names

    static let multipleChoiceToolName = "coaching_multiple_choice"
    static let getKnowledgeCardToolName = "get_knowledge_card"
    static let getJobDescriptionToolName = "get_job_description"
    static let getResumeToolName = "get_resume"
    static let updateDailyTasksToolName = "update_daily_tasks"
    static let chooseBestJobsToolName = "choose_best_jobs"

    // MARK: - Complete Tool Definitions

    /// All coaching tools including background research tools.
    static let allTools: [AnthropicTool] = [
        buildCoachingMultipleChoiceTool(),
        buildGetKnowledgeCardTool(),
        buildGetJobDescriptionTool(),
        buildGetResumeTool(),
        buildUpdateDailyTasksTool(),
        buildChooseBestJobsTool()
    ]

    // MARK: - Multiple Choice Question Tool

    /// The coaching_multiple_choice tool lets the LLM ask the user one earned
    /// multiple-choice question, or offer the end-of-session next-step choice
    /// (options carrying `actionId`).
    static func buildCoachingMultipleChoiceTool() -> AnthropicTool {
        let optionSchema: [String: Any] = [
            "type": "object",
            "description": "A single answer option for the question",
            "properties": [
                "value": [
                    "type": "integer",
                    "description": "Numeric value for this option (1-10 scale recommended for scales, 1-5 for preferences)"
                ],
                "label": [
                    "type": "string",
                    "description": "Display label for this option (keep concise, 2-5 words)"
                ],
                "emoji": [
                    "type": ["string", "null"],
                    "description": "Optional emoji to display with this option, or null"
                ],
                "actionId": [
                    "type": ["string", "null"],
                    "description": """
                        Only for the end-of-session next-step choice: "generate_tasks" \
                        (build today's task list now) or "done" (keep the list conservative — \
                        carry over open tasks, add nothing new unless critical). \
                        Must be null on data-gathering questions.
                        """
                ]
            ],
            "required": ["value", "label", "emoji", "actionId"],
            "additionalProperties": false
        ]

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "question": [
                    "type": "string",
                    "description": "The question to ask the user. Plain, direct language."
                ],
                "options": [
                    "type": "array",
                    "description": "2-5 answer options for the user to choose from. Each should be distinct and meaningful.",
                    "items": optionSchema
                ],
                "questionCategory": [
                    "type": "string",
                    "description": """
                        Short snake_case category you name yourself, describing what the question \
                        probes (examples: motivation, blockers, interview_prep, search_strategy, \
                        time_budget, wellbeing, next_step). Categories asked in recent sessions \
                        are listed in your context — do not reuse them unless the data warrants it. \
                        Use "next_step" for the end-of-session action choice.
                        """
                ]
            ],
            "required": ["question", "options", "questionCategory"],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: multipleChoiceToolName,
            description: """
                Present a multiple choice question to the user.
                Two uses:
                1. AT MOST ONE data-gathering question per session, and only when the activity \
                data cannot answer it. Set actionId to null on every option.
                2. The end-of-session next-step choice: after you have shared your observations \
                and plan, offer options whose actionId is "generate_tasks" or "done".
                Options should be clear, distinct, and cover the range of likely responses.
                """,
            inputSchema: schema,
            strict: true
        ))
    }

    // MARK: - Tool Response Parsing

    /// Parse a coaching question from raw JSON arguments string
    static func parseQuestion(from arguments: String) -> CoachingQuestion? {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(CoachingMultipleChoiceArgs.self, from: data) else {
            return nil
        }

        let category = args.questionCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !args.question.isEmpty, !category.isEmpty else {
            return nil
        }

        let options = args.options.compactMap { opt -> QuestionOption? in
            guard !opt.label.isEmpty else { return nil }
            return QuestionOption(value: opt.value, label: opt.label, emoji: opt.emoji, actionId: opt.actionId)
        }

        guard !options.isEmpty else { return nil }

        return CoachingQuestion(
            questionText: args.question,
            options: options,
            category: category
        )
    }

    // MARK: - Knowledge Card Tool

    /// Tool to retrieve detailed content from a knowledge card
    static func buildGetKnowledgeCardTool() -> AnthropicTool {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "cardId": [
                    "type": "string",
                    "description": "The ID of the knowledge card to retrieve (from the available cards list)"
                ],
                "startLine": [
                    "type": ["integer", "null"],
                    "description": "Start line number for a specific excerpt (1-indexed), or null for full content"
                ],
                "endLine": [
                    "type": ["integer", "null"],
                    "description": "End line number for a specific excerpt, or null for full content"
                ]
            ],
            "required": ["cardId", "startLine", "endLine"],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: getKnowledgeCardToolName,
            description: """
                Retrieve detailed content from a user's knowledge card. Use this to learn more about
                specific work experience, skills, or projects. You can request specific line ranges
                for targeted information.
                """,
            inputSchema: schema,
            strict: true
        ))
    }

    // MARK: - Job Description Tool

    /// Tool to retrieve job description details for a specific job application
    static func buildGetJobDescriptionTool() -> AnthropicTool {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "jobAppId": [
                    "type": "string",
                    "description": "The UUID of the job application to retrieve details for"
                ]
            ],
            "required": ["jobAppId"],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: getJobDescriptionToolName,
            description: """
                Retrieve the job description and details for a specific job application.
                Use this to understand what the user is applying for and provide targeted coaching.
                """,
            inputSchema: schema,
            strict: true
        ))
    }

    // MARK: - Resume Tool

    /// Tool to retrieve resume content for a specific resume
    static func buildGetResumeTool() -> AnthropicTool {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "resumeId": [
                    "type": "string",
                    "description": "The UUID of the resume to retrieve"
                ],
                "section": [
                    "type": ["string", "null"],
                    "description": "Specific section to retrieve (summary, work, skills, etc.), or null for overview"
                ]
            ],
            "required": ["resumeId", "section"],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: getResumeToolName,
            description: """
                Retrieve the content of a specific resume. Use this to understand what
                materials the user has prepared and provide feedback or suggestions.
                """,
            inputSchema: schema,
            strict: true
        ))
    }

    // MARK: - Update Daily Tasks Tool

    /// Session completion tool: hands the coach's directive to the shared
    /// daily-task generator, which owns carry-over semantics and persistence.
    static func buildUpdateDailyTasksTool() -> AnthropicTool {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "directive": [
                    "type": "string",
                    "description": """
                        2-4 sentences for the task generator: what today's list should \
                        emphasize based on this conversation (energy level, stated blockers, \
                        deadlines, which open tasks matter most). Concrete, not generic.
                        """
                ]
            ],
            "required": ["directive"],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: updateDailyTasksToolName,
            description: """
                End the coaching session and hand off to the daily task generator.
                Call this exactly once, after you have shared your observations and plan.
                The generator sees yesterday's tasks, completion state, preferences, and
                weekly goals — your directive adds what only this conversation revealed.
                """,
            inputSchema: schema,
            strict: true
        ))
    }

    // MARK: - Choose Best Jobs Tool

    /// Tool to trigger the job selection workflow that identifies and advances top job opportunities
    static func buildChooseBestJobsTool() -> AnthropicTool {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "count": [
                    "type": "integer",
                    "description": "Number of top jobs to select (1-10, default 5)"
                ],
                "reason": [
                    "type": "string",
                    "description": "Brief explanation of why you're triggering job selection now"
                ]
            ],
            "required": ["count", "reason"],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: chooseBestJobsToolName,
            description: """
                Analyze all jobs in the Identified stage and select the best matches for the user.
                This triggers the job selection workflow that:
                1. Evaluates all pending job leads against the user's knowledge cards and dossier
                2. Scores and ranks jobs by fit
                3. Advances the top matches to Researching stage
                Use this when the user has accumulated job leads and is ready to focus their efforts.
                """,
            inputSchema: schema,
            strict: true
        ))
    }

}

// MARK: - Task Category

/// Categories for task sections in the Daily view
enum TaskCategory: String, CaseIterable {
    case networking = "networking"
    case apply = "apply"
    case gather = "gather"

    var displayName: String {
        switch self {
        case .networking: return "Networking"
        case .apply: return "Apply"
        case .gather: return "Gather"
        }
    }

    /// Task types that belong to this category
    var taskTypes: [String] {
        switch self {
        case .networking:
            return ["networking", "event_prep", "debrief"]
        case .apply:
            return ["apply", "customize"]
        case .gather:
            return ["gather"]
        }
    }

    /// DailyTaskTypes that belong to this category
    var dailyTaskTypes: [DailyTaskType] {
        switch self {
        case .networking:
            return [.networking, .eventPrep, .eventDebrief]
        case .apply:
            return [.submitApplication, .customizeMaterials]
        case .gather:
            return [.gatherLeads]
        }
    }
}
