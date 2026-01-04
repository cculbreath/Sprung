//
//  CardMergeAgent.swift
//  Sprung
//
//  Multi-turn agent for merging duplicate knowledge cards.
//  Uses filesystem tools to read, compare, merge, and delete cards.
//

import Foundation
import Observation
import SwiftOpenAI
import SwiftyJSON

// MARK: - Agent Status

enum CardMergeAgentStatus: Equatable {
    case idle
    case running
    case completed
    case failed(String)
}

// MARK: - Agent Error

enum CardMergeAgentError: LocalizedError {
    case noLLMFacade
    case maxTurnsExceeded
    case agentDidNotComplete
    case invalidToolCall(String)
    case toolExecutionFailed(String)
    case timeout
    case workspaceError(String)

    var errorDescription: String? {
        switch self {
        case .noLLMFacade:
            return "LLM service is not available"
        case .maxTurnsExceeded:
            return "Agent exceeded maximum number of turns without completing"
        case .agentDidNotComplete:
            return "Agent stopped without calling complete_merge"
        case .invalidToolCall(let msg):
            return "Invalid tool call: \(msg)"
        case .toolExecutionFailed(let msg):
            return "Tool execution failed: \(msg)"
        case .timeout:
            return "Agent timed out"
        case .workspaceError(let msg):
            return "Workspace error: \(msg)"
        }
    }
}

// MARK: - Merge Result

/// Result of the card merge operation
struct CardMergeResult {
    let originalCount: Int
    let finalCount: Int
    let mergeCount: Int
    let mergeLog: [MergeLogEntry]
}

// MARK: - Card Merge Agent

@Observable
@MainActor
class CardMergeAgent {
    // Configuration
    private let workspacePath: URL
    private let modelId: String
    private weak var facade: LLMFacade?
    private var eventBus: EventCoordinator?

    // Agent tracking
    private let agentId: String?
    private let tracker: AgentActivityTracker?

    // State
    private(set) var status: CardMergeAgentStatus = .idle
    private(set) var currentAction: String = ""
    private(set) var progress: [String] = []
    private(set) var turnCount: Int = 0

    // Limits
    private let maxTurns = 100  // More turns allowed for thorough merging
    private let timeoutSeconds: TimeInterval = 900  // 15 minutes
    private let ephemeralTurns = 5  // Prune old tool results after this many turns

    // Conversation state
    private var messages: [ChatCompletionParameters.Message] = []

    // Track ephemeral messages: (messageIndex, addedAtTurn, toolCallId)
    private var ephemeralMessages: [(index: Int, addedAtTurn: Int, toolCallId: String)] = []

    // Tools
    private var tools: [ChatCompletionParameters.Tool]

    // Original card count for statistics
    private var originalCardCount: Int = 0

    // Background merge tasks
    private var backgroundMergeTasks: [Task<BackgroundMergeResult, Error>] = []

    // Track cards currently being merged to prevent duplicates
    private var cardsBeingMerged: Set<String> = []

    init(
        workspacePath: URL,
        modelId: String,
        facade: LLMFacade,
        eventBus: EventCoordinator? = nil,
        agentId: String? = nil,
        tracker: AgentActivityTracker? = nil
    ) {
        self.workspacePath = workspacePath
        self.modelId = modelId
        self.facade = facade
        self.eventBus = eventBus
        self.agentId = agentId
        self.tracker = tracker
        self.tools = Self.buildTools()
    }

    // MARK: - Public API

