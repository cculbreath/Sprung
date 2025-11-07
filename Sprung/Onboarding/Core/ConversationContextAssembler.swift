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
        text: String
    ) async -> [InputItem] {
        var items: [InputItem] = []

        // 1. State cues developer message (only if we have conversation history)
        // Skip for the very first message to encourage natural conversation
        // Note: Tool management is now handled via API's tools parameter
        let messages = await state.messages
        if !messages.isEmpty {
            let stateCues = await buildStateCues()
            if !stateCues.isEmpty {
                items.append(.message(InputMessage(
                    role: "developer",
                    content: .text(stateCues)
                )))
            }
        }

        // 2. Current user message (conversation history handled via previous_response_id)
        items.append(.message(InputMessage(
            role: "user",
            content: .text(text)
        )))

        Logger.debug("📦 Assembled context: \(items.count) items", category: .ai)
        return items
    }

    /// Build input items for a developer message
    func buildForDeveloperMessage(
        text: String
    ) async -> [InputItem] {
        var items: [InputItem] = []

        // Current developer message (conversation history handled via previous_response_id)
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
        callId: String
    ) async -> [InputItem] {
        var items: [InputItem] = []

        // Tool response (conversation history handled via previous_response_id)
        let outputString = output.rawString() ?? "{}"
        let status = output["status"].string // Extract status if tool provided it

        items.append(.functionToolCallOutput(FunctionToolCallOutput(
            callId: callId,
            output: outputString,
            status: status
        )))

        Logger.debug("📦 Assembled tool response context: \(items.count) items (status: \(status ?? "nil"))", category: .ai)
        return items
    }

    // MARK: - Private Helpers

    /// Build state cues developer message
    /// Note: Tool management is now handled via API's tools parameter, not injected here
    private func buildStateCues() async -> String {
        let phase = await state.phase
        let objectives = await state.getAllObjectives()
        let phaseObjectives = objectives.filter { $0.phase == phase }

        var cues: [String] = []

        // Phase info
        cues.append("Phase: \(phase.rawValue)")

        // Objectives summary
        var objectiveSummary: [String] = []
        for objective in phaseObjectives.sorted(by: { $0.id < $1.id }) {
            objectiveSummary.append("\(objective.id)=\(objective.status.rawValue)")
        }
        if !objectiveSummary.isEmpty {
            cues.append("Objectives: \(objectiveSummary.joined(separator: ", "))")
        }

        guard !cues.isEmpty else { return "" }
        return "State update:\n" + cues.joined(separator: "\n")
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

    /// Build scratchpad summary for request metadata.
    func buildScratchpadSummary() async -> String {
        await state.scratchpadSummary()
    }
}
