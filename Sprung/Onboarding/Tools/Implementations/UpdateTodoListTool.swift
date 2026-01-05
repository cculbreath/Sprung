//
//  UpdateTodoListTool.swift
//  Sprung
//
//  Allows the LLM to manage its own todo list for tracking interview progress.
//  The LLM provides the complete updated list each time (full replacement).
//  Current state is visible to the LLM via <todo-list> tags in the system prompt.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct UpdateTodoListTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Update your todo list to track interview progress. Use this tool to plan tasks, \
                mark items in progress, and check off completed work. The current todo list is \
                shown in <todo-list> tags in your context.

                USAGE:
                - At phase start: Create todos for required steps (e.g., "Request profile photo", "Collect writing samples")
                - Before starting work: Mark the relevant item as "in_progress"
                - After completing work: Mark the item as "completed"
                - Add new items as you discover additional tasks

                IMPORTANT:
                - Provide the COMPLETE updated list each time (this replaces the current list)
                - Each item needs: content (what to do), status (pending/in_progress/completed)
                - Optional: activeForm (present-tense description shown when in_progress)
                - Only ONE item should be "in_progress" at a time
                """,
            properties: [
                "todos": JSONSchema(
                    type: .array,
                    description: "The complete updated todo list (replaces current list)",
                    items: JSONSchema(
                        type: .object,
                        properties: [
                            "content": JSONSchema(
                                type: .string,
                                description: "What needs to be done (imperative form, e.g., 'Collect writing samples')"
                            ),
                            "status": JSONSchema(
                                type: .string,
                                description: "Current status: pending (not started), in_progress (working on it), completed (done)",
                                enum: ["pending", "in_progress", "completed"]
                            ),
                            "activeForm": JSONSchema(
                                type: .string,
                                description: "Optional: Present-tense form shown when in_progress (e.g., 'Collecting writing samples')"
                            )
                        ],
                        required: ["content", "status"]
                    )
                )
            ],
            required: ["todos"],
            additionalProperties: false
        )
    }()

    private let todoStore: InterviewTodoStore

    init(todoStore: InterviewTodoStore) {
        self.todoStore = todoStore
    }

    var name: String { OnboardingToolName.updateTodoList.rawValue }

    var description: String {
        "Update your todo list to track interview progress. Provide the complete updated list."
    }

    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let todosArray = params["todos"].array else {
            throw ToolError.invalidParameters("todos array is required")
        }

        var newItems: [InterviewTodoItem] = []

        for todoJson in todosArray {
            guard let content = todoJson["content"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                throw ToolError.invalidParameters("Each todo item must have non-empty 'content'")
            }

            guard let statusString = todoJson["status"].string,
                  let status = InterviewTodoStatus(rawValue: statusString) else {
                throw ToolError.invalidParameters("Each todo item must have valid 'status' (pending, in_progress, completed)")
            }

            let activeForm = todoJson["activeForm"].string?.trimmingCharacters(in: .whitespacesAndNewlines)

            newItems.append(InterviewTodoItem(
                content: content,
                status: status,
                activeForm: activeForm?.isEmpty == false ? activeForm : nil
            ))
        }

        // Update the store with the new list
        await todoStore.setItems(newItems)

        // Return success
        var output = JSON()
        output["status"].string = "completed"
        output["message"].string = "Todo list updated with \(newItems.count) item(s)"

        return .immediate(output)
    }
}
