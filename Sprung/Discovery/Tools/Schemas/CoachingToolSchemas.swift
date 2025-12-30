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
import SwiftyJSON

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

    /// Parse a tool call response from SwiftyJSON
    static func parseQuestionFromJSON(_ json: SwiftyJSON.JSON) -> CoachingQuestion? {
        let questionText = json["question"].stringValue
        let questionTypeRaw = json["question_type"].stringValue

        guard !questionText.isEmpty,
              let questionType = CoachingQuestionType(rawValue: questionTypeRaw) else {
            return nil
        }

        let options = json["options"].arrayValue.compactMap { optionJSON -> QuestionOption? in
            let value = optionJSON["value"].intValue
            let label = optionJSON["label"].stringValue
            guard !label.isEmpty else { return nil }
            let emoji = optionJSON["emoji"].string
            return QuestionOption(value: value, label: label, emoji: emoji)
        }

        guard !options.isEmpty else { return nil }

        return CoachingQuestion(
            questionText: questionText,
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
