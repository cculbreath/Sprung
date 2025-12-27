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

    // MARK: - Complete Tool Definitions

    /// Returns all coaching tools as ChatCompletionParameters.Tool objects
    static let allTools: [ChatCompletionParameters.Tool] = [
        buildCoachingMultipleChoiceTool()
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
}
