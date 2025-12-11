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

    // MARK: - UI State for Tool Interactions
    var showSkillExperiencePicker: Bool = false
    var pendingSkillQueries: [SkillQuery] = []
    private var skillUIResponseContinuation: CheckedContinuation<ResumeToolUIResponse, Never>?

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
    /// - Returns: The final text response from the LLM after all tool calls are resolved.
    func runConversation(
        systemPrompt: String,
        userPrompt: String,
        modelId: String,
        resume: Resume,
        jobApp: JobApp?
    ) async throws -> String {
        Logger.info("🔧 [Tools] Starting tool-enabled conversation with \(toolRegistry.toolNames.count) tools")

        // Build initial messages
        var messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text(systemPrompt)),
            .init(role: .user, content: .text(userPrompt))
        ]

        // Build tools
        let tools = toolRegistry.buildChatTools()

        // Tool execution loop
        var maxIterations = 10
        while maxIterations > 0 {
            maxIterations -= 1

            let response = try await llm.executeWithTools(
                messages: messages,
                tools: tools,
                toolChoice: .auto,
                modelId: modelId,
                temperature: 0.7
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
                        jobApp: jobApp,
                        presentUI: { [weak self] request in
                            await self?.handleToolUIRequest(request) ?? .cancelled
                        }
                    )

                    let result = try await toolRegistry.executeTool(
                        name: toolName,
                        arguments: toolArguments,
                        context: context
                    )

                    // Handle the result
                    let resultString = await processToolResult(result)

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

    /// Submit skill experience results from the UI
    func submitSkillExperienceResults(_ results: [SkillExperienceResult]) {
        showSkillExperiencePicker = false
        pendingSkillQueries = []
        skillUIResponseContinuation?.resume(returning: .skillExperienceResults(results))
        skillUIResponseContinuation = nil
    }

    /// Cancel the skill experience query
    func cancelSkillExperienceQuery() {
        showSkillExperiencePicker = false
        pendingSkillQueries = []
        skillUIResponseContinuation?.resume(returning: .cancelled)
        skillUIResponseContinuation = nil
    }

    // MARK: - Private Helpers

    /// Handle UI request from a tool by presenting the appropriate UI and waiting for response
    private func handleToolUIRequest(_ request: ResumeToolUIRequest) async -> ResumeToolUIResponse {
        switch request {
        case .skillExperiencePicker(let skills):
            return await presentSkillExperiencePicker(skills)
        }
    }

    /// Present the skill experience picker and wait for user response
    private func presentSkillExperiencePicker(_ skills: [SkillQuery]) async -> ResumeToolUIResponse {
        return await withCheckedContinuation { continuation in
            self.skillUIResponseContinuation = continuation
            self.pendingSkillQueries = skills
            self.showSkillExperiencePicker = true
        }
    }

    /// Process a tool result into a string for the LLM
    private func processToolResult(_ result: ResumeToolResult) async -> String {
        switch result {
        case .immediate(let json):
            return json.rawString() ?? "{}"

        case .pendingUserAction(let uiRequest):
            let uiResponse = await handleToolUIRequest(uiRequest)
            switch uiResponse {
            case .skillExperienceResults(let results):
                return QueryUserExperienceLevelTool.formatResults(results)
            case .cancelled:
                return QueryUserExperienceLevelTool.formatCancellation()
            }

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
        // Try to extract JSON from the response
        // The response may contain markdown code blocks or just raw JSON
        let jsonString: String
        if let jsonStart = response.range(of: "["),
           let jsonEnd = response.range(of: "]", options: .backwards) {
            // Extract the JSON array portion
            jsonString = String(response[jsonStart.lowerBound...jsonEnd.upperBound])
        } else if let jsonStart = response.range(of: "{"),
                  let jsonEnd = response.range(of: "}", options: .backwards) {
            // Try object format (the container might be an object with revArray)
            jsonString = String(response[jsonStart.lowerBound...jsonEnd.upperBound])
        } else {
            jsonString = response
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw LLMError.clientError("Failed to convert response to data")
        }

        // Try to decode as RevisionsContainer first
        do {
            return try JSONDecoder().decode(RevisionsContainer.self, from: data)
        } catch {
            // Try to decode as an array of revisions directly
            do {
                let revisions = try JSONDecoder().decode([ProposedRevisionNode].self, from: data)
                return RevisionsContainer(revArray: revisions)
            } catch {
                Logger.error("Failed to parse revisions from response: \(error.localizedDescription)")
                Logger.debug("Response was: \(response.prefix(500))...")
                throw LLMError.clientError("Failed to parse revision response: \(error.localizedDescription)")
            }
        }
    }
}
