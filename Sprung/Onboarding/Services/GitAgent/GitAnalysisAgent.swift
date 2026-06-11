//
//  GitAnalysisAgent.swift
//  Sprung
//
//  Multi-turn agent for analyzing git repositories.
//  Uses filesystem tools to explore codebases and generate skill assessments.
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
//  Stage A (this agent's tool loop) produces a CANDIDATE inventory; Stage B
//  (GitStageBVerifier) evidence-checks the candidate skills before the result
//  is returned to callers.
//

import Foundation
import Observation
import SwiftOpenAI

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

// MARK: - Analysis Result

/// Git repository analysis result containing skills and narrative cards.
struct GitAnalysisResult: Codable {
    let skills: [Skill]
    let narrativeCards: [KnowledgeCard]
    let repoName: String
    let analyzedAt: Date

    init(skills: [Skill] = [], narrativeCards: [KnowledgeCard] = [], repoName: String, analyzedAt: Date = Date()) {
        self.skills = skills
        self.narrativeCards = narrativeCards
        self.repoName = repoName
        self.analyzedAt = analyzedAt
    }
}

// MARK: - Git Analysis Agent

@Observable
@MainActor
class GitAnalysisAgent {
    // Configuration
    private let repoPath: URL
    private let authorFilter: String?
    private let modelId: String
    /// Rendered deterministic git evidence (commit history aggregates) injected into the initial context
    private let gitEvidence: String
    private weak var facade: LLMFacade?
    private var eventBus: EventCoordinator?

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

    // Limits
    private let maxTurns = 50
    private let timeoutSeconds: TimeInterval = 600  // 10 minutes
    /// Output ceiling per turn. The final complete_analysis inventory is the
    /// largest response; 16K keeps the non-streaming call under HTTP timeouts.
    private let maxResponseTokens = 16384
    /// Consecutive text-only turns tolerated (with a tool nudge) before aborting.
    private static let maxConsecutiveNoToolTurns = 2
    private var consecutiveNoToolTurns = 0

    // Conversation state (clean history — cache breakpoints are applied at
    // request-build time only, never persisted)
    private var messages: [AnthropicMessage] = []

    // Tools (built once at init; LAST tool carries the cache breakpoint that
    // caches the entire tool block — deterministic order is load-bearing)
    private let tools: [AnthropicTool]

    init(
        repoPath: URL,
        authorFilter: String? = nil,
        modelId: String,
        gitEvidence: String,
        facade: LLMFacade,
        eventBus: EventCoordinator? = nil,
        agentId: String? = nil,
        tracker: AgentActivityTracker? = nil
    ) {
        self.repoPath = repoPath
        self.authorFilter = authorFilter
        self.modelId = modelId
        self.gitEvidence = gitEvidence
        self.facade = facade
        self.eventBus = eventBus
        self.agentId = agentId
        self.tracker = tracker
        self.tools = Self.buildTools()
    }

    // MARK: - Public API

