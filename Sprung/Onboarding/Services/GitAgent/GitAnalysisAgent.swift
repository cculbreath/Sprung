//
//  GitAnalysisAgent.swift
//  Sprung
//
//  Multi-turn agent that explores a git repository and produces a faithful,
//  verifiable code dossier — a `RepositoryDigest` intermediate representation.
//  Uses filesystem tools to explore the codebase; the digest it returns is then
//  persisted as the artifact's IR, and downstream skill/narrative extraction runs
//  against `digest.renderedForExtraction()` (the SAME path a PDF transcription
//  takes). The agent does NOT emit skills or cards directly.
//
//  Runs on the Anthropic Messages API (non-streaming) with conversation-prefix
//  caching:
//  - Breakpoint 1: cache_control on the LAST tool — caches the whole tool block.
//  - Breakpoint 2: cache_control on the system block — caches tools + system.
//  - Breakpoint 3 (moving): the last markable content block of the final message,
//    applied at request-build time only (never persisted), so the growing
//    conversation prefix is served from cache from turn 2 onward.
//  HARD LIMIT: ≤4 breakpoints per request including system — we use 3.
//
//  The model authors the analysis layers (architecture, capabilities, technical
//  highlights, code excerpts, dependency usage, production quality, skill
//  signals, entry points, verbatim manifests/docs, omissions) via the
//  `complete_analysis` tool. The MECHANICAL layers (repo name, file tree,
//  language stats, git history, authorship) are assembled here from the
//  deterministic `GitEvidenceCollector` data — never re-emitted by the model.
//

import Foundation
import Observation
import SwiftOpenAI
import SwiftyJSON

// MARK: - Agent Status

enum GitAgentStatus: Equatable {
    case idle
    case running
    case completed
    case failed(String)
}

// MARK: - Agent Error

enum GitAgentError: LocalizedError {
    case noLLMFacade
    case maxTurnsExceeded
    case agentDidNotComplete
    case invalidToolCall(String)
    case toolExecutionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noLLMFacade:
            return "LLM service is not available"
        case .maxTurnsExceeded:
            return "Agent exceeded maximum number of turns without completing"
        case .agentDidNotComplete:
            return "Agent stopped without calling complete_analysis"
        case .invalidToolCall(let msg):
            return "Invalid tool call: \(msg)"
        case .toolExecutionFailed(let msg):
            return "Tool execution failed: \(msg)"
        case .timeout:
            return "Agent timed out"
        }
    }
}

// MARK: - Git Analysis Agent

@Observable
@MainActor
class GitAnalysisAgent: AnthropicToolLoopDelegate {
    /// Version of the digest-production prompt + tool contract. Bumped on any
    /// change that alters the digest's shape; recorded in `IRProvenance` so a
    /// persisted digest is reproducible against the agent that wrote it.
    static let promptVersion = "git-digest-v1"

    // Configuration
    private let repoPath: URL
    private let authorFilter: String?
    private let modelId: String
    /// Rendered deterministic git evidence (commit history aggregates) injected into the initial context
    private let gitEvidence: String
    /// Structured deterministic git data (contributors, fileTypes, commits,
    /// branches, stats, directoryStats) — the source of the digest's MECHANICAL
    /// layers, assembled here rather than re-emitted by the model.
    private let gitData: JSON
    private weak var facade: LLMFacade?
    private var eventBus: EventBus?

    // Agent tracking
    private let agentId: String?
    private let tracker: AgentActivityTracker?

    // State
    private(set) var status: GitAgentStatus = .idle
    private(set) var currentAction: String = ""
    private(set) var progress: [String] = []
    private(set) var turnCount: Int = 0

    /// External callback for turn-by-turn progress updates (turn, maxTurns, action)
    var onTurnUpdate: (@Sendable (Int, Int, String) async -> Void)?

    // Limits (internal so they witness AnthropicToolLoopDelegate)
    let maxTurns = 50
    let timeoutSeconds: TimeInterval = 600  // 10 minutes
    /// Output ceiling per turn. The final complete_analysis digest is the
    /// largest response; 16K keeps the non-streaming call under HTTP timeouts.
    private let maxResponseTokens = 16384
    /// Consecutive text-only turns tolerated (with a tool nudge) before aborting.
    private static let maxConsecutiveNoToolTurns = 2

