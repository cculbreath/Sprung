//
//  CoachingToolSchemas.swift
//  Sprung
//
//  JSON schemas for Job Search Coach LLM tools.
//  Defines the coaching_multiple_choice tool that allows the LLM
//  to ask the user structured questions during coaching sessions.
//

import Foundation
import SwiftOpenAI

// MARK: - Tool Argument Codable Structs

struct CoachingMultipleChoiceArgs: Codable {
    let question: String
    let options: [CoachingMultipleChoiceOptionArgs]
    let questionType: String

    enum CodingKeys: String, CodingKey {
        case question
        case options
        case questionType = "question_type"
    }
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

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case startLine = "start_line"
        case endLine = "end_line"
    }
}

struct GetJobDescriptionArgs: Codable {
    let jobAppId: String

    enum CodingKeys: String, CodingKey {
        case jobAppId = "job_app_id"
    }
}

struct GetResumeArgs: Codable {
    let resumeId: String
    let section: String?

    enum CodingKeys: String, CodingKey {
        case resumeId = "resume_id"
        case section
    }
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

    enum CodingKeys: String, CodingKey {
        case taskType = "task_type"
        case title
        case description
        case priority
        case estimatedMinutes = "estimated_minutes"
        case relatedId = "related_id"
    }
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

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case title, type, organization
        case dateRange = "date_range"
        case content
        case wordCount = "word_count"
    }
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

    enum CodingKeys: String, CodingKey {
        case jobAppId = "job_app_id"
        case company, position, status
        case jobDescription = "job_description"
        case jobUrl = "job_url"
        case notes
        case appliedDate = "applied_date"
    }
}

struct CoachingResumeToolResult: Encodable {
    let resumeId: String
    let template: String
    let section: String?
    let content: String?
    let availableSections: [String]?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case resumeId = "resume_id"
        case template, section, content
        case availableSections = "available_sections"
        case summary
    }
}

struct ChooseBestJobsToolResult: Encodable {
    let success: Bool
    let selectedCount: Int?
    let identifiedCount: Int?
    let selections: [ChooseBestJobsSelectionResult]?
    let overallAnalysis: String?
    let considerations: [String]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case selectedCount = "selected_count"
        case identifiedCount = "identified_count"
        case selections
        case overallAnalysis = "overall_analysis"
        case considerations
        case error
    }
}

struct ChooseBestJobsSelectionResult: Encodable {
    let company: String
    let role: String
    let matchScore: Double
    let reasoning: String

    enum CodingKeys: String, CodingKey {
        case company, role
        case matchScore = "match_score"
        case reasoning
    }
}

struct ToolAnswerResult: Encodable {
    let selectedValue: Int
    let selectedLabel: String

    enum CodingKeys: String, CodingKey {
        case selectedValue = "selected_value"
        case selectedLabel = "selected_label"
    }
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

    /// Returns all coaching tools including background research tools
    static let allTools: [ChatCompletionParameters.Tool] = [
        buildCoachingMultipleChoiceTool(),
        buildGetKnowledgeCardTool(),
        buildGetJobDescriptionTool(),
        buildGetResumeTool(),
        buildUpdateDailyTasksTool(),
        buildChooseBestJobsTool()
    ]

    // MARK: - Multiple Choice Question Tool

