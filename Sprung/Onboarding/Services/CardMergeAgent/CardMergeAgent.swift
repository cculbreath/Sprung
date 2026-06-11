//
//  CardMergeAgent.swift
//  Sprung
//
//  Multi-turn agent for merging duplicate knowledge cards.
//  Uses filesystem tools to read, compare, merge, and delete cards.
//  Runs against the Anthropic Messages API with prompt caching:
//  one breakpoint on the last tool (caches the tool set), one on the
//  system block, and a moving breakpoint on the last content block of
//  the final message (3 total, within the 4-breakpoint limit).
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
    private let maxResponseTokens = 8192

    // Context pruning (0 = disabled, uses full context).
    // Note: pruning rewrites earlier messages, which invalidates the cached
    // prefix from the prune point forward — only enable when context size
    // matters more than cache hits.
    private var ephemeralTurns: Int {
        UserDefaults.standard.integer(forKey: "onboardingEphemeralTurns")
    }

    // Conversation state (no cache_control markers stored here; the moving
    // breakpoint is applied to a per-request copy in cachedRequestMessages()).
    private var messages: [AnthropicMessage] = []

    // Track ephemeral tool-result blocks: (messageIndex, blockIndex, addedAtTurn, toolUseId)
    private var ephemeralBlocks: [(messageIndex: Int, blockIndex: Int, addedAtTurn: Int, toolUseId: String)] = []

    // Track file reads to detect excessive re-reading
    private var fileReadCounts: [String: Int] = [:]
    private var duplicateReadWarningIssued = false

    // Tools (built once so the encoded tool list is byte-stable across turns —
    // required for the tool-set cache breakpoint to hit)
    private var tools: [AnthropicTool]

    // Original card count for statistics
    private var originalCardCount: Int = 0

    // Background merge tasks
    private var backgroundMergeTasks: [Task<BackgroundMergeResult, Error>] = []

    // Track cards currently being merged to prevent duplicates
    private var cardsBeingMerged: Set<String> = []

    // Track cards that have been deleted by completed merges (to give better error messages)
    private var deletedCardFiles: Set<String> = []

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
        ephemeralBlocks = []

        // Count original cards
        originalCardCount = try countCards()

        // Initialize conversation
        messages.append(initialUserMessage())

        let startTime = Date()

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

                let parameters = AnthropicMessageParameter(
                    model: modelId,
                    messages: cachedRequestMessages(),
                    system: systemContent(),
                    maxTokens: maxResponseTokens,
                    stream: false,
                    tools: tools,
                    toolChoice: .auto
                )

                let response = try await facade.anthropicMessages(parameters: parameters)

                // Track token + cache usage
                let usage = response.usage
                Logger.info(
                    "🔀 CardMergeAgent usage (\(modelId)): input=\(usage.inputTokens) cache_read=\(usage.cacheReadInputTokens ?? 0) cache_create=\(usage.cacheCreationInputTokens ?? 0) output=\(usage.outputTokens)",
                    category: .ai
                )
                if let agentId = agentId {
                    tracker?.addTokenUsage(
                        agentId: agentId,
                        input: usage.inputTokens,
                        output: usage.outputTokens,
                        cached: usage.cacheReadInputTokens ?? 0
                    )
                }

                // Split response content into text and tool-use blocks
                var textParts: [String] = []
                var toolUses: [AnthropicToolUseResponseBlock] = []
                for block in response.content {
                    switch block {
                    case .text(let textBlock):
                        textParts.append(textBlock.text)
                    case .toolUse(let toolUse):
                        toolUses.append(toolUse)
                    }
                }

                // Echo the assistant turn into history
                messages.append(assistantMessage(textParts: textParts, toolUses: toolUses))

                // If the model returned text without tool calls, it might be confused
                if toolUses.isEmpty {
                    messages.append(.user("Please continue merging cards or call complete_merge if you're done."))
                    continue
                }

                // Prune old ephemeral tool-result blocks before adding new ones (if enabled)
                if ephemeralTurns > 0 {
                    pruneEphemeralBlocks()
                }

                // Execute non-completion tool calls first so every tool_use in the
                // assistant turn gets a tool_result in the next user message.
                var resultBlocks: [AnthropicContentBlock] = []
                var ephemeralCandidates: [(blockIndex: Int, toolUseId: String)] = []

                for toolUse in toolUses where toolUse.name != CompleteMergeTool.name {
                    let arguments = argumentsJSON(from: toolUse.input)

                    await updateProgress("Turn \(turnCount): \(toolDisplayName(toolUse.name))")

                    let result = await executeTool(name: toolUse.name, arguments: arguments)
                    let blockIndex = resultBlocks.count
                    resultBlocks.append(.toolResult(AnthropicToolResultBlock(
                        toolUseId: toolUse.id,
                        content: result
                    )))

                    // Mark card file reads as ephemeral (they can be pruned after a few turns)
                    // Only files in cards/ folder are ephemeral; index.json and other files persist
                    if toolUse.name == ReadFileTool.name {
                        let path = extractToolDetail(name: toolUse.name, arguments: arguments) ?? ""
                        if path.contains("cards/") {
                            ephemeralCandidates.append((blockIndex: blockIndex, toolUseId: toolUse.id))
                        }
                        // Track duplicate reads
                        trackFileRead(path: path)
                    }

                    // Log to transcript
                    if let agentId = agentId {
                        tracker?.appendTranscript(
                            agentId: agentId,
                            entryType: .tool,
                            content: toolDisplayName(toolUse.name),
                            details: extractToolDetail(name: toolUse.name, arguments: arguments)
                        )
                    }
                }

                // Handle the completion tool (if called this turn)
                if let completionCall = toolUses.first(where: { $0.name == CompleteMergeTool.name }) {
                    do {
                        let mergeLog = try parseCompleteMerge(arguments: argumentsJSON(from: completionCall.input))

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
                        resultBlocks.append(.toolResult(AnthropicToolResultBlock(
                            toolUseId: completionCall.id,
                            content: "Error parsing complete_merge: \(error.localizedDescription). Please retry.",
                            isError: true
                        )))
                        // Every tool_use must be answered: a duplicate
                        // complete_merge in the same turn would otherwise orphan
                        // its id and 400 the next request.
                        for duplicate in toolUses.filter({ $0.name == CompleteMergeTool.name && $0.id != completionCall.id }) {
                            resultBlocks.append(.toolResult(AnthropicToolResultBlock(
                                toolUseId: duplicate.id,
                                content: "Duplicate complete_merge call — answered by the first call's result.",
                                isError: true
                            )))
                        }
                    }
                }

                guard !resultBlocks.isEmpty else { continue }

                let messageIndex = messages.count
                messages.append(AnthropicMessage(role: "user", content: .blocks(resultBlocks)))

                for candidate in ephemeralCandidates {
                    ephemeralBlocks.append((
                        messageIndex: messageIndex,
                        blockIndex: candidate.blockIndex,
                        addedAtTurn: turnCount,
                        toolUseId: candidate.toolUseId
                    ))
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

        // Check for cards that were already deleted by previous merges
        let alreadyDeleted = requestedCards.intersection(deletedCardFiles)
        if !alreadyDeleted.isEmpty {
            return """
                Error: Cannot merge - the following cards were already merged and deleted:
                \(alreadyDeleted.sorted().joined(separator: "\n"))

                These cards no longer exist. Please re-read index.json to see the current list of cards.
                """
        }

        // Validate all card files exist before spawning merge
        var missingCards: [String] = []
        for cardFile in params.cardFiles {
            let filePath = workspacePath.appendingPathComponent(cardFile)
            if !FileManager.default.fileExists(atPath: filePath.path) {
                missingCards.append(cardFile)
            }
        }
        if !missingCards.isEmpty {
            return """
                Error: Cannot merge - the following card files do not exist:
                \(missingCards.joined(separator: "\n"))

                The card IDs may be incorrect. Please re-read index.json to see the current list of cards with their correct IDs.
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
            do {
                let result = try await agent.run()
                // On success, move cards from "being merged" to "deleted"
                await MainActor.run { [weak self] in
                    self?.cardsBeingMerged.subtract(cardsToRemove)
                    if result.success {
                        self?.deletedCardFiles.formUnion(cardsToRemove)
                    }
                }
                return result
            } catch {
                // On failure, just remove from "being merged" (cards still exist)
                await MainActor.run { [weak self] in
                    self?.cardsBeingMerged.subtract(cardsToRemove)
                }
                throw error
            }
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

    /// System content with a cache breakpoint. Together with the breakpoint on
    /// the last tool, this caches the full tools → system prefix.
    private func systemContent() -> AnthropicSystemContent {
        .blocks([AnthropicSystemBlock(
            text: CardMergeAgentPrompts.systemPrompt,
            cacheControl: .ephemeral
        )])
    }

    private func initialUserMessage() -> AnthropicMessage {
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
        return .user(prompt)
    }

    private func assistantMessage(
        textParts: [String],
        toolUses: [AnthropicToolUseResponseBlock]
    ) -> AnthropicMessage {
        var blocks: [AnthropicContentBlock] = []
        let text = textParts.joined(separator: "\n")
        if !text.isEmpty {
            blocks.append(.text(AnthropicTextBlock(text: text)))
        }
        for toolUse in toolUses {
            blocks.append(.toolUse(AnthropicToolUseBlock(
                id: toolUse.id,
                name: toolUse.name,
                input: toolUse.input.mapValues { $0.value }
            )))
        }
        if blocks.isEmpty {
            // The API rejects empty text blocks (400) — use a visible placeholder
            // so a rare empty-content response stays recoverable.
            blocks.append(.text(AnthropicTextBlock(text: "(no content)")))
        }
        return AnthropicMessage(role: "assistant", content: .blocks(blocks))
    }

    /// Returns a per-request copy of the conversation with the moving cache
    /// breakpoint applied to the last content block of the final message.
    /// History itself stays marker-free so each request carries exactly one
    /// message-tier breakpoint (3 total with tools + system).
    private func cachedRequestMessages() -> [AnthropicMessage] {
        guard let last = messages.last else { return messages }

        var result = messages

        switch last.content {
        case .text(let text):
            result[result.count - 1] = AnthropicMessage(
                role: last.role,
                content: .blocks([.text(AnthropicTextBlock(text: text, cacheControl: .ephemeral))])
            )
        case .blocks(let blocks):
            guard let lastBlock = blocks.last else { return result }
            var newBlocks = blocks
            switch lastBlock {
            case .text(let textBlock):
                newBlocks[newBlocks.count - 1] = .text(
                    AnthropicTextBlock(text: textBlock.text, cacheControl: .ephemeral)
                )
            case .toolResult(let toolResult):
                newBlocks[newBlocks.count - 1] = .toolResult(AnthropicToolResultBlock(
                    toolUseId: toolResult.toolUseId,
                    content: toolResult.content,
                    isError: toolResult.isError ?? false,
                    cacheControl: .ephemeral
                ))
            default:
                break  // image/document/toolUse blocks never terminate our messages
            }
            result[result.count - 1] = AnthropicMessage(role: last.role, content: .blocks(newBlocks))
        }

        return result
    }

    /// Serialize a tool-use input dictionary back to a JSON string for the
    /// existing Codable tool parameter decoders.
    private func argumentsJSON(from input: [String: AnthropicDynamicValue]) -> String {
        let dict = input.mapValues { $0.value }
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Tool Definitions

    private static func buildTools() -> [AnthropicTool] {
        let toolTypes: [any AgentTool.Type] = [
            ReadFileTool.self,
            ListDirectoryTool.self,
            WriteFileTool.self,
            DeleteFileTool.self,
            GlobSearchTool.self,
            MergeCardsTool.self,
            CompleteMergeTool.self
        ]

        return toolTypes.enumerated().map { index, tool in
            // Cache breakpoint on the LAST tool caches the whole tool set.
            let isLast = index == toolTypes.count - 1
            return .function(AnthropicFunctionTool(
                name: tool.name,
                description: tool.description,
                inputSchema: tool.parametersSchema,
                cacheControl: isLast ? .ephemeral : nil
            ))
        }
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

    // MARK: - Context Pruning

    /// Prune old ephemeral tool-result blocks to keep context size manageable.
    /// Replaces pruned blocks with a placeholder so tool_use IDs remain answered.
    /// Only called when ephemeralTurns > 0.
    private func pruneEphemeralBlocks() {
        let expiredTurn = turnCount - ephemeralTurns
        let toRemove = ephemeralBlocks.filter { $0.addedAtTurn <= expiredTurn }

        for item in toRemove {
            guard item.messageIndex < messages.count,
                  case .blocks(var blocks) = messages[item.messageIndex].content,
                  item.blockIndex < blocks.count else { continue }

            blocks[item.blockIndex] = .toolResult(AnthropicToolResultBlock(
                toolUseId: item.toolUseId,
                content: "[Content pruned - file was read \(turnCount - item.addedAtTurn) turns ago. Re-read if needed.]"
            ))
            messages[item.messageIndex] = AnthropicMessage(
                role: messages[item.messageIndex].role,
                content: .blocks(blocks)
            )
        }

        // Remove from tracking
        ephemeralBlocks.removeAll { $0.addedAtTurn <= expiredTurn }

        if !toRemove.isEmpty {
            Logger.debug("🔀 Pruned \(toRemove.count) ephemeral tool results from context", category: .ai)
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

    // MARK: - Duplicate Read Tracking

    /// Track file reads and warn if excessive re-reading is detected.
    private func trackFileRead(path: String) {
        let count = (fileReadCounts[path] ?? 0) + 1
        fileReadCounts[path] = count

        // Warn on first duplicate (count >= 2)
        if count >= 2 && !duplicateReadWarningIssued {
            let totalDuplicates = fileReadCounts.values.filter { $0 >= 2 }.count
            if totalDuplicates >= 3 {
                duplicateReadWarningIssued = true
                Logger.warning("⚠️ CardMergeAgent: Excessive file re-reading detected (\(totalDuplicates) files read multiple times). Consider increasing 'Context Pruning Turns' in Settings or setting to 0 (disabled).", category: .ai)
            }
        }

        if count >= 3 {
            Logger.debug("🔀 File '\(path)' read \(count) times this session", category: .ai)
        }
    }
}
