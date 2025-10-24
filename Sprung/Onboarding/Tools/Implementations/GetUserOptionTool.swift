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
            description: "Parameters for the get_user_option tool",
            properties: properties,
            required: ["prompt", "options"],
            additionalProperties: false
        )
    }()

    private let service: OnboardingInterviewService
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var name: String { "get_user_option" }
    var description: String { "Present a multiple choice prompt to the user and return the selected option identifiers." }
    var parameters: JSONSchema { Self.schema }

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        let payload = try OptionPromptPayload(json: params)
        let tokenId = UUID()

        await service.presentChoicePrompt(
            prompt: payload.toChoicePrompt(),
            continuationId: tokenId
        )

        let token = ContinuationToken(
            id: tokenId,
            toolName: name,
            resumeHandler: { input in
                await service.clearChoicePrompt(continuationId: tokenId)

                if input["cancelled"].boolValue {
                    return .error(.userCancelled)
                }

                guard let selectedArray = input["selectedIds"].arrayObject as? [String], !selectedArray.isEmpty else {
                    return .error(.invalidParameters("selectedIds must be a non-empty array of strings"))
                }

                var response = JSON()
                response["selectedIds"] = JSON(selectedArray)
                response["timestamp"].string = dateFormatter.string(from: Date())
                return .immediate(response)
            }
        )

        return .waiting(message: "Waiting for user selection", continuation: token)
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

