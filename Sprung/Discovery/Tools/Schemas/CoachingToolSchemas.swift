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
    let questionType: String
}

struct CoachingMultipleChoiceOptionArgs: Codable {
    let value: Int
    let label: String
    let emoji: String?
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
    let tasks: [UpdateDailyTaskEntry]
}

struct UpdateDailyTaskEntry: Codable {
    let taskType: String
    let title: String
    let description: String
    let priority: Int
    let estimatedMinutes: Int
    let relatedId: String?
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

    /// The coaching_multiple_choice tool lets the LLM ask the user structured
    /// multiple-choice questions to gather context before providing coaching
    /// recommendations.
    static func buildCoachingMultipleChoiceTool() -> AnthropicTool {
        let optionSchema: [String: Any] = [
            "type": "object",
            "description": "A single answer option for the question",
            "properties": [
                "value": [
                    "type": "integer",
                    "description": "Numeric value for this option (1-10 scale recommended for motivation, 1-5 for preferences)"
                ],
                "label": [
                    "type": "string",
                    "description": "Display label for this option (keep concise, 2-5 words)"
                ],
                "emoji": [
                    "type": ["string", "null"],
                    "description": "Optional emoji to display with this option for visual appeal"
                ]
            ],
            "required": ["value", "label", "emoji"],
            "additionalProperties": false
        ]

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "question": [
                    "type": "string",
                    "description": "The question to ask the user. Keep it conversational and empathetic."
                ],
                "options": [
                    "type": "array",
                    "description": "2-5 answer options for the user to choose from. Each should be distinct and meaningful.",
                    "items": optionSchema
                ],
                "questionType": [
                    "type": "string",
                    "description": "Category of question to help organize the coaching conversation",
                    "enum": ["motivation", "challenge", "focus", "feedback"]
                ]
            ],
            "required": ["question", "options", "questionType"],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: multipleChoiceToolName,
            description: """
                Present a multiple choice question to the user to understand their current state and needs.
                You MUST call this tool at least twice before providing recommendations.
                Questions should gather information about:
                - Current motivation/energy level for job searching
                - Biggest challenges or blockers they're facing
                - Preferred focus areas for today
                - Feedback on recent activity or strategy

                Design questions that are quick to answer but provide meaningful coaching context.
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

        guard !args.question.isEmpty,
              let questionType = CoachingQuestionType(rawValue: args.questionType) else {
            return nil
        }

        let options = args.options.compactMap { opt -> QuestionOption? in
            guard !opt.label.isEmpty else { return nil }
            return QuestionOption(value: opt.value, label: opt.label, emoji: opt.emoji)
        }

        guard !options.isEmpty else { return nil }

        return CoachingQuestion(
            questionText: args.question,
            options: options,
            questionType: questionType
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

    /// Tool for the LLM to output structured daily tasks at the end of a coaching session
    static func buildUpdateDailyTasksTool() -> AnthropicTool {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "tasks": [
                    "type": "array",
                    "description": "The daily tasks to add. Generate 3-6 tasks based on the coaching conversation.",
                    "items": dailyTaskEntrySchema
                ]
            ],
            "required": ["tasks"],
            "additionalProperties": false
        ]

        return .function(AnthropicFunctionTool(
            name: updateDailyTasksToolName,
            description: """
                Generate the user's daily task list based on the coaching conversation.
                Create 3-6 specific, actionable tasks that align with what was discussed.
                Match task count/complexity to the user's stated energy level.
                Include tasks from multiple categories when appropriate.
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

    // MARK: - Task Regeneration Schema

    /// A single daily-task entry schema, shared by the update_daily_tasks tool
    /// and the task-regeneration structured output.
    private static let dailyTaskEntrySchema: [String: Any] = [
        "type": "object",
        "description": "A single task to add to the user's daily task list",
        "properties": [
            "taskType": [
                "type": "string",
                "description": "The type of task",
                "enum": ["gather", "customize", "apply", "follow_up", "networking", "event_prep", "debrief"]
            ],
            "title": [
                "type": "string",
                "description": "Short, actionable title for the task (2-8 words)"
            ],
            "description": [
                "type": "string",
                "description": "Brief context or details about the task"
            ],
            "priority": [
                "type": "integer",
                "description": "Priority level: 0 (low), 1 (medium), 2 (high)"
            ],
            "estimatedMinutes": [
                "type": "integer",
                "description": "Estimated time in minutes to complete the task"
            ],
            "relatedId": [
                "type": ["string", "null"],
                "description": "UUID of related job app, event, or contact if applicable, otherwise null"
            ]
        ],
        "required": ["taskType", "title", "description", "priority", "estimatedMinutes", "relatedId"],
        "additionalProperties": false
    ]

    /// Schema (dictionary form, for Anthropic structured output) for regenerated
    /// tasks in a specific category based on user feedback.
    static func buildTaskRegenerationSchema() -> [String: Any] {
        [
            "type": "object",
            "description": "Regenerated tasks for a specific category based on user feedback",
            "properties": [
                "tasks": [
                    "type": "array",
                    "description": "The regenerated tasks. Generate 2-5 tasks based on the user's feedback.",
                    "items": dailyTaskEntrySchema
                ],
                "explanation": [
                    "type": "string",
                    "description": "Brief explanation of why these tasks were suggested based on the feedback"
                ]
            ],
            "required": ["tasks", "explanation"],
            "additionalProperties": false
        ]
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
