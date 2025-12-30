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
        let properties: [String: JSONSchema] = [
            "prompt": UserInteractionSchemas.optionPrompt,
            "options": UserInteractionSchemas.optionsArray,
            "allowMultiple": UserInteractionSchemas.allowMultipleOptions,
            "required": UserInteractionSchemas.requiredSelection
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
    var name: String { OnboardingToolName.getUserOption.rawValue }
    var description: String { "Present multiple-choice selection card. Returns immediately - selection arrives as user message. Use for structured decisions (2-6 options)." }
    var parameters: JSONSchema { Self.schema }
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    func execute(_ params: JSON) async throws -> ToolResult {
        let payload = try OptionPromptPayload(json: params)
        // Emit UI request to show the choice prompt
        await coordinator.eventBus.publish(.choicePromptRequested(prompt: payload.toChoicePrompt()))
        // Codex paradigm: Return pending - don't send tool response until user acts.
        // The tool output will be sent when user makes a selection.
        return .pendingUserAction
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
