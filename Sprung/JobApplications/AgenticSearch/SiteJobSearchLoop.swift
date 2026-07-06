//
//  SiteJobSearchLoop.swift
//  Sprung
//
//  Agentic job search against one specific "web-fetch friendly" small job
//  board or company careers page — boards with no MCP server and no scraper.
//  Runs on the shared AnthropicToolLoopRunner with Anthropic's server-side
//  web_search + web_fetch tools, mirroring EventDiscoveryLoop's proven shape.
//  Two-phase strategy (map the site's listing/index pages, then page-verify
//  every candidate posting with web_fetch) lives in site_job_search.txt; the
//  loop terminates when the agent submits its verified list through the
//  strict `submit_job_listings` tool.
//
//  The runner's echo is full-fidelity (every response content block verbatim,
//  via `AnthropicTurnResult.assistantEchoes`), so its stored history IS the
//  wire conversation — server_tool_use / web_search_tool_result /
//  web_fetch_tool_result blocks, including the `encrypted_content` the model
//  needs to keep citing pages across turns, survive without any delegate-side
//  bookkeeping. Server-tool mechanics this delegate still owns (identical to
//  EventDiscoveryLoop):
//
//  - pause_turn. When a response stops with "pause_turn" the server-side tool
//    loop paused mid-turn: re-send the conversation with the assistant turn
//    appended — no extra user message, never a tool_result for a
//    server_tool_use. Handled inside `runModelTurn` (so the runner never
//    counts a paused turn as a no-tool stall); the paused segments ride back
//    to the runner in the turn result so its history echoes each one.
//
//  - No-tool policy. A turn that only ran server tools surfaces to the runner
//    as "no tool calls" (server blocks aren't client tool_use). Those turns
//    are working turns, not stalls — the delegate tracks genuinely idle turns
//    itself and only forces completion after repeated idleness.
//
//  - Prompt-cache breakpoints. One on the system block (caches tools +
//    system) plus a moving tail breakpoint on the last cache-controllable
//    message block, applied per request — turn N+1 reads the conversation
//    prefix turn N wrote instead of re-paying the fetched-page-heavy history
//    every turn. 2 of Anthropic's 4 breakpoints.
//
//  Cancellation is cooperative through the runner's existing seam: the runner
//  calls `Task.checkCancellation()` before every turn, so cancelling the
//  owning task (the Cancel button in JobSearchView) stops the loop between
//  turns instead of discarding it on a wall-clock deadline (there is none —
//  maxTurns is the only bound).
//

import Foundation
import SwiftOpenAI

// MARK: - Errors

enum SiteJobSearchError: Error, LocalizedError {
    case promptTemplateMissing(String)
    case toolLoopExceeded
    case llmError(String)

    var errorDescription: String? {
        switch self {
        case .promptTemplateMissing(let name):
            return "A required prompt template (\(name)) is missing — the app may need to be reinstalled."
        case .toolLoopExceeded:
            return "The site search agent ran out of turns before submitting results."
        case .llmError(let reason):
            return "LLM error: \(reason)"
        }
    }
}

// MARK: - Wire Types (camelCase keys we control)

/// One page-verified posting submitted through `submit_job_listings`. Strict
/// tool use sends explicit JSON null (never absent) for the nullable leaves,
/// which decodes to nil here.
struct SiteJobListing: Codable, Identifiable, Hashable {
    let title: String
    let company: String
    /// The posting's canonical detail-page URL — the page the agent fetched.
    let url: String
    let location: String?
    let salary: String?
    /// Faithful excerpt/condensation of the posting page — never fabricated.
    let summary: String
    let postedDate: String?

    var id: String { url }
}

/// The `submit_job_listings` payload: the verified list, plus an honest
/// reason when it's empty (site unreachable / bot-walled / nothing matched)
/// so an empty run surfaces to the user instead of reading as a quiet success.
struct SiteJobSearchSubmission: Codable {
    let listings: [SiteJobListing]
    let emptyReason: String?
}

// MARK: - Loop

@MainActor
final class SiteJobSearchLoop: AnthropicToolLoopDelegate {
    private let llmFacade: LLMFacade
    private let modelId: String
    private let systemPrompt: String
    private let userMessage: String
    /// Terse progress lines for the search UI ("Searching: …", "Fetching: …").
    private let onProgress: (@MainActor (String) async -> Void)?

