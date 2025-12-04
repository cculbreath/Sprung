//
//  ConversationLogStore.swift
//  Sprung
//
//  Captures conversation flow for debugging: tool calls, responses, developer messages,
//  assistant messages, and user messages in a chronological, readable format.
//

import Foundation
import SwiftyJSON

/// Entry types for the conversation log
enum ConversationLogEntryType: String {
    case user = "USER"
    case assistant = "ASSISTANT"
    case developer = "DEVELOPER"
    case toolCall = "TOOL_CALL"
    case toolResponse = "TOOL_RESPONSE"
    case system = "SYSTEM"
}

/// A single entry in the conversation log
struct ConversationLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: ConversationLogEntryType
    let content: String
    let metadata: [String: String]

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    var formattedEntry: String {
        var metaString = ""
        if !metadata.isEmpty {
            metaString = " | meta: " + metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        }
        return "[\(formattedTimestamp)] [\(type.rawValue)] \(content)\(metaString)"
    }
}

/// Stores and manages the conversation log
@MainActor
final class ConversationLogStore {
    private var entries: [ConversationLogEntry] = []
    private let maxEntries = 2000

    init() {}

    // MARK: - Event Subscription

    func startListening(eventBus: EventCoordinator) {
        // Subscribe to LLM events
        Task {
            for await event in await eventBus.stream(topic: .llm) {
                await handleEvent(event)
            }
        }
        // Subscribe to tool events
        Task {
            for await event in await eventBus.stream(topic: .tool) {
                await handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: OnboardingEvent) async {
        switch event {
        // User messages
        case .chatboxUserMessageAdded(let messageId):
            addEntry(type: .user, content: "Message added to chatbox", metadata: ["messageId": String(messageId.prefix(8))])

        case .llmUserMessageSent(let messageId, let payload, let isSystemGenerated):
            // Check both "text" and "content" keys - different code paths use different keys
            let text = payload["text"].string ?? payload["content"].stringValue
            let truncated = text.count > 200 ? String(text.prefix(200)) + "..." : text
            let source = isSystemGenerated ? "system" : "user"
            addEntry(type: .user, content: truncated, metadata: ["source": source, "messageId": String(messageId.prefix(8))])

        // Developer messages
        case .llmDeveloperMessageSent(let messageId, let payload):
            let text = payload["text"].stringValue
            let truncated = text.count > 300 ? String(text.prefix(300)) + "..." : text
            addEntry(type: .developer, content: truncated, metadata: ["messageId": String(messageId.prefix(8))])

        // Tool responses sent to LLM
        case .llmSentToolResponseMessage(let messageId, let payload):
            let callId = payload["callId"].stringValue
            let output = payload["output"]
            let resultPreview = output.rawString()?.prefix(150) ?? "{}"
            addEntry(type: .toolResponse, content: " → \(resultPreview)", metadata: ["messageId": String(messageId.prefix(8)), "callId": String(callId.prefix(12))])

        // Tool calls from LLM (incoming requests)
        case .toolCallRequested(let call, _):
            // Format as: tool_name({ "arg": "value" })
            let argsDisplay = call.arguments.rawString() ?? "{}"
            addEntry(type: .toolCall, content: "\(call.name)(\(argsDisplay))", metadata: ["callId": call.callId, "name": call.name])

        // Tool call completed (response back to LLM)
        case .toolCallCompleted(let id, let result, _):
            var resultDisplay = "{}"
            if let prettyData = try? JSONSerialization.data(withJSONObject: result.object, options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                resultDisplay = prettyString
            } else {
                resultDisplay = result.rawString() ?? "{}"
            }
            addEntry(type: .toolResponse, content: resultDisplay, metadata: ["callId": id.uuidString])

        // Assistant messages (streaming)
        case .streamingMessageFinalized(let id, let finalText, let toolCalls, _):
            if !finalText.isEmpty {
                let truncated = finalText.count > 300 ? String(finalText.prefix(300)) + "..." : finalText
                addEntry(type: .assistant, content: truncated, metadata: ["messageId": String(id.uuidString.prefix(8))])
            }
            if let tools = toolCalls, !tools.isEmpty {
                addEntry(type: .system, content: "Response includes \(tools.count) tool call(s)", metadata: ["messageId": String(id.uuidString.prefix(8))])
            }

        default:
            break
        }
    }

    // MARK: - Entry Management

    private func addEntry(type: ConversationLogEntryType, content: String, metadata: [String: String] = [:]) {
        let entry = ConversationLogEntry(
            timestamp: Date(),
            type: type,
            content: content,
            metadata: metadata
        )
        entries.append(entry)

        // Trim if over limit
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func getEntries() -> [ConversationLogEntry] {
        entries
    }

    func clear() {
        entries.removeAll()
    }

    // MARK: - Export

    func exportLog() -> String {
        var output = "Sprung Onboarding Conversation Log\n"
        output += "Generated: \(Date().formatted())\n"
        output += "Entries: \(entries.count)\n"
        output += String(repeating: "=", count: 80) + "\n\n"

        for entry in entries {
            output += entry.formattedEntry + "\n\n"
        }

        return output
    }
}