    /// Run the agent to merge duplicate cards
    func run() async throws -> CardMergeResult {
        guard let facade = facade else {
            throw CardMergeAgentError.noLLMFacade
        }

        status = .running
        turnCount = 0
        messages = []
        progress = []

        // Count original cards
        originalCardCount = try countCards()

        // Initialize conversation
        messages.append(systemMessage())
        messages.append(initialUserMessage())

        let startTime = Date()
        var mergeLog: [MergeLogEntry] = []

        do {
            while turnCount < maxTurns {
                // Check timeout
                if Date().timeIntervalSince(startTime) > timeoutSeconds {
                    throw CardMergeAgentError.timeout
                }

                turnCount += 1
                await updateProgress("Turn \(turnCount): Calling LLM...")

                // Add turn marker to transcript
                if let agentId = agentId {
                    tracker?.appendTranscript(
                        agentId: agentId,
                        entryType: .turn,
                        content: "Turn \(turnCount) of \(maxTurns)",
                        details: nil
                    )
                }

                // Call LLM with tools
                let response = try await facade.executeWithTools(
                    messages: messages,
                    tools: tools,
                    toolChoice: .auto,
                    modelId: modelId,
                    temperature: 0.2  // Low temperature for consistent merging decisions
                )

                // Track token usage
                if let usage = response.usage, let agentId = agentId {
                    let inputTokens = usage.promptTokens ?? 0
                    let outputTokens = usage.completionTokens ?? 0
                    let cachedTokens = usage.promptTokensDetails?.cachedTokens ?? 0
                    tracker?.addTokenUsage(
                        agentId: agentId,
                        input: inputTokens,
                        output: outputTokens,
                        cached: cachedTokens
                    )
                }

                // Process response
                guard let choice = response.choices?.first,
                      let message = choice.message else {
                    throw CardMergeAgentError.agentDidNotComplete
                }

                // Add assistant message to history
                messages.append(buildAssistantMessage(from: message))

                // Check finish reason
                let finishReason: String
                switch choice.finishReason {
                case .int(let val): finishReason = String(val)
                case .string(let val): finishReason = val
                case .none: finishReason = ""
                }

                // If model returned text without tool calls, it might be confused
                if finishReason == "stop" && (message.toolCalls == nil || message.toolCalls!.isEmpty) {
                    // Prompt it to continue or complete
                    messages.append(ChatCompletionParameters.Message(
                        role: .user,
                        content: .text("Please continue merging cards or call complete_merge if you're done.")
                    ))
                    continue
                }

                // Process tool calls
                guard let toolCalls = message.toolCalls, !toolCalls.isEmpty else {
                    continue
                }

                // Check for completion tool
                if let completionCall = toolCalls.first(where: { $0.function.name == CompleteMergeTool.name }) {
                    do {
                        mergeLog = try parseCompleteMerge(arguments: completionCall.function.arguments)

                        // Wait for any background merge tasks to complete before finalizing
                        if !backgroundMergeTasks.isEmpty {
                            await updateProgress("Waiting for \(backgroundMergeTasks.count) background merges...")
                            let bgResults = await waitForBackgroundMerges()
                            Logger.info("🔀 Background merges finished: \(bgResults.filter { $0.success }.count) successful", category: .ai)
                        }

                        status = .completed
                        await updateProgress("Merge complete!")

                        let finalCount = try countCards()
                        return CardMergeResult(
                            originalCount: originalCardCount,
                            finalCount: finalCount,
                            mergeCount: originalCardCount - finalCount,
                            mergeLog: mergeLog
                        )
                    } catch {
                        // Send error back so agent can retry
                        messages.append(buildToolResultMessage(
                            toolCallId: completionCall.id ?? UUID().uuidString,
                            result: "Error parsing complete_merge: \(error.localizedDescription). Please retry."
                        ))
                        continue
                    }
                }

                // Prune old ephemeral messages before adding new ones
                pruneEphemeralMessages()

                // Execute other tool calls
                let executableCalls = toolCalls.filter { $0.function.name != CompleteMergeTool.name }

                for toolCall in executableCalls {
                    let toolId = toolCall.id ?? UUID().uuidString
                    let toolName = toolCall.function.name ?? "unknown"
                    let arguments = toolCall.function.arguments

                    await updateProgress("Turn \(turnCount): \(toolDisplayName(toolName))")

                    let result = await executeTool(name: toolName, arguments: arguments)
                    let messageIndex = messages.count
                    messages.append(buildToolResultMessage(toolCallId: toolId, result: result))

                    // Mark card file reads as ephemeral (they can be pruned after a few turns)
                    // Only files in cards/ folder are ephemeral; index.json and other files persist
                    if toolName == ReadFileTool.name {
                        let path = extractToolDetail(name: toolName, arguments: arguments) ?? ""
                        let isCardFile = path.contains("cards/")
                        if isCardFile {
                            ephemeralMessages.append((index: messageIndex, addedAtTurn: turnCount, toolCallId: toolId))
                        }
                    }

                    // Log to transcript
                    if let agentId = agentId {
                        tracker?.appendTranscript(
                            agentId: agentId,
                            entryType: .tool,
                            content: toolDisplayName(toolName),
                            details: extractToolDetail(name: toolName, arguments: arguments)
                        )
                    }
                }
            }

            // Max turns reached
            Logger.warning("CardMergeAgent: Max turns reached, forcing completion", category: .ai)
            throw CardMergeAgentError.maxTurnsExceeded

        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, arguments: String) async -> String {
        do {
            let argsData = arguments.data(using: .utf8) ?? Data()

            switch name {
            case ReadFileTool.name:
                let params = try JSONDecoder().decode(ReadFileTool.Parameters.self, from: argsData)
                let result = try ReadFileTool.execute(parameters: params, repoRoot: workspacePath)
                return formatReadResult(result)

            case ListDirectoryTool.name:
                let params = try JSONDecoder().decode(ListDirectoryTool.Parameters.self, from: argsData)
                let result = try ListDirectoryTool.execute(parameters: params, repoRoot: workspacePath)
                return result.formattedTree

            case WriteFileTool.name:
                let params = try JSONDecoder().decode(WriteFileTool.Parameters.self, from: argsData)
                let result = try WriteFileTool.execute(parameters: params, repoRoot: workspacePath)
                return "Successfully wrote \(result.bytesWritten) bytes to \(result.path)"

            case DeleteFileTool.name:
                let params = try JSONDecoder().decode(DeleteFileTool.Parameters.self, from: argsData)
                let result = try DeleteFileTool.execute(parameters: params, repoRoot: workspacePath)
                return "Successfully deleted \(result.path)"

            case GlobSearchTool.name:
                let params = try JSONDecoder().decode(GlobSearchTool.Parameters.self, from: argsData)
                let result = try GlobSearchTool.execute(parameters: params, repoRoot: workspacePath)
                return formatGlobResult(result)

            case MergeCardsTool.name:
                let params = try JSONDecoder().decode(MergeCardsTool.Parameters.self, from: argsData)
                return executeMergeCards(params: params)

            default:
                return "Unknown tool: \(name)"
            }
        } catch {
            Logger.error("CardMergeAgent tool error (\(name)): \(error.localizedDescription)", category: .ai)
            return "Error: \(error.localizedDescription)"
        }
    }

    private func formatReadResult(_ result: ReadFileTool.Result) -> String {
        var output = "File content (lines \(result.startLine)-\(result.endLine) of \(result.totalLines)):\n"
        output += result.content
        if result.hasMore {
            output += "\n\n[File has more content. Use offset=\(result.endLine + 1) to read more.]"
        }
        return output
    }

    private func formatGlobResult(_ result: GlobSearchTool.Result) -> String {
        var lines: [String] = ["Found \(result.totalMatches) files:"]
        for file in result.files {
            lines.append("  \(file.relativePath)")
        }
        if result.truncated {
            lines.append("  ... and \(result.totalMatches - result.files.count) more")
        }
        return lines.joined(separator: "\n")
    }

    /// Spawn a background merge agent for the given card files
    private func executeMergeCards(params: MergeCardsTool.Parameters) -> String {
        guard let facade = facade else {
            return "Error: LLM service not available"
        }

        // Check for conflicts with in-progress merges
        let requestedCards = Set(params.cardFiles)
        let conflicts = requestedCards.intersection(cardsBeingMerged)
        if !conflicts.isEmpty {
            return """
                Error: Cannot start merge - the following cards are already being merged in the background:
                \(conflicts.sorted().joined(separator: ", "))

                Please wait for the existing merge to complete before attempting to merge these cards again.
                """
        }

        // Mark cards as being merged
        cardsBeingMerged.formUnion(requestedCards)

        let agent = BackgroundMergeAgent(
            workspacePath: workspacePath,
            cardFiles: params.cardFiles,
            mergeReason: params.mergeReason,
            modelId: modelId,
            facade: facade,
            parentAgentId: agentId,
            tracker: tracker
        )

        // Log spawn to parent agent transcript with merge reasoning
        let cardIds = params.cardFiles.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        if let agentId = agentId {
            tracker?.appendTranscript(
                agentId: agentId,
                entryType: .tool,
                content: "Spawning background merge for \(cardIds.count) cards",
                details: "Cards: \(cardIds.joined(separator: ", "))\nReason: \(params.mergeReason)"
            )
        }

        // Capture cards for cleanup after task completes
        let cardsToRemove = requestedCards
        let task = Task { [weak self] () -> BackgroundMergeResult in
            defer {
                Task { @MainActor [weak self] in
                    self?.cardsBeingMerged.subtract(cardsToRemove)
                }
            }
            return try await agent.run()
        }
        backgroundMergeTasks.append(task)

        Logger.info("🔀 Spawned background merge for \(cardIds.count) cards: \(cardIds.joined(separator: ", "))", category: .ai)

        return """
            Background merge started for \(params.cardFiles.count) cards.
            Cards: \(params.cardFiles.joined(separator: ", "))
            Reason: \(params.mergeReason)

            The merge will complete in the background. You can continue analyzing other cards.
            The source cards will be automatically deleted and index updated when merge completes.
            """
    }

    /// Wait for all background merge tasks to complete
    private func waitForBackgroundMerges() async -> [BackgroundMergeResult] {
        guard !backgroundMergeTasks.isEmpty else { return [] }

        Logger.info("🔀 Waiting for \(backgroundMergeTasks.count) background merge tasks...", category: .ai)

        var results: [BackgroundMergeResult] = []
        for task in backgroundMergeTasks {
            do {
                let result = try await task.value
                results.append(result)
            } catch {
                Logger.error("🔀 Background merge failed: \(error.localizedDescription)", category: .ai)
            }
        }
        backgroundMergeTasks.removeAll()

        Logger.info("🔀 All background merges complete: \(results.count) successful", category: .ai)
        return results
    }

    // MARK: - Message Building

    private func systemMessage() -> ChatCompletionParameters.Message {
        let prompt = CardMergeAgentPrompts.systemPrompt
        return ChatCompletionParameters.Message(
            role: .system,
            content: .text(prompt)
        )
    }

    private func initialUserMessage() -> ChatCompletionParameters.Message {
        let prompt = """
        Please analyze and merge duplicate knowledge cards in the workspace.

        Workspace path: \(workspacePath.path)

        The workspace contains:
        - index.json: Summary of all cards (id, title, organization, date_range, card_type, narrative_preview)
        - cards/: Directory with individual card files as {uuid}.json

        Start by reading index.json to understand what cards exist, then identify duplicates to merge.
        When you find duplicates:
        1. Read the full cards to compare content
        2. Create a merged card with a new UUID using write_file
        3. Delete the source cards using delete_file

        Call complete_merge when you've processed all duplicates.
        """
        return ChatCompletionParameters.Message(
            role: .user,
            content: .text(prompt)
        )
    }

    private func buildAssistantMessage(from message: ChatCompletionObject.ChatChoice.ChatMessage) -> ChatCompletionParameters.Message {
        let content: ChatCompletionParameters.Message.ContentType
        if let text = message.content {
            content = .text(text)
        } else {
            content = .text("")
        }

        return ChatCompletionParameters.Message(
            role: .assistant,
            content: content,
            toolCalls: message.toolCalls
        )
    }

    private func buildToolResultMessage(toolCallId: String, result: String) -> ChatCompletionParameters.Message {
        return ChatCompletionParameters.Message(
            role: .tool,
            content: .text(result),
            toolCallID: toolCallId
        )
    }

    // MARK: - Tool Definitions

    private static func buildTools() -> [ChatCompletionParameters.Tool] {
        [
            buildTool(ReadFileTool.self),
            buildTool(ListDirectoryTool.self),
            buildTool(WriteFileTool.self),
            buildTool(DeleteFileTool.self),
            buildTool(GlobSearchTool.self),
            buildTool(MergeCardsTool.self),
            buildTool(CompleteMergeTool.self)
        ]
    }

    private static func buildTool<T: AgentTool>(_ tool: T.Type) -> ChatCompletionParameters.Tool {
        let schemaDict = tool.parametersSchema
        let schema = buildJSONSchema(from: schemaDict)

        let function = ChatCompletionParameters.ChatFunction(
            name: tool.name,
            strict: false,
            description: tool.description,
            parameters: schema
        )

        return ChatCompletionParameters.Tool(function: function)
    }

    private static func buildJSONSchema(from dict: [String: Any]) -> JSONSchema {
        let typeStr = dict["type"] as? String ?? "object"
        let desc = dict["description"] as? String
        let enumValues = dict["enum"] as? [String]

        let schemaType: JSONSchemaType
        switch typeStr {
        case "string": schemaType = .string
        case "integer": schemaType = .integer
        case "number": schemaType = .number
        case "boolean": schemaType = .boolean
        case "array": schemaType = .array
        case "object": schemaType = .object
        default: schemaType = .string
        }

        var properties: [String: JSONSchema]? = nil
        if let propsDict = dict["properties"] as? [String: [String: Any]] {
            var propSchemas: [String: JSONSchema] = [:]
            for (key, propSpec) in propsDict {
                propSchemas[key] = buildJSONSchema(from: propSpec)
            }
            properties = propSchemas
        }

        var items: JSONSchema? = nil
        if schemaType == .array, let itemsDict = dict["items"] as? [String: Any] {
            items = buildJSONSchema(from: itemsDict)
        }

        let required = dict["required"] as? [String]
        let additionalProps = dict["additionalProperties"] as? Bool ?? false

        return JSONSchema(
            type: schemaType,
            description: desc,
            properties: properties,
            items: items,
            required: required,
            additionalProperties: additionalProps,
            enum: enumValues
        )
    }

    // MARK: - Result Parsing

    private func parseCompleteMerge(arguments: String) throws -> [MergeLogEntry] {
        guard let data = arguments.data(using: .utf8) else {
            throw CardMergeAgentError.invalidToolCall("Could not parse arguments as UTF-8")
        }

        let params = try JSONDecoder().decode(CompleteMergeTool.Parameters.self, from: data)

        return params.mergeLog.map { entry in
            MergeLogEntry(
                action: entry.action == "merged" ? .merged : .kept,
                inputCardIds: entry.sourceCardIds,
                outputCardId: entry.resultCardId,
                reasoning: entry.reasoning
            )
        }
    }

    // MARK: - Ephemeral Message Pruning

    /// Prune old ephemeral messages to keep context size manageable.
    /// Replaces pruned messages with a placeholder so tool call IDs remain valid.
    private func pruneEphemeralMessages() {
        let expiredTurn = turnCount - ephemeralTurns
        let toRemove = ephemeralMessages.filter { $0.addedAtTurn <= expiredTurn }

        for item in toRemove {
            guard item.index < messages.count else { continue }

            // Replace with a pruned placeholder instead of removing
            // This preserves the message structure and tool call ID reference
            // Use the tracked toolCallId since the property may not be accessible
            messages[item.index] = ChatCompletionParameters.Message(
                role: .tool,
                content: .text("[Content pruned - file was read \(turnCount - item.addedAtTurn) turns ago. Re-read if needed.]"),
                toolCallID: item.toolCallId
            )
        }

        // Remove from tracking
        ephemeralMessages.removeAll { $0.addedAtTurn <= expiredTurn }

        if !toRemove.isEmpty {
            Logger.debug("🔀 Pruned \(toRemove.count) ephemeral messages from context", category: .ai)
        }
    }

    // MARK: - Helpers

    private func countCards() throws -> Int {
        let cardsDir = workspacePath.appendingPathComponent("cards")
        let files = try FileManager.default.contentsOfDirectory(
            at: cardsDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        return files.count
    }

    private func updateProgress(_ message: String) async {
        currentAction = message
        progress.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
        Logger.info("🔀 CardMergeAgent: \(message)", category: .ai)

        if let agentId = agentId {
            tracker?.updateStatusMessage(agentId: agentId, message: message)
        }
    }

    private func toolDisplayName(_ name: String) -> String {
        switch name {
        case ReadFileTool.name: return "Read file"
        case ListDirectoryTool.name: return "List directory"
        case WriteFileTool.name: return "Write file"
        case DeleteFileTool.name: return "Delete file"
        case GlobSearchTool.name: return "Search files"
        case MergeCardsTool.name: return "Merge cards (background)"
        case CompleteMergeTool.name: return "Complete merge"
        default: return name
        }
    }

    private func extractToolDetail(name: String, arguments: String) -> String? {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch name {
        case ReadFileTool.name, WriteFileTool.name, DeleteFileTool.name:
            return json["path"] as? String
        case ListDirectoryTool.name:
            return json["path"] as? String ?? "."
        case GlobSearchTool.name:
            return json["pattern"] as? String
        default:
            return nil
        }
    }
}
