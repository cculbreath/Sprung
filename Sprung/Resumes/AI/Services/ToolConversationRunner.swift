//
//  ToolConversationRunner.swift
//  Sprung
//
//  Handles tool-enabled LLM conversations for resume customization.
//  Manages the tool execution loop and UI interactions for tool results.
//

import Foundation
import SwiftUI
import SwiftOpenAI
import SwiftyJSON

/// Manages tool-enabled conversations with LLMs.
/// Executes a loop: LLM response → tool calls → tool execution → tool results → repeat.
@MainActor
@Observable
class ToolConversationRunner {
    // MARK: - Dependencies
    private let llm: LLMFacade
    private let toolRegistry: ResumeToolRegistry

    init(llm: LLMFacade, toolRegistry: ResumeToolRegistry? = nil) {
        self.llm = llm
        self.toolRegistry = toolRegistry ?? ResumeToolRegistry()
    }

    // MARK: - Public Interface

    /// Check if tool calling should be used for this model
    func shouldUseTools(modelId: String, openRouterService: OpenRouterService) -> Bool {
        let toolsEnabled = UserDefaults.standard.bool(forKey: "enableResumeCustomizationTools")
        guard toolsEnabled else {
            Logger.debug("🔧 [Tools] Feature flag disabled")
            return false
        }

        let model = openRouterService.findModel(id: modelId)
        let supportsTools = model?.supportsTools ?? false
        Logger.debug("🔧 [Tools] Model \(modelId) supportsTools: \(supportsTools)")
        return supportsTools
    }

    /// Run a tool-enabled conversation with the LLM.
    /// - Parameters:
    ///   - systemPrompt: The system prompt for the conversation
    ///   - userPrompt: The user's message/query
    ///   - modelId: The LLM model to use
    ///   - resume: The resume being customized
    ///   - jobApp: Optional job application context
    ///   - initialToolChoice: Optional tool choice to force for the first turn (reverts to .auto after)
    /// - Returns: The final text response from the LLM after all tool calls are resolved.
    func runConversation(
        systemPrompt: String,
        userPrompt: String,
        modelId: String,
        resume: Resume,
        jobApp: JobApp?,
        initialToolChoice: ToolChoice? = nil
    ) async throws -> String {
        Logger.info("🔧 [Tools] Starting tool-enabled conversation with \(toolRegistry.toolNames.count) tools")
        if let forcedTool = initialToolChoice {
            Logger.info("🔧 [Tools] Initial tool choice forced: \(forcedTool)")
        }

        // Build initial messages
        var messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text(systemPrompt)),
            .init(role: .user, content: .text(userPrompt))
        ]

        // Build tools
        let tools = toolRegistry.buildChatTools()

        // Tool execution loop
        var maxIterations = 10
        var isFirstIteration = true
        while maxIterations > 0 {
            maxIterations -= 1

            // Use initialToolChoice for first iteration only, then switch to .auto
            let currentToolChoice: ToolChoice = (isFirstIteration && initialToolChoice != nil)
                ? initialToolChoice!
                : .auto
            isFirstIteration = false

            let response = try await llm.executeWithTools(
                messages: messages,
                tools: tools,
                toolChoice: currentToolChoice,
                modelId: modelId
            )

            guard let choice = response.choices?.first,
                  let message = choice.message else {
                throw LLMError.clientError("No response from model")
            }

            // Check for tool calls
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                Logger.info("🔧 [Tools] Model requested \(toolCalls.count) tool call(s)")

                // Add assistant message with tool calls to history
                let assistantContent: ChatCompletionParameters.Message.ContentType = message.content.map { .text($0) } ?? .text("")
                messages.append(ChatCompletionParameters.Message(
                    role: .assistant,
                    content: assistantContent,
                    toolCalls: toolCalls
                ))

                // Execute each tool and collect results
                for toolCall in toolCalls {
                    let toolCallId = toolCall.id ?? UUID().uuidString
                    let toolName = toolCall.function.name ?? "unknown"
                    let toolArguments = toolCall.function.arguments

                    Logger.debug("🔧 [Tools] Executing tool: \(toolName)")

                    let context = ResumeToolContext(
                        resume: resume,
                        jobApp: jobApp
                    )

                    let result = try await toolRegistry.executeTool(
                        name: toolName,
                        arguments: toolArguments,
                        context: context
                    )

                    // Handle the result
                    let resultString = processToolResult(result)

                    // Add tool result message
                    messages.append(ChatCompletionParameters.Message(
                        role: .tool,
                        content: .text(resultString),
                        toolCallID: toolCallId
                    ))
                }
            } else {
                // No tool calls - return the final response
                let finalContent = message.content ?? ""
                Logger.info("🔧 [Tools] Conversation complete, returning final response")
                return finalContent
            }
        }

        throw LLMError.clientError("Tool execution exceeded maximum iterations")
    }

    // MARK: - Private Helpers

    /// Process a tool result into a string for the LLM
    private func processToolResult(_ result: ResumeToolResult) -> String {
        switch result {
        case .immediate(let json):
            return json.rawString() ?? "{}"

        case .error(let errorMessage):
            return """
            {"error": "\(errorMessage)"}
            """
        }
    }
}

// MARK: - Response Parsing

extension ToolConversationRunner {
    /// Parse revisions from a raw LLM response string
    func parseRevisionsFromResponse(_ response: String) throws -> RevisionsContainer {
        do {
            return try JSONResponseParser.parseFlexibleFromText(response, as: RevisionsContainer.self)
        } catch {
            // LLM may return a bare array instead of a container object
            let revisions = try JSONResponseParser.parseFlexibleFromText(response, as: [ProposedRevisionNode].self)
            return RevisionsContainer(revArray: revisions)
        }
    }
}
