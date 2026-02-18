//
//  LLMFacadeOpenAIToolsAdapter.swift
//  Sprung
//
//  Translates tool-calling requests (in ChatCompletion format) to the OpenAI
//  Responses API and converts the result back to ChatCompletionObject.
//  Extracted from LLMFacade for single responsibility.
//

import Foundation
import SwiftOpenAI

/// Translates tool-calling requests (in ChatCompletion format) to the OpenAI
/// Responses API and converts the result back to ChatCompletionObject.
@MainActor
struct LLMFacadeOpenAIToolsAdapter {
    private let specializedAPIs: LLMFacadeSpecializedAPIs

    init(specializedAPIs: LLMFacadeSpecializedAPIs) {
        self.specializedAPIs = specializedAPIs
    }

    func execute(
        messages: [ChatCompletionParameters.Message],
        tools: [ChatCompletionParameters.Tool],
        toolChoice: ToolChoice?,
        modelId: String,
        reasoningEffort: String?
    ) async throws -> ChatCompletionObject {
        let openAIModelId = modelId.hasPrefix("openai/") ? String(modelId.dropFirst(7)) : modelId

        var inputItems: [InputItem] = []
        for message in messages {
            let role: String
            switch message.role {
            case "system": role = "developer"
            case "user": role = "user"
            case "assistant": role = "assistant"
            case "tool": role = "user"
            default: role = "user"
            }

            switch message.content {
            case .text(let text):
                inputItems.append(.message(InputMessage(role: role, content: .text(text))))
            case .contentArray:
                break
            }
        }

        let responsesTools: [Tool] = tools.compactMap { chatTool in
            let function = chatTool.function
            return Tool.function(Tool.FunctionTool(
                name: function.name,
                parameters: function.parameters ?? JSONSchema(type: .object),
                strict: function.strict,
                description: function.description
            ))
        }

        let responsesToolChoice: ToolChoiceMode?
        if let choice = toolChoice {
            switch choice {
            case .auto: responsesToolChoice = .auto
            case .none: responsesToolChoice = ToolChoiceMode.none
            case .required: responsesToolChoice = .required
            case .function(_, let name): responsesToolChoice = .functionTool(FunctionTool(name: name))
            }
        } else {
            responsesToolChoice = nil
        }

        let reasoning: Reasoning? = reasoningEffort.map { Reasoning(effort: $0) }

        let parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(openAIModelId),
            reasoning: reasoning,
            store: true,
            toolChoice: responsesToolChoice,
            tools: responsesTools.isEmpty ? nil : responsesTools
        )

        let stream = try await specializedAPIs.responseCreateStream(parameters: parameters)
        var finalResponse: ResponseModel?
        for try await event in stream {
            if case .responseCompleted(let completed) = event {
                finalResponse = completed.response
            }
        }
        guard let response = finalResponse else {
            throw LLMError.clientError("No response received from OpenAI")
        }
        return try convertResponseToCompletion(response)
    }

    private func convertResponseToCompletion(_ response: ResponseModel) throws -> ChatCompletionObject {
        var toolCallsArray: [[String: Any]] = []
        var content: String?

        for item in response.output {
            switch item {
            case .message(let message):
                for contentItem in message.content {
                    if case let .outputText(textOutput) = contentItem {
                        content = textOutput.text
                    }
                }
            case .functionCall(let functionCall):
                toolCallsArray.append([
                    "id": functionCall.callId,
                    "type": "function",
                    "function": [
                        "arguments": functionCall.arguments,
                        "name": functionCall.name
                    ]
                ])
            default:
                break
            }
        }

        var messageDict: [String: Any] = ["role": "assistant"]
        if let content = content { messageDict["content"] = content }
        if !toolCallsArray.isEmpty { messageDict["tool_calls"] = toolCallsArray }

        let json: [String: Any] = [
            "id": response.id,
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": response.model,
            "choices": [[
                "index": 0,
                "message": messageDict,
                "finish_reason": toolCallsArray.isEmpty ? "stop" : "tool_calls"
            ]]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(ChatCompletionObject.self, from: jsonData)
    }
}