    /// Set after repeated idle turns so the next turn forces `submit_job_listings`.
    private var forceCompletionNextTurn = false

    /// Consecutive turns with neither client tool calls nor server-tool
    /// activity. Distinct from the runner's counter, which cannot see
    /// server-tool activity.
    private var idleNoToolTurns = 0

    let maxTurns = 24
    /// Explicit output cap — a truncated submit_job_listings payload fails to
    /// decode and silently loses postings, so leave generous headroom.
    private let maxResponseTokens = 12000
    /// Bound on pause_turn continuations within a single runner turn.
    private let maxPauseContinuations = 8

    init(
        llmFacade: LLMFacade,
        modelId: String,
        systemPrompt: String,
        userMessage: String,
        onProgress: (@MainActor (String) async -> Void)? = nil
    ) {
        self.llmFacade = llmFacade
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.userMessage = userMessage
        self.onProgress = onProgress
    }

    // MARK: - AnthropicToolLoopDelegate

    var completionToolName: String { SiteJobSearchToolSchemas.submitListingsToolName }

    func maxTurnsError() -> Error { SiteJobSearchError.toolLoopExceeded }

    func initialMessages() -> [AnthropicMessage] {
        [.user(userMessage)]
    }

    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult {
        let toolChoice: AnthropicToolChoice = forceCompletionNextTurn
            ? .tool(name: completionToolName)
            : .auto
        forceCompletionNextTurn = false

        let (response, pausedSegments, hadServerActivity) = try await runPausableRequest(
            conversation: messages,
            toolChoice: toolChoice
        )

        let result = AnthropicTurnResult(response: response, pausedSegments: pausedSegments)
        if hadServerActivity || !result.toolCalls.isEmpty {
            idleNoToolTurns = 0
        }
        return result
    }