    // Conversation history is owned by AnthropicToolLoopRunner; cache breakpoints
    // are applied at request-build time only, never persisted.

    // Tools (built once at init; LAST tool carries the cache breakpoint that
    // caches the entire tool block — deterministic order is load-bearing)
    private let tools: [AnthropicTool]

    init(
        repoPath: URL,
        authorFilter: String? = nil,
        modelId: String,
        gitEvidence: String,
        gitData: JSON,
        facade: LLMFacade,
        eventBus: EventBus? = nil,
        agentId: String? = nil,
        tracker: AgentActivityTracker? = nil
    ) {
        self.repoPath = repoPath
        self.authorFilter = authorFilter
        self.modelId = modelId
        self.gitEvidence = gitEvidence
        self.gitData = gitData
        self.facade = facade
        self.eventBus = eventBus
        self.agentId = agentId
        self.tracker = tracker
        self.tools = Self.buildTools()
    }

    // MARK: - Public API

    /// Run the agent to explore the repository and produce a `RepositoryDigest`.
    func run() async throws -> RepositoryDigest {
        guard facade != nil else {
            throw GitAgentError.noLLMFacade
        }

        status = .running
        turnCount = 0
        progress = []

        do {
            return try await AnthropicToolLoopRunner(delegate: self).run()
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Tool Loop Delegate

    var completionToolName: String { RepositoryDigestTool.name }

    func timeoutError() -> Error { GitAgentError.timeout }
    func maxTurnsError() -> Error { GitAgentError.maxTurnsExceeded }

    func initialMessages() -> [AnthropicMessage] {
        // Anthropic conversations start with a user message; the system prompt
        // rides in the request's `system` field.
        [initialUserMessage()]
    }

    func willStartTurn(_ turn: Int) async {
        turnCount = turn
        await emitEvent(.processing(.gitAgentTurnStarted(turn: turn, maxTurns: maxTurns)))
        await updateProgress("(Turn \(turn)) Calling LLM...")
        if let agentId = agentId {
            tracker?.appendTranscript(
                agentId: agentId,
                entryType: .turn,
                content: "Turn \(turn) of \(maxTurns)",
                details: nil
            )
        }
    }

    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult {
        guard let facade = facade else { throw GitAgentError.noLLMFacade }
        let response = try await facade.anthropicMessages(
            parameters: buildParameters(messages: messages, toolChoice: .auto)
        )
        await recordUsage(response.usage, turnLabel: "turn \(turnCount)")
        return AnthropicTurnResult(response: response)
    }

    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision {
        // A pure-text turn (no tool calls) is recoverable — the paid conversation
        // state is intact. Nudge the model back onto tools (alternation holds:
        // history ends with the assistant echo), and only abort after repeated
        // consecutive text-only turns.
        if consecutiveNoToolTurns > Self.maxConsecutiveNoToolTurns {
            return .abort(GitAgentError.agentDidNotComplete)
        }
        Logger.warning("Git agent turn \(turnCount) had no tool calls — nudging (\(consecutiveNoToolTurns)/\(Self.maxConsecutiveNoToolTurns))", category: .ai)
        return .nudge("<coordinator>Continue exploring with tools, or call complete_analysis with your findings.</coordinator>")
    }

    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> RepositoryDigest {
        let digest = try buildDigest(input: call.input.mapValues { $0.value })
        await emitEvent(.processing(.gitAgentProgressUpdated(message: "Repository digest complete", turn: turnCount)))
        await updateProgress("Repository digest complete")
        status = .completed
        return digest
    }

    func completionRetryContent(for error: Error) -> String {
        // Send detailed decoding error back so the model can retry with corrected JSON.
        Logger.warning("⚠️ GitAgent: complete_analysis parsing failed, asking LLM to retry: \(error.localizedDescription)", category: .ai)
        return parsingErrorMessage(for: error)
    }

    /// Execute tool calls concurrently (arguments serialized up front so only
    /// Sendable values cross into child tasks). executeTool is nonisolated, so
    /// child tasks run on the global executor — the blocking file/ripgrep I/O
    /// never touches the main thread.
    func executeTools(_ toolCalls: [AnthropicToolUseResponseBlock]) async -> [String: AnthropicToolOutput] {
        let toolNames = toolCalls.map { $0.name }
        await updateProgress("(Turn \(turnCount)) Running: \(toolNames.joined(separator: ", "))")
        if toolCalls.count > 1 {
            Logger.info("🚀 GitAgent: Executing \(toolCalls.count) tools in parallel", category: .ai)
        }

        let argumentsById: [String: Data] = Dictionary(
            toolCalls.map { ($0.id, Self.serializeInput($0.input)) },
            uniquingKeysWith: { first, _ in first }
        )
        let results = await withTaskGroup(of: (String, String, String).self, returning: [String: (String, String)].self) { group in
            for toolUse in toolCalls {
                let toolId = toolUse.id
                let toolName = toolUse.name
                let argumentsData = argumentsById[toolId] ?? Data("{}".utf8)

                // Emit from the main actor up front so the child task does pure
                // off-actor work (no per-tool main-actor hop).
                await emitEvent(.processing(.gitAgentToolExecuting(toolName: toolName, turn: turnCount)))

                group.addTask { [self] in
                    let result = await self.executeTool(name: toolName, argumentsData: argumentsData)
                    return (toolId, toolName, result)
                }
            }

            var collected: [String: (String, String)] = [:]
            for await (toolId, toolName, result) in group {
                collected[toolId] = (toolName, result)
            }
            return collected
        }

        await updateProgress("(Turn \(turnCount)) Processing results...")

        // Map to outputs and append per-tool transcript in tool_use order.
        var outputs: [String: AnthropicToolOutput] = [:]
        for toolUse in toolCalls {
            guard let (toolName, result) = results[toolUse.id] else { continue }
            outputs[toolUse.id] = AnthropicToolOutput(content: result)
            if let agentId = agentId {
                let toolDetail = extractToolDetail(name: toolName, input: toolUse.input.mapValues { $0.value })
                let displayName = toolDisplayName(toolName)
                let content = toolDetail.isEmpty ? displayName : "\(displayName): \(toolDetail)"
                tracker?.appendTranscript(
                    agentId: agentId,
                    entryType: .tool,
                    content: content,
                    details: nil
                )
            }
        }
        return outputs
    }

    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> RepositoryDigest? {
        Logger.warning("⚠️ GitAgent: Max turns (\(maxTurns)) reached, forcing completion...", category: .ai)
        await updateProgress("(Turn \(turnCount + 1)) Forcing completion...")
        guard let facade = facade else { throw GitAgentError.noLLMFacade }
        guard let forcedDigest = try await forceCompletion(facade: facade, messages: messages) else {
            return nil
        }
        status = .completed
        return forcedDigest
    }

    // MARK: - Request Building

    /// Static system prompt with a cache breakpoint (caches tools + system —
    /// tools render before system in the prompt).
    private func systemContent() -> AnthropicSystemContent {
        let prompt = GitAgentPrompts.systemPrompt(authorFilter: authorFilter)
        return .blocks([AnthropicSystemBlock(text: prompt, cacheControl: .ephemeral)])
    }

    private func buildParameters(messages: [AnthropicMessage], toolChoice: AnthropicToolChoice) -> AnthropicMessageParameter {
        AnthropicMessageParameter(
            model: modelId,
            messages: applyMovingCacheBreakpoint(to: messages),
            system: systemContent(),
            maxTokens: maxResponseTokens,
            stream: false,
            tools: tools,
            toolChoice: toolChoice
        )
    }

    /// Place the moving conversation breakpoint on the last markable content
    /// block of the final message. Applied at request-build time only — the
    /// stored history stays clean, so the breakpoint moves naturally each turn
    /// and turn N+1 reads the prefix turn N wrote.
    private func applyMovingCacheBreakpoint(to messages: [AnthropicMessage]) -> [AnthropicMessage] {
        guard !messages.isEmpty else { return messages }
        var result = messages
        for messageIndex in result.indices.reversed() {
            let blocks = AnthropicCacheBreakpointPlanner.contentBlocks(of: result[messageIndex])
            for blockIndex in blocks.indices.reversed() {
                guard let marked = AnthropicCacheBreakpointPlanner.addingCacheControl(
                    to: blocks[blockIndex], cacheControl: .ephemeral) else { continue }
                var newBlocks = blocks
                newBlocks[blockIndex] = marked
                result[messageIndex] = AnthropicMessage(role: result[messageIndex].role, content: .blocks(newBlocks))
                return result
            }
        }
        return result
    }

    // MARK: - Usage Tracking

    /// Log per-turn token usage. From turn 2 onward cache_read should cover
    /// tools + system + prior conversation; a zero there is the regression signal.
    private func recordUsage(_ usage: AnthropicUsage, turnLabel: String) async {
        let cacheRead = usage.cacheReadInputTokens ?? 0
        let cacheCreate = usage.cacheCreationInputTokens ?? 0

        Logger.info(
            "🤖 GitAgent \(turnLabel) usage (\(modelId)): input=\(usage.inputTokens) cache_read=\(cacheRead) cache_create=\(cacheCreate) output=\(usage.outputTokens)",
            category: .ai
        )

        await emitEvent(.llm(.tokenUsageReceived(
            modelId: modelId,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreate,
            reasoningTokens: 0,
            source: .gitAgent
        )))

        if let agentId = agentId {
            tracker?.addTokenUsage(
                agentId: agentId,
                input: usage.inputTokens,
                output: usage.outputTokens,
                cached: cacheRead
            )
        }
    }

    // MARK: - Forced Completion

    /// Forces the agent to call complete_analysis when max turns is reached.
    /// Appends a coordinator instruction to the last user message (preserving
    /// strict user/assistant alternation) and forces the tool via tool_choice.
    /// If parsing or validation fails, sends the validation error back once and
    /// re-requests completion; a second failure propagates as before
    /// (nil → maxTurnsExceeded).
    private func forceCompletion(facade: LLMFacade, messages incomingMessages: [AnthropicMessage]) async throws -> RepositoryDigest? {
        var messages = incomingMessages
        appendUserText("""
            <coordinator>
            CRITICAL: You have reached the maximum number of exploration turns.
            You MUST call the complete_analysis tool NOW with the repository digest from your
            findings so far. Provide the analysis layers (architecture, capabilities, technical
            highlights, code excerpts, dependency usage, production quality, skill signals, entry
            points, verbatim manifests/docs, omissions) — keep claims grounded in what you saw.
            Do NOT call any other tools - only call complete_analysis immediately.
            </coordinator>
            """, to: &messages)

        // One forced call plus a single corrective round-trip on parse/validation failure
        for attempt in 1...2 {
            let response = try await facade.anthropicMessages(
                parameters: buildParameters(messages: messages, toolChoice: .tool(name: RepositoryDigestTool.name))
            )

            await recordUsage(response.usage, turnLabel: "forced completion (attempt \(attempt))")

            let toolUses = response.content.compactMap { block -> AnthropicToolUseResponseBlock? in
                if case .toolUse(let toolUse) = block { return toolUse }
                return nil
            }

            guard let completionCall = toolUses.first(where: { $0.name == RepositoryDigestTool.name }) else {
                Logger.error("❌ GitAgent: Forced completion failed - no complete_analysis call received (attempt \(attempt))", category: .ai)
                return nil
            }

            do {
                let digest = try buildDigest(input: completionCall.input.mapValues { $0.value })
                await emitEvent(.processing(.gitAgentProgressUpdated(message: "Repository digest complete (forced)!", turn: turnCount + 1)))
                await updateProgress("Repository digest complete (forced)!")
                Logger.info("✅ GitAgent: Forced completion succeeded", category: .ai)
                return digest
            } catch where attempt == 1 {
                // Send the validation error back so the model can correct its JSON once.
                // Every tool_use in the response gets a tool_result (alternation +
                // tool_result pairing requirements).
                Logger.warning("⚠️ GitAgent: Forced completion parsing failed, sending corrective round-trip: \(error.localizedDescription)", category: .ai)
                messages.append(assistantEchoMessage(from: response))
                var resultBlocks: [AnthropicContentBlock] = []
                for toolUse in toolUses {
                    let content = toolUse.id == completionCall.id
                        ? parsingErrorMessage(for: error)
                        : "Not executed: only complete_analysis is accepted at this point."
                    resultBlocks.append(.toolResult(AnthropicToolResultBlock(
                        toolUseId: toolUse.id,
                        content: content,
                        isError: true
                    )))
                }
                messages.append(AnthropicMessage(role: "user", content: .blocks(resultBlocks)))
            } catch {
                Logger.error("❌ GitAgent: Forced completion parsing failed after corrective retry: \(error.localizedDescription)", category: .ai)
                return nil
            }
        }

        return nil
    }

    // MARK: - Tool Execution

    /// Serialize a tool_use input dictionary to JSON Data for parameter decoding.
    private static func serializeInput(_ input: [String: AnthropicDynamicValue]) -> Data {
        input.jsonData
    }

    /// nonisolated (class is @MainActor): tool bodies are synchronous blocking
    /// I/O (file reads, ripgrep via Process), so execution must leave the main
    /// actor — under SE-0338 a nonisolated async function runs on the global
    /// executor, letting the per-turn task group genuinely parallelize. Only
    /// touches the immutable `repoPath` and stateless static tool functions.
    nonisolated private func executeTool(name: String, argumentsData argsData: Data) async -> String {
        do {
            switch name {
            case ReadFileTool.name:
                let params = try JSONDecoder().decode(ReadFileTool.Parameters.self, from: argsData)
                let result = try ReadFileTool.execute(parameters: params, repoRoot: repoPath)
                return formatToolResult(result)

            case ListDirectoryTool.name:
                let params = try JSONDecoder().decode(ListDirectoryTool.Parameters.self, from: argsData)
                let result = try ListDirectoryTool.execute(parameters: params, repoRoot: repoPath)
                return result.formattedTree

            case GlobSearchTool.name:
                let params = try JSONDecoder().decode(GlobSearchTool.Parameters.self, from: argsData)
                let result = try GlobSearchTool.execute(parameters: params, repoRoot: repoPath)
                return formatGlobResult(result)

            case GrepSearchTool.name:
                let params = try JSONDecoder().decode(GrepSearchTool.Parameters.self, from: argsData)
                let result = try GrepSearchTool.execute(parameters: params, repoRoot: repoPath)
                return result.formatted

            default:
                return "Unknown tool: \(name)"
            }
        } catch {
            Logger.error("❌ Tool execution error (\(name)): \(error.localizedDescription)", category: .ai)
            return "Error: \(error.localizedDescription)"
        }
    }

    nonisolated private func formatToolResult(_ result: ReadFileTool.Result) -> String {
        var output = "File content (lines \(result.startLine)-\(result.endLine) of \(result.totalLines)):\n"
        output += result.content
        if result.hasMore {
            output += "\n\n[Note: File has more content. Use offset=\(result.endLine + 1) to read more.]"
        }
        return output
    }

    nonisolated private func formatGlobResult(_ result: GlobSearchTool.Result) -> String {
        var lines: [String] = ["Found \(result.totalMatches) files matching pattern:"]
        for file in result.files {
            let sizeStr = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
            lines.append("  \(file.relativePath) (\(sizeStr))")
        }
        if result.truncated {
            lines.append("  ... and \(result.totalMatches - result.files.count) more")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Message Building

    private func initialUserMessage() -> AnthropicMessage {
        let repoName = repoPath.lastPathComponent
        var prompt = """
        Please analyze the git repository at: \(repoPath.path)
        Repository name: \(repoName)
        """

        if !gitEvidence.isEmpty {
            prompt += """


            <git_evidence>
            \(gitEvidence)
            </git_evidence>

            The git evidence above is deterministic data gathered from the repository's commit \
            history (each section states its coverage). Use it to ground skill claims in \
            longitudinal evidence: tenure in a directory (first/last commit dates), sustained \
            activity (commits and churn per area, monthly activity), and recency.
            """
        }

        prompt += """


        Start by exploring the directory structure to understand the project layout, then examine key files to assess the developer's skills.
        """

        return .user(prompt)
    }

    /// Echo the assistant response (text + tool_use blocks) back into history so
    /// every tool_use is paired with a tool_result in the following user message.
    private func assistantEchoMessage(from response: AnthropicMessageResponse) -> AnthropicMessage {
        var blocks: [AnthropicContentBlock] = []
        for block in response.content {
            switch block {
            case .text(let textBlock):
                let trimmed = textBlock.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(.text(AnthropicTextBlock(text: textBlock.text)))
                }
            case .toolUse(let toolUse):
                blocks.append(.toolUse(AnthropicToolUseBlock(
                    id: toolUse.id,
                    name: toolUse.name,
                    input: toolUse.input.mapValues { $0.value }
                )))
            }
        }
        if blocks.isEmpty {
            // The API rejects empty assistant messages
            blocks.append(.text(AnthropicTextBlock(text: "(continuing)")))
        }
        return AnthropicMessage(role: "assistant", content: .blocks(blocks))
    }

    /// Append a text block to the trailing user message (or start a new one if
    /// the conversation ends with an assistant turn) — preserves strict
    /// user/assistant alternation.
    private func appendUserText(_ text: String, to messages: inout [AnthropicMessage]) {
        let block = AnthropicContentBlock.text(AnthropicTextBlock(text: text))
        if let last = messages.last, last.role == "user" {
            var blocks = AnthropicCacheBreakpointPlanner.contentBlocks(of: last)
            blocks.append(block)
            messages[messages.count - 1] = AnthropicMessage(role: "user", content: .blocks(blocks))
        } else {
            messages.append(AnthropicMessage(role: "user", content: .blocks([block])))
        }
    }

    // MARK: - Tool Definitions

    /// Fixed, deterministic tool order (prompt-cache invariant: tools render at
    /// position 0; any reorder invalidates the entire cache). The cache
    /// breakpoint on the LAST tool caches the whole tool block.
    private static func buildTools() -> [AnthropicTool] {
        [
            functionTool(ReadFileTool.self),
            functionTool(ListDirectoryTool.self),
            functionTool(GlobSearchTool.self),
            functionTool(GrepSearchTool.self),
            functionTool(RepositoryDigestTool.self, cached: true)
        ]
    }

    private static func functionTool<T: AgentTool>(_ tool: T.Type, cached: Bool = false) -> AnthropicTool {
        .function(AnthropicFunctionTool(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.parametersSchema,
            cacheControl: cached ? .ephemeral : nil
        ))
    }

    // MARK: - Digest Building

    private func parsingErrorMessage(for error: Error) -> String {
        // Extract specific decoding error details if available
        var specificError = error.localizedDescription
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, let context):
                specificError = "Missing required field '\(key.stringValue)' at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .typeMismatch(let type, let context):
                specificError = "Type mismatch for '\(context.codingPath.map(\.stringValue).joined(separator: "."))': expected \(type)"
            case .valueNotFound(let type, let context):
                specificError = "Missing value for '\(context.codingPath.map(\.stringValue).joined(separator: "."))': expected \(type)"
            case .dataCorrupted(let context):
                specificError = "Data corrupted at '\(context.codingPath.map(\.stringValue).joined(separator: "."))': \(context.debugDescription)"
            @unknown default:
                break
            }
        }

        return """
        ERROR: Failed to parse complete_analysis arguments.

        \(specificError)

        Your input must match the repository-digest structure EXACTLY (all keys present;
        objects inside arrays must include their required keys):
        {
          "architecture": "string",
          "capabilities": ["string"],
          "technicalHighlights": [
            { "title": "string", "description": "string", "verbatimExcerpt": "string",
              "path": "string", "lineRange": "string (optional)", "whyNotable": "string" }
          ],
          "codeExcerpts": [
            { "purpose": "string", "path": "string", "lineRange": "string (optional)",
              "excerpt": "string", "tiedToClaim": "string (optional)" }
          ],
          "dependencyUsage": [
            { "dependency": "string", "importCount": 0, "usageNotes": "string" }
          ],
          "productionQuality": {
            "testing": "string", "cicd": "string", "infraAndDeploy": "string",
            "observability": "string", "lintFormatTypeSafety": "string",
            "docsQuality": "string", "accessibilityI18n": "string", "securityTooling": "string"
          },
          "skillSignals": [
            { "skill": "string", "strength": "strong|moderate|weak", "anchors": ["string"] }
          ],
          "entryPoints": ["string"],
          "manifests": [ { "path": "string", "content": "string" } ],
          "readmeAndDocs": [ { "path": "string", "content": "string" } ],
          "omissions": "string"
        }

        Strings you cannot fill may be empty ("") but the KEY must still be present.
        Please retry with corrected JSON.
        """
    }

