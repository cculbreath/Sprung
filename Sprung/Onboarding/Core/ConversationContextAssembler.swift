//
//  ConversationContextAssembler.swift
//  Sprung
//
//  Phase 3: Rolling conversation context with state cues
//  Assembles conversation history + current state for LLM requests
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

/// Assembles conversation context for LLM requests
/// Includes rolling message window + state cues (allowed tools, objectives, phase)
actor ConversationContextAssembler {
    // MARK: - Properties

    private let state: StateCoordinator
    private let maxConversationTurns: Int

    // MARK: - Initialization

    init(state: StateCoordinator, maxConversationTurns: Int = 8) {
        self.state = state
        self.maxConversationTurns = maxConversationTurns
        Logger.info("📝 ConversationContextAssembler initialized (max turns: \(maxConversationTurns))", category: .ai)
    }

    // MARK: - Context Assembly

    /// Build input items for a user message
    func buildForUserMessage(
        text: String,
        systemPrompt: String,
        allowedTools: Set<String>
    ) async -> [InputItem] {
        var items: [InputItem] = []

        // 1. System prompt
        items.append(.message(InputMessage(
            role: "developer",
            content: .text(systemPrompt)
        )))

        // 2. State cues developer message
        let stateCues = await buildStateCues(allowedTools: allowedTools)
        items.append(.message(InputMessage(
            role: "developer",
            content: .text(stateCues)
        )))

        // 3. Rolling conversation history (last N turns)
        let conversationItems = await buildConversationHistory()
        items.append(contentsOf: conversationItems)

        // 4. Current user message
        items.append(.message(InputMessage(
            role: "user",
            content: .text(text)
        )))

        Logger.debug("📦 Assembled context: \(items.count) items", category: .ai)
        return items
    }

    /// Build input items for a developer message
    func buildForDeveloperMessage(
        text: String,
        systemPrompt: String,
        allowedTools: Set<String>
    ) async -> [InputItem] {
        var items: [InputItem] = []

        // 1. System prompt (optional - may be omitted for developer-only messages)
        items.append(.message(InputMessage(
            role: "developer",
            content: .text(systemPrompt)
        )))

        // 2. Rolling conversation history
        let conversationItems = await buildConversationHistory()
        items.append(contentsOf: conversationItems)

        // 3. Current developer message
        items.append(.message(InputMessage(
            role: "developer",
            content: .text(text)
        )))

        Logger.debug("📦 Assembled developer context: \(items.count) items", category: .ai)
        return items
    }

    /// Build input items for a tool response
    func buildForToolResponse(
        output: JSON,
        callId: String,
        systemPrompt: String
    ) async -> [InputItem] {
        var items: [InputItem] = []

        // 1. System prompt
        items.append(.message(InputMessage(
            role: "developer",
            content: .text(systemPrompt)
        )))

        // 2. Rolling conversation history
        let conversationItems = await buildConversationHistory()
        items.append(contentsOf: conversationItems)

        // 3. Tool response
        let outputString = output.rawString() ?? "{}"
        items.append(.functionToolCallOutput(FunctionToolCallOutput(
            callId: callId,
            output: outputString
        )))

        Logger.debug("📦 Assembled tool response context: \(items.count) items", category: .ai)
        return items
    }

    // MARK: - Private Helpers

    /// Build state cues developer message
    private func buildStateCues(allowedTools: Set<String>) async -> String {
        let phase = await state.phase
        let objectives = await state.getAllObjectives()
        let phaseObjectives = objectives.filter { $0.phase == phase }

        var cues: [String] = []

        // Phase info
        cues.append("Current phase: \(phase.rawValue)")

        // Allowed tools
        let toolList = allowedTools.sorted().joined(separator: ", ")
        cues.append("Allowed tools: [\(toolList)]")

        // Objectives summary
        var objectiveSummary: [String] = []
        for objective in phaseObjectives.sorted(by: { $0.id < $1.id }) {
            objectiveSummary.append("\(objective.id)=\(objective.status.rawValue)")
        }
        if !objectiveSummary.isEmpty {
            cues.append("Objectives: \(objectiveSummary.joined(separator: ", "))")
        }

        return """
        Developer: State update
        \(cues.joined(separator: "\n"))
        """
    }

    /// Build rolling conversation history (last N user/assistant turns)
    private func buildConversationHistory() async -> [InputItem] {
        let messages = await state.messages
        let recentMessages = Array(messages.suffix(maxConversationTurns * 2)) // user + assistant pairs

        return recentMessages.compactMap { message -> InputItem? in
            let role: String
            switch message.role {
            case .user:
                role = "user"
            case .assistant:
                role = "assistant"
            case .system:
                // Skip system messages - they're included via system prompt
                return nil
            }

            return .message(InputMessage(
                role: role,
                content: .text(message.text)
            ))
        }
    }
}
