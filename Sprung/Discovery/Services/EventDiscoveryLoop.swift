//
//  EventDiscoveryLoop.swift
//  Sprung
//
//  Networking-event discovery agent on the shared AnthropicToolLoopRunner,
//  using Anthropic's server-side web_search + web_fetch tools. Two-phase
//  strategy (fan-out searches, then page-verify every candidate with
//  web_fetch) lives in discovery_discover_events.txt; the loop terminates
//  when the agent submits its verified list through the strict
//  `submit_events` tool.
//
//  Server-tool mechanics this delegate owns (the runner is agnostic to them):
//
//  - Full-fidelity assistant echo. `AnthropicTurnResult` drops server-tool
//    blocks, so the runner's own echo would lose `server_tool_use` /
//    `web_search_tool_result` / `web_fetch_tool_result` blocks — including the
//    `encrypted_content` the model needs to keep citing pages across turns.
//    This delegate stashes a verbatim echo of EVERY response content block per
//    turn and, on each request, rebuilds the conversation by substituting the
//    stashed echoes for the runner's lossy ones (`reconciled(_:turnEchoes:)`).
//
//  - pause_turn. When a response stops with "pause_turn" the server-side tool
//    loop paused mid-turn: re-send the conversation with the assistant turn
//    appended — no extra user message, never a tool_result for a
//    server_tool_use. Handled inside `runModelTurn`, so the runner never
//    counts a paused turn as a no-tool stall.
//
//  - No-tool policy. A turn that only ran server tools surfaces to the runner
//    as "no tool calls" (server blocks aren't client tool_use). Those turns
//    are working turns, not stalls — the delegate tracks genuinely idle turns
//    itself and only forces completion after repeated idleness.
//

import Foundation
import SwiftOpenAI

@MainActor
final class EventDiscoveryLoop: AnthropicToolLoopDelegate {
    private let llmFacade: LLMFacade
    private let modelId: String
    private let systemPrompt: String
    private let userMessage: String
    /// Terse progress lines for the discovery UI ("Searching: …", "Fetching: …").
    private let onProgress: (@MainActor (String) async -> Void)?

    /// Full-fidelity assistant echoes, one entry per completed runner turn
    /// (each entry holds the pause_turn continuation echoes plus the final one).
    private var turnEchoes: [[AnthropicMessage]] = []

    /// Set after repeated idle turns so the next turn forces `submit_events`.
    private var forceCompletionNextTurn = false

    /// Consecutive turns with neither client tool calls nor server-tool
    /// activity. Distinct from the runner's counter, which cannot see
    /// server-tool activity.
    private var idleNoToolTurns = 0

    let maxTurns = 24
    /// Explicit output cap — a truncated submit_events payload fails to decode
    /// and silently loses events, so leave generous headroom.
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

    var completionToolName: String { EventDiscoveryToolSchemas.submitEventsToolName }

    func maxTurnsError() -> Error { DiscoveryAgentError.toolLoopExceeded }

    func initialMessages() -> [AnthropicMessage] {
        [.user(userMessage)]
    }

    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult {
        let toolChoice: AnthropicToolChoice = forceCompletionNextTurn
            ? .tool(name: completionToolName)
            : .auto
        forceCompletionNextTurn = false

        let conversation = Self.reconciled(messages, turnEchoes: turnEchoes)
        let (response, echoes, hadServerActivity) = try await runPausableRequest(
            conversation: conversation,
            toolChoice: toolChoice
        )
        turnEchoes.append(echoes)

        let result = AnthropicTurnResult(response: response)
        if hadServerActivity || !result.toolCalls.isEmpty {
            idleNoToolTurns = 0
        }
        return result
    }

