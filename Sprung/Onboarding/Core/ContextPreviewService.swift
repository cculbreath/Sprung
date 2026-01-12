//
//  ContextPreviewService.swift
//  Sprung
//
//  Builds a preview of the conversation context that would be sent to the LLM.
//  Used for debugging to understand token usage and context composition.
//

import Foundation
import SwiftOpenAI

// MARK: - Context Preview Models

/// A single item in the context preview
struct ContextPreviewItem: Identifiable {
    let id = UUID()
    let type: ContextItemType
    let label: String
    let content: String
    let estimatedTokens: Int
    let byteSize: Int

    enum ContextItemType: String {
        case systemPrompt = "System"
        case userMessage = "User"
        case assistantMessage = "Assistant"
        case toolCall = "Tool Call"
        case toolResult = "Tool Result"
        case interviewContext = "Context"
        case coordinator = "Coordinator"
        case document = "Document"
    }
}

/// Complete context preview snapshot
struct ContextPreviewSnapshot {
    let timestamp: Date
    let items: [ContextPreviewItem]
    let toolCount: Int
    let toolSchemaTokens: Int

    var totalEstimatedTokens: Int {
        items.reduce(0) { $0 + $1.estimatedTokens } + toolSchemaTokens
    }

    var totalBytes: Int {
        items.reduce(0) { $0 + $1.byteSize }
    }
}

// MARK: - Context Preview Service

/// Service that builds a preview of the conversation context
@MainActor
final class ContextPreviewService {
    private let stateCoordinator: StateCoordinator
    private let phaseRegistry: PhaseScriptRegistry
    private let toolRegistry: ToolRegistry
    private let todoStore: InterviewTodoStore

    init(
        stateCoordinator: StateCoordinator,
        phaseRegistry: PhaseScriptRegistry,
        toolRegistry: ToolRegistry,
        todoStore: InterviewTodoStore
    ) {
        self.stateCoordinator = stateCoordinator
        self.phaseRegistry = phaseRegistry
        self.toolRegistry = toolRegistry
        self.todoStore = todoStore
    }

    // MARK: - Preview Generation

    /// Build a complete context preview snapshot
    func buildPreview() async -> ContextPreviewSnapshot {
        var items: [ContextPreviewItem] = []

        // 1. System prompt
        let phase = await stateCoordinator.phase
        var systemPrompt = phaseRegistry.buildSystemPrompt(for: phase)

        // Add todo list if present (same as AnthropicRequestBuilder does)
        if let todoList = await todoStore.renderForSystemPrompt() {
            systemPrompt += "\n\n" + todoList
            systemPrompt += "\n\nUse the update_todo_list tool to manage your task list. Mark items in_progress before starting work, and completed when done."
        }

        items.append(ContextPreviewItem(
            type: .systemPrompt,
            label: "System Prompt",
            content: systemPrompt,
            estimatedTokens: estimateTokens(systemPrompt),
            byteSize: systemPrompt.utf8.count
        ))

        // 2. Build interview context (what would be prepended to user messages)
        let workingMemoryBuilder = WorkingMemoryBuilder(stateCoordinator: stateCoordinator)
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            items.append(ContextPreviewItem(
                type: .interviewContext,
                label: "Interview Context (prepended to next user message)",
                content: interviewContext,
                estimatedTokens: estimateTokens(interviewContext),
                byteSize: interviewContext.utf8.count
            ))
        }

        // 3. Conversation history
        let messages = await stateCoordinator.messages
        for message in messages {
            let role = message.role
            let text = message.text

            switch role {
            case .user:
                items.append(ContextPreviewItem(
                    type: .userMessage,
                    label: "User",
                    content: text,
                    estimatedTokens: estimateTokens(text),
                    byteSize: text.utf8.count
                ))

            case .assistant:
                if !text.isEmpty {
                    items.append(ContextPreviewItem(
                        type: .assistantMessage,
                        label: "Assistant",
                        content: text,
                        estimatedTokens: estimateTokens(text),
                        byteSize: text.utf8.count
                    ))
                }

                // Include tool calls
                if let toolCalls = message.toolCalls {
                    for toolCall in toolCalls {
                        let callContent = "\(toolCall.name)(\(toolCall.arguments))"
                        items.append(ContextPreviewItem(
                            type: .toolCall,
                            label: "Tool: \(toolCall.name)",
                            content: callContent,
                            estimatedTokens: estimateTokens(callContent),
                            byteSize: callContent.utf8.count
                        ))

                        if let result = toolCall.result {
                            items.append(ContextPreviewItem(
                                type: .toolResult,
                                label: "Result: \(toolCall.name)",
                                content: result,
                                estimatedTokens: estimateTokens(result),
                                byteSize: result.utf8.count
                            ))
                        }
                    }
                }

            case .system, .systemNote:
                // System messages and notes are not included in LLM history
                break
            }
        }

        // 4. Tool schemas
        let tools = toolRegistry.allTools()
        let toolSchemaTokens = estimateToolSchemaTokens(tools)

        return ContextPreviewSnapshot(
            timestamp: Date(),
            items: items,
            toolCount: tools.count,
            toolSchemaTokens: toolSchemaTokens
        )
    }

    // MARK: - Token Estimation

    /// Estimate tokens for a string using character-based approximation
    /// Claude tokenization averages roughly 4 characters per token for English text
    private func estimateTokens(_ text: String) -> Int {
        // More accurate estimation:
        // - English prose: ~4 chars/token
        // - Code/JSON: ~3 chars/token (more special characters)
        // - XML/markup: ~3.5 chars/token
        // We use a conservative 3.5 average
        let charCount = text.count
        return max(1, Int(ceil(Double(charCount) / 3.5)))
    }

    /// Estimate tokens for tool schemas
    private func estimateToolSchemaTokens(_ tools: [InterviewTool]) -> Int {
        var totalChars = 0
        for tool in tools {
            // Tool name + description
            totalChars += tool.name.count
            totalChars += tool.description.count

            // Schema as JSON - JSONSchema encodes to JSON
            if let schemaData = try? JSONEncoder().encode(tool.parameters),
               let schemaString = String(data: schemaData, encoding: .utf8) {
                totalChars += schemaString.count
            } else {
                // Fallback estimate for schema
                totalChars += 200
            }
        }

        // Tool schemas are JSON-heavy, use 3 chars/token
        return max(1, Int(ceil(Double(totalChars) / 3.0)))
    }
}