    /// Run the agent to analyze the repository
    func run() async throws -> GitAnalysisResult {
        guard let facade = facade else {
            throw GitAgentError.noLLMFacade
        }

        status = .running
        turnCount = 0
        messages = []
        progress = []
        consecutiveNoToolTurns = 0

        // Anthropic conversations start with a user message; the system prompt
        // rides in the request's `system` field.
        messages.append(initialUserMessage())

        let startTime = Date()

        do {
            while turnCount < maxTurns {
                // Check timeout
                if Date().timeIntervalSince(startTime) > timeoutSeconds {
                    throw GitAgentError.timeout
                }

                turnCount += 1
                await emitEvent(.processing(.gitAgentTurnStarted(turn: turnCount, maxTurns: maxTurns)))
                await updateProgress("(Turn \(turnCount)) Calling LLM...")

                // Add turn marker to transcript
                if let agentId = agentId {
                    tracker?.appendTranscript(
                        agentId: agentId,
                        entryType: .turn,
                        content: "Turn \(turnCount) of \(maxTurns)",
                        details: nil
                    )
                }

                // Call the Anthropic Messages API with tools (non-streaming)
                let response = try await facade.anthropicMessages(
                    parameters: buildParameters(toolChoice: .auto)
                )

                await recordUsage(response.usage, turnLabel: "turn \(turnCount)")

                // Split response content into text and tool_use blocks
                let toolUses = response.content.compactMap { block -> AnthropicToolUseResponseBlock? in
                    if case .toolUse(let toolUse) = block { return toolUse }
                    return nil
                }

                // Add assistant message to history (echoes text + tool_use blocks
                // so every tool_use has its tool_result in the next user message)
                messages.append(assistantEchoMessage(from: response))

                // A pure-text turn (no tool calls) is recoverable — the paid
                // conversation state is intact. Nudge the model back onto tools
                // (alternation holds: history ends with the assistant echo), and
                // only abort after repeated consecutive text-only turns.
                guard !toolUses.isEmpty else {
                    consecutiveNoToolTurns += 1
                    if consecutiveNoToolTurns > Self.maxConsecutiveNoToolTurns {
                        throw GitAgentError.agentDidNotComplete
                    }
                    Logger.warning("Git agent turn \(turnCount) had no tool calls — nudging (\(consecutiveNoToolTurns)/\(Self.maxConsecutiveNoToolTurns))", category: .ai)
                    appendUserText("<coordinator>Continue exploring with tools, or call complete_analysis with your findings.</coordinator>")
                    continue
                }
                consecutiveNoToolTurns = 0

                // Check for completion tool first (terminates the agent loop)
                if let completionCall = toolUses.first(where: { $0.name == CompleteAnalysisTool.name }) {
                    do {
                        let candidates = try parseCompleteAnalysis(input: completionCall.input.mapValues { $0.value })
                        await emitEvent(.processing(.gitAgentProgressUpdated(message: "Candidate inventory complete", turn: turnCount)))
                        await updateProgress("Candidate inventory complete")
                        let verified = await runStageB(on: candidates, facade: facade)
                        status = .completed
                        return verified
                    } catch {
                        // Send detailed error back as a tool_result so the model can
                        // retry with corrected JSON. Every OTHER tool_use in this turn
                        // still gets a real result (Anthropic requires one per tool_use).
                        Logger.warning("⚠️ GitAgent: complete_analysis parsing failed, asking LLM to retry: \(error.localizedDescription)", category: .ai)
                        var resultBlocks: [AnthropicContentBlock] = []
                        for toolUse in toolUses {
                            if toolUse.id == completionCall.id {
                                resultBlocks.append(.toolResult(AnthropicToolResultBlock(
                                    toolUseId: toolUse.id,
                                    content: parsingErrorMessage(for: error),
                                    isError: true
                                )))
                            } else {
                                let result = await executeTool(name: toolUse.name, argumentsData: Self.serializeInput(toolUse.input))
                                resultBlocks.append(.toolResult(AnthropicToolResultBlock(
                                    toolUseId: toolUse.id,
                                    content: result
                                )))
                            }
                        }
                        messages.append(AnthropicMessage(role: "user", content: .blocks(resultBlocks)))
                        continue
                    }
                }

                // Log parallel execution
                let toolNames = toolUses.map { $0.name }
                await updateProgress("(Turn \(turnCount)) Running: \(toolNames.joined(separator: ", "))")
                if toolUses.count > 1 {
                    Logger.info("🚀 GitAgent: Executing \(toolUses.count) tools in parallel", category: .ai)
                }

                // Execute tool calls concurrently (arguments serialized up front
                // so only Sendable values cross into child tasks). executeTool is
                // nonisolated, so child tasks run on the global executor — the
                // blocking file/ripgrep I/O never touches the main thread.
                let argumentsById: [String: Data] = Dictionary(
                    toolUses.map { ($0.id, Self.serializeInput($0.input)) },
                    uniquingKeysWith: { first, _ in first }
                )
                let results = await withTaskGroup(of: (String, String, String).self, returning: [String: (String, String)].self) { group in
                    for toolUse in toolUses {
                        let toolId = toolUse.id
                        let toolName = toolUse.name
                        let argumentsData = argumentsById[toolId] ?? Data("{}".utf8)

                        // Emit from the main actor up front so the child task does
                        // pure off-actor work (no per-tool main-actor hop).
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

                // Send all tool results back in ONE user message, in tool_use order
                await updateProgress("(Turn \(turnCount)) Processing results...")
                var resultBlocks: [AnthropicContentBlock] = []
                for toolUse in toolUses {
                    guard let (toolName, result) = results[toolUse.id] else { continue }
                    resultBlocks.append(.toolResult(AnthropicToolResultBlock(
                        toolUseId: toolUse.id,
                        content: result
                    )))

                    // Add tool call to transcript
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
                messages.append(AnthropicMessage(role: "user", content: .blocks(resultBlocks)))
            }

            // Max turns reached - force completion
            Logger.warning("⚠️ GitAgent: Max turns (\(maxTurns)) reached, forcing completion...", category: .ai)
            await updateProgress("(Turn \(turnCount + 1)) Forcing completion...")

            if let forcedCandidates = try await forceCompletion(facade: facade) {
                let verified = await runStageB(on: forcedCandidates, facade: facade)
                status = .completed
                return verified
            }

            throw GitAgentError.maxTurnsExceeded

        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Request Building

    /// Static system prompt with a cache breakpoint (caches tools + system —
    /// tools render before system in the prompt).
    private func systemContent() -> AnthropicSystemContent {
        let prompt = GitAgentPrompts.systemPrompt(authorFilter: authorFilter)
        return .blocks([AnthropicSystemBlock(text: prompt, cacheControl: .ephemeral)])
    }

    private func buildParameters(toolChoice: AnthropicToolChoice) -> AnthropicMessageParameter {
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
            let blocks = Self.contentBlocks(of: result[messageIndex])
            for blockIndex in blocks.indices.reversed() {
                guard let marked = Self.addingEphemeralCacheControl(to: blocks[blockIndex]) else { continue }
                var newBlocks = blocks
                newBlocks[blockIndex] = marked
                result[messageIndex] = AnthropicMessage(role: result[messageIndex].role, content: .blocks(newBlocks))
                return result
            }
        }
        return result
    }

    private static func contentBlocks(of message: AnthropicMessage) -> [AnthropicContentBlock] {
        switch message.content {
        case .text(let text):
            return [.text(AnthropicTextBlock(text: text))]
        case .blocks(let blocks):
            return blocks
        }
    }

    /// tool_use blocks cannot carry cache_control; everything else can.
    private static func addingEphemeralCacheControl(to block: AnthropicContentBlock) -> AnthropicContentBlock? {
        switch block {
        case .text(let textBlock):
            return .text(AnthropicTextBlock(text: textBlock.text, cacheControl: .ephemeral))
        case .toolResult(let resultBlock):
            return .toolResult(AnthropicToolResultBlock(
                toolUseId: resultBlock.toolUseId,
                content: resultBlock.content,
                isError: resultBlock.isError ?? false,
                cacheControl: .ephemeral
            ))
        case .image(let imageBlock):
            return .image(AnthropicImageBlock(source: imageBlock.source, cacheControl: .ephemeral))
        case .document(let documentBlock):
            return .document(AnthropicDocumentBlock(source: documentBlock.source, cacheControl: .ephemeral))
        case .toolUse:
            return nil
        }
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
    private func forceCompletion(facade: LLMFacade) async throws -> GitAnalysisResult? {
        appendUserText("""
            <coordinator>
            CRITICAL: You have reached the maximum number of analysis turns.
            You MUST call the complete_analysis tool NOW with your findings so far.
            Summarize what you've discovered and output the card inventory.
            Do NOT call any other tools - only call complete_analysis immediately.
            </coordinator>
            """)

        // One forced call plus a single corrective round-trip on parse/validation failure
        for attempt in 1...2 {
            let response = try await facade.anthropicMessages(
                parameters: buildParameters(toolChoice: .tool(name: CompleteAnalysisTool.name))
            )

            await recordUsage(response.usage, turnLabel: "forced completion (attempt \(attempt))")

            let toolUses = response.content.compactMap { block -> AnthropicToolUseResponseBlock? in
                if case .toolUse(let toolUse) = block { return toolUse }
                return nil
            }

            guard let completionCall = toolUses.first(where: { $0.name == CompleteAnalysisTool.name }) else {
                Logger.error("❌ GitAgent: Forced completion failed - no complete_analysis call received (attempt \(attempt))", category: .ai)
                return nil
            }

            do {
                let result = try parseCompleteAnalysis(input: completionCall.input.mapValues { $0.value })
                await emitEvent(.processing(.gitAgentProgressUpdated(message: "Analysis complete (forced)!", turn: turnCount + 1)))
                await updateProgress("Analysis complete (forced)!")
                Logger.info("✅ GitAgent: Forced completion succeeded", category: .ai)
                return result
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

    // MARK: - Stage B (Evidence Deep-Dive)

    /// Stage A's complete_analysis output is a CANDIDATE inventory. Stage B
    /// re-checks every candidate skill against the deterministic git evidence
    /// and demands concrete citations before a skill survives at its claimed
    /// proficiency. Stage B failures degrade gracefully (candidates kept).
    private func runStageB(on candidates: GitAnalysisResult, facade: LLMFacade) async -> GitAnalysisResult {
        guard !candidates.skills.isEmpty else { return candidates }

        await updateProgress("Stage B: evidence-checking \(candidates.skills.count) candidate skills...")
        if let agentId = agentId {
            tracker?.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Stage B: verifying \(candidates.skills.count) candidate skills",
                details: nil
            )
        }

        let verifier = GitStageBVerifier(facade: facade, modelId: modelId, gitEvidence: gitEvidence)
        let verifiedSkills = await verifier.verify(candidates: candidates.skills) { [weak self] message in
            await self?.updateProgress(message)
        }

        await updateProgress("Analysis complete!")
        await emitEvent(.processing(.gitAgentProgressUpdated(message: "Analysis complete!", turn: turnCount)))

        return GitAnalysisResult(
            skills: verifiedSkills,
            narrativeCards: candidates.narrativeCards,
            repoName: candidates.repoName,
            analyzedAt: candidates.analyzedAt
        )
    }

    // MARK: - Tool Execution

    /// Serialize a tool_use input dictionary to JSON Data for parameter decoding.
    private static func serializeInput(_ input: [String: AnthropicDynamicValue]) -> Data {
        let plain = input.mapValues { $0.value }
        return (try? JSONSerialization.data(withJSONObject: plain)) ?? Data("{}".utf8)
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
            history (each section states its coverage). Use it to ground proficiency judgments in \
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
    private func appendUserText(_ text: String) {
        let block = AnthropicContentBlock.text(AnthropicTextBlock(text: text))
        if let last = messages.last, last.role == "user" {
            var blocks = Self.contentBlocks(of: last)
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
            functionTool(CompleteAnalysisTool.self, cached: true)
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

    // MARK: - Result Parsing

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

        Your input must match this EXACT structure:
        {
          "documentType": "git_analysis",
          "cards": [
            {
              "cardType": "string (required) - one of: skill, project, achievement, employment, education",
              "proposedTitle": "string (required) - specific, descriptive title",
              "evidenceStrength": "string (required) - one of: primary, supporting, mention",
              "evidenceLocations": ["string"],  // required - file paths with line numbers
              "keyFacts": ["string"],  // required
              "technologies": ["string"],  // required
              "quantifiedOutcomes": ["string"],  // required (may be empty)
              "crossReferences": ["string"],  // required (may be empty)
              "dateRange": "string (optional) - e.g., '2023-2024'",
              "extractionNotes": "string (optional)",
              "proficiency": "string (REQUIRED for skill cards) - one of: expert, proficient, familiar",
              "category": "string (REQUIRED for skill cards) - skill-bank category",
              "atsVariants": ["string"]  // skill cards - search-term variants of the skill's NAME
            }
          ]
        }

        Please retry with corrected JSON.
        """
    }

    private func parseCompleteAnalysis(input: [String: Any]) throws -> GitAnalysisResult {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: input)
        } catch {
            throw GitAgentError.invalidToolCall("Could not serialize complete_analysis input: \(error.localizedDescription)")
        }

        do {
            let params = try JSONDecoder().decode(CompleteAnalysisTool.Parameters.self, from: data)
            let repoName = repoPath.lastPathComponent
            let docId = repoName

            var skills: [Skill] = []
            var narrativeCards: [KnowledgeCard] = []

            for card in params.cards {
                if card.cardType == "skill" {
                    // Convert skill cards to Skill objects, carrying the agent's judgments through
                    guard let proficiencyRaw = card.proficiency,
                          let proficiency = Proficiency(rawValue: proficiencyRaw) else {
                        throw GitAgentError.invalidToolCall(
                            "Skill card '\(card.proposedTitle)' is missing a valid 'proficiency' (expected one of: expert, proficient, familiar)"
                        )
                    }
                    guard let category = card.category, !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw GitAgentError.invalidToolCall(
                            "Skill card '\(card.proposedTitle)' is missing a 'category'"
                        )
                    }
                    guard let evidenceStrength = EvidenceStrength(rawValue: card.evidenceStrength) else {
                        throw GitAgentError.invalidToolCall(
                            "Skill card '\(card.proposedTitle)' has an invalid 'evidenceStrength' value '\(card.evidenceStrength)' (expected one of: primary, supporting, mention)"
                        )
                    }

                    let evidence = card.evidenceLocations.map { location in
                        SkillEvidence(
                            documentId: docId,
                            location: location,
                            context: card.extractionNotes ?? "",
                            strength: evidenceStrength
                        )
                    }

                    let skill = Skill(
                        canonical: card.proposedTitle,
                        atsVariants: card.atsVariants ?? [],
                        category: category,
                        proficiency: proficiency,
                        evidence: evidence
                    )
                    skills.append(skill)
                } else {
                    // Convert other card types to KnowledgeCard
                    let cardType: CardType = {
                        switch card.cardType {
                        case "project": return .project
                        case "achievement": return .achievement
                        case "education": return .education
                        case "employment": return .employment
                        default: return .project
                        }
                    }()

                    // Convert evidence locations to EvidenceAnchor
                    let evidenceAnchors = card.evidenceLocations.map { location in
                        EvidenceAnchor(
                            documentId: docId,
                            location: location,
                            verbatimExcerpt: nil
                        )
                    }

                    // Build narrative from key facts and outcomes
                    var narrativeParts: [String] = []
                    if let notes = card.extractionNotes, !notes.isEmpty {
                        narrativeParts.append(notes)
                    }
                    if !card.keyFacts.isEmpty {
                        narrativeParts.append("\n## Key Points\n" + card.keyFacts.joined(separator: "\n• "))
                    }
                    if !card.quantifiedOutcomes.isEmpty {
                        narrativeParts.append("\n## Outcomes\n" + card.quantifiedOutcomes.joined(separator: "\n• "))
                    }

                    let narrativeCard = KnowledgeCard(
                        title: card.proposedTitle,
                        narrative: narrativeParts.joined(separator: "\n"),
                        cardType: cardType,
                        dateRange: card.dateRange,
                        organization: repoName,
                        evidenceAnchors: evidenceAnchors,
                        extractable: ExtractableMetadata(
                            domains: card.technologies.prefix(5).map { String($0) },
                            scale: card.quantifiedOutcomes,
                            keywords: card.keyFacts.prefix(3).map { String($0) }
                        )
                    )
                    narrativeCards.append(narrativeCard)
                }
            }

            return GitAnalysisResult(
                skills: skills,
                narrativeCards: narrativeCards,
                repoName: repoName,
                analyzedAt: Date()
            )
        } catch let error as GitAgentError {
            throw error
        } catch {
            throw GitAgentError.invalidToolCall("Failed to decode complete_analysis: \(error.localizedDescription)")
        }
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
        case CompleteAnalysisTool.name:
            return "submitting analysis"
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
        case CompleteAnalysisTool.name: return "Complete analysis"
        default: return name
        }
    }

    // MARK: - Event Emission

    private func emitEvent(_ event: OnboardingEvent) async {
        guard let eventBus = eventBus else { return }
        await eventBus.publish(event)
    }
}