    func executeTools(_ toolCalls: [AnthropicToolUseResponseBlock]) async -> [String: AnthropicToolOutput] {
        // web_search/web_fetch run server-side and submit_events terminates the
        // loop, so no client tool should ever reach here. Answer defensively so
        // an unexpected call never orphans a tool_use.
        toolCalls.reduce(into: [:]) { outputs, call in
            outputs[call.id] = AnthropicToolOutput(
                content: "Unknown tool '\(call.name)' — only \(completionToolName) runs client-side.",
                isError: true
            )
        }
    }

    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> [DiscoveredEvent] {
        let events = try Self.decodeSubmission(call)
        await onProgress?("Submitted \(events.count) verified event\(events.count == 1 ? "" : "s")")
        Logger.info("Event discovery agent submitted \(events.count) verified events", category: .ai)
        return events
    }

    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision {
        // Server-tool-only turns land here too (their blocks aren't client tool
        // calls); runModelTurn already reset the idle counter for those.
        idleNoToolTurns += 1
        if idleNoToolTurns >= 2 {
            forceCompletionNextTurn = true
            return .nudge(
                "Call \(completionToolName) now with every event you have page-verified so far "
                + "(an empty list if none survived verification)."
            )
        }
        return .nudge(
            "Continue: run your next web_search or web_fetch, or — if Phase B verification "
            + "is complete — call \(completionToolName) with the final list."
        )
    }

    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> [DiscoveredEvent]? {
        // Don't discard the run's research: force one submit_events call from
        // the conversation so far. Nil (schema-invalid forced payload) falls
        // back to the runner throwing maxTurnsError().
        var conversation = Self.reconciled(messages, turnEchoes: turnEchoes)
        conversation.append(.user(
            "You are out of research turns. Call \(completionToolName) NOW with every event you "
            + "have page-verified so far — an empty list if none. Do not call any other tool."
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
            Logger.error("Event discovery: forced completion returned no \(completionToolName) call", category: .ai)
            return nil
        }
        do {
            let events = try Self.decodeSubmission(completionCall)
            Logger.info("Event discovery agent force-submitted \(events.count) events at max turns", category: .ai)
            return events
        } catch {
            Logger.error("Event discovery: forced completion payload invalid: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    // MARK: - Request Execution (pause_turn handling)

    /// Send the conversation, transparently continuing while the server-side
    /// tool loop pauses (`stop_reason == "pause_turn"`): each paused assistant
    /// turn is appended verbatim and the request re-sent, with no user message
    /// in between. Returns the final response, the full-fidelity echoes of
    /// every segment (paused + final), and whether any segment ran server tools.
    private func runPausableRequest(
        conversation: [AnthropicMessage],
        toolChoice: AnthropicToolChoice
    ) async throws -> (response: AnthropicMessageResponse, echoes: [AnthropicMessage], hadServerActivity: Bool) {
        var conversation = conversation
        var echoes: [AnthropicMessage] = []
        var hadServerActivity = false
        var pauseContinuations = 0

        while true {
            let parameters = AnthropicMessageParameter(
                model: modelId,
                messages: conversation,
                system: .blocks([AnthropicSystemBlock(text: systemPrompt)]),
                maxTokens: maxResponseTokens,
                stream: false,
                tools: EventDiscoveryToolSchemas.allTools,
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
                "🌐 EventDiscovery usage (\(modelId)): input=\(usage.inputTokens) output=\(usage.outputTokens) "
                + "searches=\(serverUsage?.webSearchRequests ?? 0) fetches=\(serverUsage?.webFetchRequests ?? 0)",
                category: .ai
            )

            let sawServerBlocks = await reportServerToolActivity(response.content)
            hadServerActivity = hadServerActivity || sawServerBlocks

            let echo = Self.assistantEcho(from: response)
            echoes.append(echo)

            if response.stopReason == "pause_turn", pauseContinuations < maxPauseContinuations {
                pauseContinuations += 1
                conversation.append(echo)
                continue
            }
            if response.stopReason == "pause_turn" {
                // Continuation cap hit: treat the segment as final rather than
                // discarding the research; the runner's no-tool path re-engages.
                Logger.warning("Event discovery: pause_turn continuation cap reached; treating turn as final", category: .ai)
            }
            return (response, echoes, hadServerActivity)
        }
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
                    Logger.warning("Event discovery web_search error: \(error.errorCode)", category: .ai)
                }
            case .webFetchToolResult(let result):
                sawServerBlock = true
                if case .error(let error) = result.content {
                    await onProgress?("Fetch failed: \(error.errorCode)")
                    Logger.warning("Event discovery web_fetch error: \(error.errorCode)", category: .ai)
                }
            case .text, .toolUse:
                break
            }
        }
        return sawServerBlock
    }

    // MARK: - Pure Helpers (static — covered by EventDiscoveryLoopTests)

    /// Build the assistant echo preserving EVERY response content block
    /// verbatim — server-tool blocks (`server_tool_use`,
    /// `web_search_tool_result`, `web_fetch_tool_result`) are the same Codable
    /// values decoded from the wire, so re-encoding is byte-faithful (including
    /// `encrypted_content` and fetched documents). Whitespace-only text blocks
    /// are dropped (the API rejects empty text).
    static func assistantEcho(from response: AnthropicMessageResponse) -> AnthropicMessage {
        var blocks: [AnthropicContentBlock] = []
        for block in response.content {
            switch block {
            case .text(let textBlock):
                if !textBlock.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(textBlock))
                }
            case .toolUse(let call):
                blocks.append(.toolUse(AnthropicToolUseBlock(
                    id: call.id,
                    name: call.name,
                    input: call.input.mapValues { $0.value }
                )))
            case .serverToolUse(let serverToolUse):
                blocks.append(.serverToolUse(serverToolUse))
            case .webSearchToolResult(let result):
                blocks.append(.webSearchToolResult(result))
            case .webFetchToolResult(let result):
                blocks.append(.webFetchToolResult(result))
            }
        }
        if blocks.isEmpty {
            // The API rejects empty assistant messages.
            blocks.append(.text(AnthropicTextBlock(text: "(continuing)")))
        }
        return AnthropicMessage(role: "assistant", content: .blocks(blocks))
    }

    /// Rebuild the true conversation from the runner's stored history: the
    /// runner's assistant echoes drop server-tool blocks, so each one is
    /// replaced (in order) by the stashed full-fidelity echo sequence for that
    /// turn. User messages (initial, tool results, nudges) pass through.
    static func reconciled(
        _ messages: [AnthropicMessage],
        turnEchoes: [[AnthropicMessage]]
    ) -> [AnthropicMessage] {
        var result: [AnthropicMessage] = []
        var turnIndex = 0
        for message in messages {
            if message.role == "assistant", turnIndex < turnEchoes.count {
                result.append(contentsOf: turnEchoes[turnIndex])
                turnIndex += 1
            } else {
                result.append(message)
            }
        }
        return result
    }

    /// Decode and validate a `submit_events` payload. Throws (with a
    /// corrective message the runner relays as the tool_result) on decode
    /// failure or unparseable dates.
    static func decodeSubmission(_ call: AnthropicToolUseResponseBlock) throws -> [DiscoveredEvent] {
        let submission: EventDiscoverySubmission
        do {
            submission = try JSONDecoder().decode(EventDiscoverySubmission.self, from: call.input.jsonData)
        } catch {
            throw DiscoveryAgentError.llmError(
                "submit_events payload failed to decode: \(error.localizedDescription)"
            )
        }
        let unparseable = submission.events.filter { $0.parsedDate == nil }
        guard unparseable.isEmpty else {
            let names = unparseable.map { "'\($0.name)' (date: \($0.date))" }.joined(separator: ", ")
            throw DiscoveryAgentError.llmError(
                "These events have unparseable dates — resubmit with dates formatted YYYY-MM-DD: \(names)"
            )
        }
        return submission.events
    }

    /// The 20260209 web_search/web_fetch tool variants require
    /// current-generation models. When the API 400s on the tool declaration,
    /// name the fix (the Discovery model setting) instead of surfacing a raw
    /// wire error — and never silently fall back to older tool variants.
    static func mapServerToolRejection(_ error: Error) -> Error {
        guard let apiError = error as? APIError,
              case .responseUnsuccessful(_, let statusCode, let responseBody) = apiError,
              statusCode == 400,
              let body = responseBody?.lowercased(),
              body.contains("web_search") || body.contains("web_fetch") else {
            return error
        }
        return DiscoveryAgentError.llmError(
            "The configured Discovery model rejected Anthropic's web_search/web_fetch tools. "
            + "Select a current-generation Anthropic model under Settings > Models > Discovery Agent, then retry."
        )
    }
}
