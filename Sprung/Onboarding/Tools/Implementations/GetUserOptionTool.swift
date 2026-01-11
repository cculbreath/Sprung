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
            properties: properties,
            required: ["prompt", "options"],
            additionalProperties: false
        )
    }()
    private weak var coordinator: OnboardingInterviewCoordinator?
    var name: String { OnboardingToolName.getUserOption.rawValue }
    var description: String {
        """
        Present a multiple-choice selection card in the tool pane. Use for structured decision points \
        (e.g., "Which contact source?", "Which sections to include?"). \
        RETURNS: { "message": "UI presented...", "status": "completed" } - completes immediately, \
        user selection arrives as new message with selected option IDs. \
        Use for binary choices, small option sets (2-6 items), or when structured input beats free-form chat. \
        ERROR: Fails if prompt empty or options < 2.
        """
    }
    var parameters: JSONSchema { Self.schema }
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        let payload = try OptionPromptPayload(json: params)
        // Emit UI request to show the choice prompt
        await coordinator.eventBus.publish(.toolpane(.choicePromptRequested(prompt: payload.toChoicePrompt())))
        // Block until user completes the action or interrupts
        let result = await coordinator.uiToolContinuationManager.awaitUserAction(toolName: name)
        return .immediate(result.toJSON())
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