    /// Build the full `RepositoryDigest`: decode the model-authored analysis
    /// layers, then graft on the MECHANICAL layers assembled from the
    /// deterministic git data, and attach provenance.
    private func buildDigest(input: [String: Any]) throws -> RepositoryDigest {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: input)
        } catch {
            throw GitAgentError.invalidToolCall("Could not serialize complete_analysis input: \(error.localizedDescription)")
        }

        let params: RepositoryDigestTool.Parameters
        do {
            params = try JSONDecoder().decode(RepositoryDigestTool.Parameters.self, from: data)
        } catch {
            throw GitAgentError.invalidToolCall("Failed to decode repository digest: \(error.localizedDescription)")
        }

        let repoName = repoPath.lastPathComponent
        let mechanical = mechanicalLayers()
        let provenance = IRProvenance(
            sourceArtifactId: repoName,
            modelId: modelId,
            promptVersion: Self.promptVersion,
            createdAt: Date(),
            analyzedCommit: analyzedCommit(),
            explorationTurnCount: turnCount,
            toolVersions: nil
        )

        return RepositoryDigest(
            repoName: repoName,
            fileTree: mechanical.fileTree,
            languageStats: mechanical.languageStats,
            manifests: params.manifests,
            readmeAndDocs: params.readmeAndDocs,
            entryPoints: params.entryPoints,
            gitHistory: mechanical.gitHistory,
            authorship: mechanical.authorship,
            dependencyUsage: params.dependencyUsage,
            architecture: params.architecture,
            capabilities: params.capabilities,
            technicalHighlights: params.technicalHighlights,
            codeExcerpts: params.codeExcerpts,
            productionQuality: params.productionQuality,
            skillSignals: params.skillSignals,
            omissions: params.omissions,
            provenance: provenance
        )
    }

    // MARK: - Mechanical Layers (deterministic git evidence → IR types)

    /// HEAD commit recorded in provenance (best-effort; nil when unavailable,
    /// e.g. filesystem-fallback evidence).
    private func analyzedCommit() -> String? {
        let commit = gitData["lastCommit"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return commit.isEmpty ? nil : commit
    }

    /// Map the deterministic `GitEvidenceCollector` JSON into the digest's
    /// MECHANICAL layers. The model never re-emits these — they are lossless and
    /// cheap, so we derive them here from ground truth.
    private func mechanicalLayers() -> (fileTree: String, languageStats: [LanguageStat], gitHistory: GitHistory, authorship: [ContributorShare]) {
        let languageStats = languageStatsFromFileTypes()
        let gitHistory = gitHistoryFromEvidence()
        let authorship = authorshipFromContributors()
        // GitEvidenceCollector does not gather a full file tree; the agent's
        // exploration covers structure, and `omissions` records what was skipped.
        // The rendered evidence carries the directory/file activity table, which
        // is the closest deterministic "tree" signal we have without re-walking.
        let fileTree = directoryActivityTree()
        return (fileTree, languageStats, gitHistory, authorship)
    }

    /// Per-language LOC/file/percent. GitEvidenceCollector aggregates by file
    /// EXTENSION (not LOC), so `loc` is left 0 and the file count + percentage
    /// (by file share) carry the signal; the extension stands in for language.
    private func languageStatsFromFileTypes() -> [LanguageStat] {
        let fileTypes = gitData["fileTypes"].arrayValue
        let total = fileTypes.reduce(0) { $0 + $1["count"].intValue }
        guard total > 0 else { return [] }
        return fileTypes.map { entry in
            let count = entry["count"].intValue
            return LanguageStat(
                language: entry["extension"].stringValue,
                loc: 0,
                fileCount: count,
                percent: Double(count) / Double(total) * 100.0
            )
        }
    }

    private func gitHistoryFromEvidence() -> GitHistory {
        let commitCount = gitData["totalCommits"].intValue
        let first = gitData["firstCommit"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = gitData["lastCommit"].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var dateRange = ""
        if !first.isEmpty || !last.isEmpty {
            dateRange = "\(first.isEmpty ? "?" : first) → \(last.isEmpty ? "?" : last)"
        }
        // Top-churn directories stand in for top-churn files (the evidence
        // aggregates per top-level directory, not per file).
        let topChurn = gitData["directoryStats"].arrayValue
            .prefix(10)
            .map { "\($0["directory"].stringValue) (+\($0["linesAdded"].intValue)/-\($0["linesDeleted"].intValue))" }
        let branches = gitData["branches"].arrayValue
            .map { $0.stringValue.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return GitHistory(
            commitCount: commitCount,
            dateRange: dateRange,
            cadence: "",
            topChurnFiles: Array(topChurn),
            branches: branches,
            tags: []
        )
    }

    /// Contributor commit/LOC share from the deterministic contributor list.
    /// The collector gathers commit counts (not LOC), so `locShare` mirrors the
    /// commit share; blame on core files is not gathered and is left nil.
    private func authorshipFromContributors() -> [ContributorShare] {
        let contributors = gitData["contributors"].arrayValue
        let totalCommits = contributors.reduce(0) { $0 + $1["commits"].intValue }
        guard totalCommits > 0 else { return [] }
        return contributors.map { entry in
            let commits = entry["commits"].intValue
            let share = Double(commits) / Double(totalCommits)
            return ContributorShare(
                name: entry["name"].stringValue,
                commitShare: share,
                locShare: share,
                blameOnCoreFiles: nil
            )
        }
    }

    /// Deterministic "tree" rendering from the per-directory activity table
    /// (git-backed) or the per-directory file counts (filesystem fallback).
    private func directoryActivityTree() -> String {
        let dirStats = gitData["directoryStats"].arrayValue
        if !dirStats.isEmpty {
            return dirStats.map { dir in
                "\(dir["directory"].stringValue)/ — \(dir["commits"].intValue) commits, "
                + "+\(dir["linesAdded"].intValue)/-\(dir["linesDeleted"].intValue) lines"
            }.joined(separator: "\n")
        }
        let fileStats = gitData["directoryFileStats"].arrayValue
        if !fileStats.isEmpty {
            return fileStats.map { dir in
                "\(dir["directory"].stringValue)/ — \(dir["files"].intValue) files"
            }.joined(separator: "\n")
        }
        return ""
    }

    // MARK: - Progress Updates

    private func updateProgress(_ message: String) async {
        currentAction = message
        progress.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
        Logger.info("🤖 GitAgent: \(message)", category: .ai)
        // Notify external listener (e.g. DocumentIngestionSheet status)
        await onTurnUpdate?(turnCount, maxTurns, message)
        // Update agent-specific status message in tracker (shown in BackgroundAgentStatusBar)
        // Note: We only emit extractionStateChanged if there's no tracker, to avoid duplicate status displays
        if let agentId = agentId {
            tracker?.updateStatusMessage(agentId: agentId, message: message)
        } else {
            // Fallback for agents not using the tracker - emit extraction state
            await emitEvent(.processing(.extractionStateChanged(inProgress: true, statusMessage: "Git analysis: \(message)")))
        }
    }

    /// Extract a human-readable detail from tool input for logging
    private func extractToolDetail(name: String, input: [String: Any]) -> String {
        switch name {
        case ReadFileTool.name:
            if let path = input["path"] as? String {
                // Show just the filename or last path component
                let url = URL(fileURLWithPath: path)
                return url.lastPathComponent
            }
        case ListDirectoryTool.name:
            if let path = input["path"] as? String {
                let url = URL(fileURLWithPath: path)
                let depth = input["depth"] as? Int ?? 1
                return "\(url.lastPathComponent)/ (depth: \(depth))"
            }
        case GlobSearchTool.name:
            if let pattern = input["pattern"] as? String {
                return "pattern: \(pattern)"
            }
        case GrepSearchTool.name:
            if let pattern = input["pattern"] as? String {
                if let glob = input["glob"] as? String {
                    return "'\(pattern)' in \(glob)"
                }
                return "'\(pattern)'"
            }
        case RepositoryDigestTool.name:
            return "submitting digest"
        default:
            break
        }

        return ""
    }

    /// Convert tool name to human-readable display name
    private func toolDisplayName(_ name: String) -> String {
        switch name {
        case ReadFileTool.name: return "Read file"
        case ListDirectoryTool.name: return "List directory"
        case GlobSearchTool.name: return "Glob search"
        case GrepSearchTool.name: return "Grep search"
        case RepositoryDigestTool.name: return "Submit digest"
        default: return name
        }
    }

    // MARK: - Event Emission

    private func emitEvent(_ event: OnboardingEvent) async {
        guard let eventBus = eventBus else { return }
        await eventBus.publish(event)
    }
}