    func executeTools(_ toolCalls: [AnthropicToolUseResponseBlock]) async -> [String: AnthropicToolOutput] {
        // web_search/web_fetch run server-side and submit_job_listings
        // terminates the loop, so no client tool should ever reach here.
        // Answer defensively so an unexpected call never orphans a tool_use.
        toolCalls.reduce(into: [:]) { outputs, call in
            outputs[call.id] = AnthropicToolOutput(
                content: "Unknown tool '\(call.name)' — only \(completionToolName) runs client-side.",
                isError: true
            )
        }
    }

    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> SiteJobSearchSubmission {
        let submission = try Self.decodeSubmission(call)
        let count = submission.listings.count
        await onProgress?("Submitted \(count) verified posting\(count == 1 ? "" : "s")")
        Logger.info("Site job search agent submitted \(count) verified postings", category: .ai)
        return submission
    }

    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision {
        // Server-tool-only turns land here too (their blocks aren't client tool
        // calls); runModelTurn already reset the idle counter for those.
        idleNoToolTurns += 1
        if idleNoToolTurns >= 2 {
            forceCompletionNextTurn = true
            return .nudge(
                "Call \(completionToolName) now with every posting you have page-verified so far "
                + "(an empty list with emptyReason if none survived verification)."
            )
        }
        return .nudge(
            "Continue: run your next web_search or web_fetch, or — if Phase B verification "
            + "is complete — call \(completionToolName) with the final list."
        )
    }

    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> SiteJobSearchSubmission? {
        // Don't discard the run's research: force one submit_job_listings call
        // from the conversation so far. Nil (schema-invalid forced payload)
        // falls back to the runner throwing maxTurnsError().
        var conversation = messages
        conversation.append(.user(
            "You are out of research turns. Call \(completionToolName) NOW with every posting you "
            + "have page-verified so far — an empty list with emptyReason if none. Do not call any other tool."
        ))
        let (response, _, _) = try await runPausableRequest(
            conversation: conversation,
            toolChoice: .tool(name: completionToolName)
        )
        let completionCall = response.content.compactMap { block -> AnthropicToolUseResponseBlock? in
            if case .toolUse(let call) = block, call.name == completionToolName { return call }
            return nil
        }.first
        guard let completionCall else {
            Logger.error("Site job search: forced completion returned no \(completionToolName) call", category: .ai)
            return nil
        }
        do {
            let submission = try Self.decodeSubmission(completionCall)
            Logger.info("Site job search agent force-submitted \(submission.listings.count) postings at max turns", category: .ai)
            return submission
        } catch {
            Logger.error("Site job search: forced completion payload invalid: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    // MARK: - Request Execution (pause_turn handling)

    /// Send the conversation, transparently continuing while the server-side
    /// tool loop pauses (`stop_reason == "pause_turn"`): each paused assistant
    /// turn is appended verbatim and the request re-sent, with no user message
    /// in between. Returns the final response, the content of every paused
    /// segment (for the runner's full-fidelity echoes), and whether any
    /// segment ran server tools.
    private func runPausableRequest(
        conversation: [AnthropicMessage],
        toolChoice: AnthropicToolChoice
    ) async throws -> (
        response: AnthropicMessageResponse,
        pausedSegments: [[AnthropicResponseContentBlock]],
        hadServerActivity: Bool
    ) {
        var conversation = conversation
        var pausedSegments: [[AnthropicResponseContentBlock]] = []
        var hadServerActivity = false
        var pauseContinuations = 0

        while true {
            let parameters = AnthropicMessageParameter(
                model: modelId,
                messages: Self.applyingMovingCacheBreakpoint(to: conversation),
                system: Self.systemContent(systemPrompt),
                maxTokens: maxResponseTokens,
                stream: false,
                tools: SiteJobSearchToolSchemas.allTools,
                toolChoice: toolChoice
            )

            let response: AnthropicMessageResponse
            do {
                response = try await llmFacade.anthropicMessages(parameters: parameters)
            } catch {
                throw Self.mapServerToolRejection(error)
            }

            let usage = response.usage
            let serverUsage = usage.serverToolUse
            Logger.debug(
                "🔎 SiteJobSearch usage (\(modelId)): input=\(usage.inputTokens) "
                + "cache_read=\(usage.cacheReadInputTokens ?? 0) cache_create=\(usage.cacheCreationInputTokens ?? 0) "
                + "output=\(usage.outputTokens) "
                + "searches=\(serverUsage?.webSearchRequests ?? 0) fetches=\(serverUsage?.webFetchRequests ?? 0)",
                category: .ai
            )

            let sawServerBlocks = await reportServerToolActivity(response.content)
            hadServerActivity = hadServerActivity || sawServerBlocks

            if response.stopReason == "pause_turn", pauseContinuations < maxPauseContinuations {
                pauseContinuations += 1
                pausedSegments.append(response.content)
                conversation.append(AnthropicTurnResult.assistantEcho(of: response.content))
                continue
            }
            if response.stopReason == "pause_turn" {
                // Continuation cap hit: treat the segment as final rather than
                // discarding the research; the runner's no-tool path re-engages.
                Logger.warning("Site job search: pause_turn continuation cap reached; treating turn as final", category: .ai)
            }
            return (response, pausedSegments, hadServerActivity)
        }
    }

    // MARK: - Prompt-Cache Breakpoints (static — covered by SiteJobSearchLoopTests)

    /// System block with a cache breakpoint (caches tools + system — tools
    /// render before system in the prompt). Turns run back-to-back within a
    /// search, so the 5-minute ephemeral TTL is the right one.
    static func systemContent(_ prompt: String) -> AnthropicSystemContent {
        .blocks([AnthropicSystemBlock(text: prompt, cacheControl: .ephemeral)])
    }

    /// Place the moving conversation breakpoint on the last content block that
    /// can carry cache_control, walking back past the server-tool blocks that
    /// dominate this loop's tails (the fork's types take cache_control on
    /// text / tool_result but not on server_tool_use / web_*_tool_result).
    /// Applied to a per-request copy ONLY — the runner's stored history stays
    /// clean, so the breakpoint moves naturally each turn and turn N+1 reads
    /// the prefix turn N wrote. Total: 1 system + 1 message breakpoint = 2 of
    /// Anthropic's 4. (Single-tail placement, EventDiscoveryLoop's pattern: a
    /// fetch-heavy turn that adds >20 blocks re-writes the prefix once, then
    /// the chain resumes.)
    static func applyingMovingCacheBreakpoint(to messages: [AnthropicMessage]) -> [AnthropicMessage] {
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

    /// Emit terse progress lines for each server-tool invocation and surface
    /// server-tool errors. Returns whether any server-tool block was present.
    private func reportServerToolActivity(_ content: [AnthropicResponseContentBlock]) async -> Bool {
        var sawServerBlock = false
        for block in content {
            switch block {
            case .serverToolUse(let use):
                sawServerBlock = true
                switch use.name {
                case "web_search":
                    if let query = use.input["query"]?.value as? String {
                        await onProgress?("Searching: \(query)")
                    }
                case "web_fetch":
                    if let url = use.input["url"]?.value as? String {
                        await onProgress?("Fetching: \(url)")
                    }
                default:
                    break
                }
            case .webSearchToolResult(let result):
                sawServerBlock = true
                if case .error(let error) = result.content {
                    await onProgress?("Search failed: \(error.errorCode)")
                    Logger.warning("Site job search web_search error: \(error.errorCode)", category: .ai)
                }
            case .webFetchToolResult(let result):
                sawServerBlock = true
                if case .error(let error) = result.content {
                    await onProgress?("Fetch failed: \(error.errorCode)")
                    Logger.warning("Site job search web_fetch error: \(error.errorCode)", category: .ai)
                }
            case .text, .toolUse:
                break
            }
        }
        return sawServerBlock
    }

    // MARK: - Pure Helpers (static — covered by SiteJobSearchLoopTests)

    /// Decode and validate a `submit_job_listings` payload. Throws (with a
    /// corrective message the runner relays as the tool_result) on decode
    /// failure, essentials-missing listings, non-http(s) posting URLs, or
    /// duplicate posting URLs.
    static func decodeSubmission(_ call: AnthropicToolUseResponseBlock) throws -> SiteJobSearchSubmission {
        let submission: SiteJobSearchSubmission
        do {
            submission = try JSONDecoder().decode(SiteJobSearchSubmission.self, from: call.input.jsonData)
        } catch {
            throw SiteJobSearchError.llmError(
                "\(SiteJobSearchToolSchemas.submitListingsToolName) payload failed to decode: \(error.localizedDescription)"
            )
        }

        let incomplete = submission.listings.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard incomplete.isEmpty else {
            let names = incomplete.map { "'\($0.title.isEmpty ? $0.url : $0.title)'" }.joined(separator: ", ")
            throw SiteJobSearchError.llmError(
                "These listings are missing a title, company, or summary — resubmit with every field "
                + "taken from the fetched posting page: \(names)"
            )
        }

        let badURLs = submission.listings.filter { listing in
            guard let url = URL(string: listing.url), let scheme = url.scheme?.lowercased() else { return true }
            return !(scheme == "http" || scheme == "https") || url.host == nil
        }
        guard badURLs.isEmpty else {
            let names = badURLs.map { "'\($0.title)' (url: \($0.url))" }.joined(separator: ", ")
            throw SiteJobSearchError.llmError(
                "These listings have invalid posting URLs — resubmit with each posting's canonical "
                + "http(s) detail-page URL, the page you actually fetched: \(names)"
            )
        }

        var seen = Set<String>()
        let duplicated = submission.listings.filter { !seen.insert($0.url).inserted }
        guard duplicated.isEmpty else {
            let names = duplicated.map { "'\($0.title)' (url: \($0.url))" }.joined(separator: ", ")
            throw SiteJobSearchError.llmError(
                "These listings repeat a posting URL already in the submission — each posting appears "
                + "exactly once: \(names)"
            )
        }

        return submission
    }

    /// The 20260209 web_search/web_fetch tool variants require
    /// current-generation models. When the API 400s on the tool declaration,
    /// name the fix (the Discovery model setting this loop shares) instead of
    /// surfacing a raw wire error — and never silently fall back to older tool
    /// variants.
    static func mapServerToolRejection(_ error: Error) -> Error {
        guard let apiError = error as? APIError,
              case .responseUnsuccessful(_, let statusCode, let responseBody) = apiError,
              statusCode == 400,
              let body = responseBody?.lowercased(),
              body.contains("web_search") || body.contains("web_fetch") else {
            return error
        }
        return SiteJobSearchError.llmError(
            "The configured Discovery model rejected Anthropic's web_search/web_fetch tools. "
            + "Select a current-generation Anthropic model under Settings > Models > Discovery Agent, then retry."
        )
    }
}
