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

    // MARK: - Complete Tool Definitions

    /// Returns the question tool only (for forced tool choice)
    static let questionTool: [ChatCompletionParameters.Tool] = [
        buildCoachingMultipleChoiceTool()
    ]

    /// Returns all coaching tools including background research tools
    static let allTools: [ChatCompletionParameters.Tool] = [
        buildCoachingMultipleChoiceTool(),
        buildGetKnowledgeCardTool(),
        buildGetJobDescriptionTool(),
        buildGetResumeTool()
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

    /// Parse a tool call response into a CoachingQuestion
    static func parseQuestion(from arguments: [String: Any]) -> CoachingQuestion? {
        guard let questionText = arguments["question"] as? String,
              let optionsArray = arguments["options"] as? [[String: Any]],
              let questionTypeRaw = arguments["question_type"] as? String,
              let questionType = CoachingQuestionType(rawValue: questionTypeRaw) else {
            return nil
        }

        let options = optionsArray.compactMap { optionDict -> QuestionOption? in
            guard let value = optionDict["value"] as? Int,
                  let label = optionDict["label"] as? String else {
                return nil
            }
            let emoji = optionDict["emoji"] as? String
            return QuestionOption(value: value, label: label, emoji: emoji)
        }

        guard !options.isEmpty else { return nil }

        return CoachingQuestion(
            questionText: questionText,
            options: options,
            questionType: questionType
        )
    }

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
                    description: "Optional: start line number for a specific excerpt (1-indexed)"
                ),
                "end_line": JSONSchema(
                    type: .optional(.integer),
                    description: "Optional: end line number for a specific excerpt"
                )
            ],
            required: ["card_id"],
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
                    description: "Optional: specific section to retrieve (summary, work, skills, etc.)"
                )
            ],
            required: ["resume_id"],
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
}