    /// Build the coaching_multiple_choice tool schema
    /// This tool allows the LLM to ask the user structured multiple-choice questions
    /// to gather context before providing coaching recommendations.
    static func buildCoachingMultipleChoiceTool() -> ChatCompletionParameters.Tool {
        let optionSchema = JSONSchema(
            type: .object,
            description: "A single answer option for the question",
            properties: [
                "value": JSONSchema(
                    type: .integer,
                    description: "Numeric value for this option (1-10 scale recommended for motivation, 1-5 for preferences)"
                ),
                "label": JSONSchema(
                    type: .string,
                    description: "Display label for this option (keep concise, 2-5 words)"
                ),
                "emoji": JSONSchema(
                    type: .optional(.string),
                    description: "Optional emoji to display with this option for visual appeal"
                )
            ],
            required: ["value", "label", "emoji"],
            additionalProperties: false
        )

        let schema = JSONSchema(
            type: .object,
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
            properties: [
                "question": JSONSchema(
                    type: .string,
                    description: "The question to ask the user. Keep it conversational and empathetic."
                ),
                "options": JSONSchema(
                    type: .array,
                    description: "2-5 answer options for the user to choose from. Each should be distinct and meaningful.",
                    items: optionSchema
                ),
                "question_type": JSONSchema(
                    type: .string,
                    description: "Category of question to help organize the coaching conversation",
                    enum: ["motivation", "challenge", "focus", "feedback"]
                )
            ],
            required: ["question", "options", "question_type"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: multipleChoiceToolName,
                strict: true,
                description: "Ask the user a multiple choice question to gather coaching context",
                parameters: schema
            )
        )
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
    static func buildGetKnowledgeCardTool() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Retrieve detailed content from a user's knowledge card. Use this to learn more about
                specific work experience, skills, or projects. You can request specific line ranges
                for targeted information.
                """,
            properties: [
                "card_id": JSONSchema(
                    type: .string,
                    description: "The ID of the knowledge card to retrieve (from the available cards list)"
                ),
                "start_line": JSONSchema(
                    type: .optional(.integer),
                    description: "Start line number for a specific excerpt (1-indexed), or null for full content"
                ),
                "end_line": JSONSchema(
                    type: .optional(.integer),
                    description: "End line number for a specific excerpt, or null for full content"
                )
            ],
            required: ["card_id", "start_line", "end_line"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: getKnowledgeCardToolName,
                strict: true,
                description: "Get detailed content from a knowledge card about the user's experience",
                parameters: schema
            )
        )
    }

    // MARK: - Job Description Tool

    /// Tool to retrieve job description details for a specific job application
    static func buildGetJobDescriptionTool() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Retrieve the job description and details for a specific job application.
                Use this to understand what the user is applying for and provide targeted coaching.
                """,
            properties: [
                "job_app_id": JSONSchema(
                    type: .string,
                    description: "The UUID of the job application to retrieve details for"
                )
            ],
            required: ["job_app_id"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: getJobDescriptionToolName,
                strict: true,
                description: "Get job description and details for a specific application",
                parameters: schema
            )
        )
    }

    // MARK: - Resume Tool

    /// Tool to retrieve resume content for a specific resume
    static func buildGetResumeTool() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Retrieve the content of a specific resume. Use this to understand what
                materials the user has prepared and provide feedback or suggestions.
                """,
            properties: [
                "resume_id": JSONSchema(
                    type: .string,
                    description: "The UUID of the resume to retrieve"
                ),
                "section": JSONSchema(
                    type: .optional(.string),
                    description: "Specific section to retrieve (summary, work, skills, etc.), or null for overview"
                )
            ],
            required: ["resume_id", "section"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: getResumeToolName,
                strict: true,
                description: "Get content from a specific resume",
                parameters: schema
            )
        )
    }

    // MARK: - Update Daily Tasks Tool

    /// Tool for the LLM to output structured daily tasks at the end of a coaching session
    static func buildUpdateDailyTasksTool() -> ChatCompletionParameters.Tool {
        let taskSchema = JSONSchema(
            type: .object,
            description: "A single task to add to the user's daily task list",
            properties: [
                "task_type": JSONSchema(
                    type: .string,
                    description: "The type of task",
                    enum: ["gather", "customize", "apply", "follow_up", "networking", "event_prep", "debrief"]
                ),
                "title": JSONSchema(
                    type: .string,
                    description: "Short, actionable title for the task (2-8 words)"
                ),
                "description": JSONSchema(
                    type: .string,
                    description: "Brief context or details about the task"
                ),
                "priority": JSONSchema(
                    type: .integer,
                    description: "Priority level: 0 (low), 1 (medium), 2 (high)"
                ),
                "estimated_minutes": JSONSchema(
                    type: .integer,
                    description: "Estimated time in minutes to complete the task"
                ),
                "related_id": JSONSchema(
                    type: .optional(.string),
                    description: "UUID of related job app, event, or contact if applicable, otherwise null"
                )
            ],
            required: ["task_type", "title", "description", "priority", "estimated_minutes", "related_id"],
            additionalProperties: false
        )

        let schema = JSONSchema(
            type: .object,
            description: """
                Generate the user's daily task list based on the coaching conversation.
                Create 3-6 specific, actionable tasks that align with what was discussed.
                Match task count/complexity to the user's stated energy level.
                Include tasks from multiple categories when appropriate.
                """,
            properties: [
                "tasks": JSONSchema(
                    type: .array,
                    description: "The daily tasks to add. Generate 3-6 tasks based on the coaching conversation.",
                    items: taskSchema
                )
            ],
            required: ["tasks"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: updateDailyTasksToolName,
                strict: true,
                description: "Set the user's daily task list based on the coaching session",
                parameters: schema
            )
        )
    }

    // MARK: - Choose Best Jobs Tool

    /// Tool to trigger the job selection workflow that identifies and advances top job opportunities
    static func buildChooseBestJobsTool() -> ChatCompletionParameters.Tool {
        let schema = JSONSchema(
            type: .object,
            description: """
                Analyze all jobs in the Identified stage and select the best matches for the user.
                This triggers the job selection workflow that:
                1. Evaluates all pending job leads against the user's knowledge cards and dossier
                2. Scores and ranks jobs by fit
                3. Advances the top matches to Researching stage
                Use this when the user has accumulated job leads and is ready to focus their efforts.
                """,
            properties: [
                "count": JSONSchema(
                    type: .integer,
                    description: "Number of top jobs to select (1-10, default 5)"
                ),
                "reason": JSONSchema(
                    type: .string,
                    description: "Brief explanation of why you're triggering job selection now"
                )
            ],
            required: ["count", "reason"],
            additionalProperties: false
        )

        return ChatCompletionParameters.Tool(
            function: ChatCompletionParameters.ChatFunction(
                name: chooseBestJobsToolName,
                strict: true,
                description: "Analyze identified jobs and advance best matches to Researching stage",
                parameters: schema
            )
        )
    }

    // MARK: - Task Regeneration Schema

    /// Schema for structured task output during regeneration
    static func buildTaskRegenerationSchema() -> JSONSchema {
        let taskSchema = JSONSchema(
            type: .object,
            description: "A single task to add to the user's daily task list",
            properties: [
                "task_type": JSONSchema(
                    type: .string,
                    description: "The type of task",
                    enum: ["gather", "customize", "apply", "follow_up", "networking", "event_prep", "debrief"]
                ),
                "title": JSONSchema(
                    type: .string,
                    description: "Short title for the task (2-8 words)"
                ),
                "description": JSONSchema(
                    type: .string,
                    description: "Brief context or details about the task"
                ),
                "priority": JSONSchema(
                    type: .integer,
                    description: "Priority level: 0 (low), 1 (medium), 2 (high)"
                ),
                "estimated_minutes": JSONSchema(
                    type: .integer,
                    description: "Estimated time in minutes to complete the task"
                ),
                "related_id": JSONSchema(
                    type: .optional(.string),
                    description: "UUID of related job app, event, or contact if applicable, otherwise null"
                )
            ],
            required: ["task_type", "title", "description", "priority", "estimated_minutes", "related_id"],
            additionalProperties: false
        )

        return JSONSchema(
            type: .object,
            description: "Regenerated tasks for a specific category based on user feedback",
            properties: [
                "tasks": JSONSchema(
                    type: .array,
                    description: "The regenerated tasks. Generate 2-5 tasks based on the user's feedback.",
                    items: taskSchema
                ),
                "explanation": JSONSchema(
                    type: .string,
                    description: "Brief explanation of why these tasks were suggested based on the feedback"
                )
            ],
            required: ["tasks", "explanation"],
            additionalProperties: false
        )
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
