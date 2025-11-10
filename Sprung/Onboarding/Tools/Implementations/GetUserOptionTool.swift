//
//  GetUserOptionTool.swift
//  Sprung
//
//  Presents a multiple-choice prompt to the user and waits for a selection.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

struct GetUserOptionTool: InterviewTool {
    private static let schema: JSONSchema = {
        let optionProperties: [String: JSONSchema] = [
            "id": JSONSchema(type: .string, description: "Stable identifier for the option"),
            "label": JSONSchema(type: .string, description: "Display label for the option"),
            "description": JSONSchema(type: .string, description: "Optional detailed description"),
            "icon": JSONSchema(type: .string, description: "Optional system icon name")
        ]

        let optionObject = JSONSchema(
            type: .object,
            description: "Single selectable option",
            properties: optionProperties,
            required: ["id", "label"],
            additionalProperties: false
        )

        let properties: [String: JSONSchema] = [
            "prompt": JSONSchema(type: .string, description: "Question or instruction to display"),
            "options": JSONSchema(
                type: .array,
                description: "Array of available options",
                items: optionObject,
                required: nil,
                additionalProperties: false
            ),
            "allowMultiple": JSONSchema(type: .boolean, description: "Allow selecting multiple options"),
            "required": JSONSchema(type: .boolean, description: "Is selection required to continue")
        ]

        return JSONSchema(
            type: .object,
            description: """
                Present a multiple-choice selection card in the tool pane.

                Use this for structured decision points where the user needs to select from predefined options (e.g., "Which contact source do you prefer?", "Which resume sections should we include?").

                RETURNS: { "message": "UI presented. Awaiting user input.", "status": "completed" }

                The tool completes immediately after presenting UI. User selection arrives as a new user message containing selected option IDs.

                USAGE: Use for binary choices (yes/no), small option sets (2-6 items), or when you need structured input rather than free-form chat responses. Provides better UX than asking questions in chat when options are well-defined.

                WORKFLOW:
                1. Call get_user_option with prompt and options
                2. Tool returns immediately - card is now active in tool pane
                3. User selects one or more options (depending on allowMultiple)
                4. You receive user message with selected option IDs
                5. Process selection and continue workflow

                ERROR: Will fail if prompt is empty or options array has fewer than 2 items.
                """,
            properties: properties,
            required: ["prompt", "options"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var name: String { "get_user_option" }
    var description: String { "Present multiple-choice selection card. Returns immediately - selection arrives as user message. Use for structured decisions (2-6 options)." }
    var parameters: JSONSchema { Self.schema }

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        let payload = try OptionPromptPayload(json: params)

        // Emit UI request to show the choice prompt
        await coordinator.eventBus.publish(.choicePromptRequested(prompt: payload.toChoicePrompt()))

        // Return completed - the tool's job is to present UI, which it has done
        // User's selection will arrive as a new user message
        var response = JSON()
        response["message"].string = "UI presented. Awaiting user input."
        response["status"].string = "completed"

        return .immediate(response)
    }
}

private struct OptionPromptPayload {
    struct Option {
        let id: String
        let label: String
        let detail: String?
        let icon: String?

        func toChoiceOption() -> OnboardingChoiceOption {
            OnboardingChoiceOption(id: id, title: label, detail: detail, icon: icon)
        }
    }

    let prompt: String
    let options: [Option]
    let allowMultiple: Bool
    let required: Bool

    init(json: JSON) throws {
        guard let prompt = json["prompt"].string, !prompt.isEmpty else {
            throw ToolError.invalidParameters("prompt must be a non-empty string")
        }
        guard let optionArray = json["options"].array, !optionArray.isEmpty else {
            throw ToolError.invalidParameters("options must contain at least two entries")
        }

        self.prompt = prompt
        self.options = try optionArray.map { optionJSON in
            guard let id = optionJSON["id"].string, !id.isEmpty else {
                throw ToolError.invalidParameters("option id must be a non-empty string")
            }
            guard let label = optionJSON["label"].string, !label.isEmpty else {
                throw ToolError.invalidParameters("option label must be a non-empty string")
            }
            return Option(
                id: id,
                label: label,
                detail: optionJSON["description"].string,
                icon: optionJSON["icon"].string
            )
        }
        self.allowMultiple = json["allowMultiple"].boolValue
        self.required = json["required"].boolValue
    }

    func toChoicePrompt() -> OnboardingChoicePrompt {
        let style: OnboardingSelectionStyle = allowMultiple ? .multiple : .single
        return OnboardingChoicePrompt(
            prompt: prompt,
            options: options.map { $0.toChoiceOption() },
            selectionStyle: style,
            required: required
        )
    }
}
