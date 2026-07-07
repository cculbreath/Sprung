//
//  JobImportLoop.swift
//  Sprung
//
//  Job-posting extraction agent on the shared AnthropicToolLoopRunner. Two
//  modes, one terminal tool (`submit_job`):
//
//  - .url  — the agent fetches the posting page itself with Anthropic's
//            server-side web_fetch (web_search as a locator fallback), then
//            submits. This replaces the old OpenAI Responses web-search import.
//  - .text — the posting text is already in hand (LinkedIn MCP innerText), so
//            no web tools are declared and submit_job is forced on turn 1.
//
//  Server-tool mechanics (pause_turn continuation, no-tool policy, moving cache
//  breakpoint, tool-rejection mapping) mirror EventDiscoveryLoop — see its
//  header for the full rationale. Job import fetches a single page, so the
//  budgets and turn count are small.
//

import Foundation
import SwiftOpenAI

enum JobImportError: LocalizedError {
    case toolLoopExceeded
    case extractionInvalid(String)
    case serverToolRejected

    var errorDescription: String? {
        switch self {
        case .toolLoopExceeded:
            return "The job-import agent ran out of turns before extracting the posting."
        case .extractionInvalid(let detail):
            return detail
        case .serverToolRejected:
            return "The configured Job Import model rejected Anthropic's web_search/web_fetch tools. "
                + "Select a current-generation Anthropic model under Settings > Models > Job Import, then retry."
        }
    }
}

@MainActor
final class JobImportLoop: AnthropicToolLoopDelegate {
    enum Mode {
        /// Fetch the posting page with server-side web tools, then extract.
        case url(URL)
        /// Extract from posting text supplied directly (no web step).
        case text(String)
    }

    private let mode: Mode
    private let sourceURL: String
    private let llmFacade: LLMFacade
    private let modelId: String
    /// Terse progress lines for the import UI ("Fetching: …", "Searching: …").
    private let onProgress: (@MainActor (String) async -> Void)?

    /// Set after repeated idle turns so the next turn forces `submit_job`.
    private var forceCompletionNextTurn = false
    /// Consecutive turns with neither client tool calls nor server-tool activity.
    private var idleNoToolTurns = 0

    let maxTurns = 10
    /// Explicit output cap — a truncated submit_job payload fails to decode, so
    /// leave generous headroom for a long full-posting `jobDescription`.
    private let maxResponseTokens = 16000
    /// Bound on pause_turn continuations within a single runner turn.
    private let maxPauseContinuations = 6

    init(
        mode: Mode,
        sourceURL: String,
        llmFacade: LLMFacade,
        modelId: String,
        onProgress: (@MainActor (String) async -> Void)? = nil
    ) {
        self.mode = mode
        self.sourceURL = sourceURL
        self.llmFacade = llmFacade
        self.modelId = modelId
        self.onProgress = onProgress
    }

    // MARK: - System prompt / seed message

    private var systemPrompt: String {
        """
        You are a job listing data extractor. Extract structured job information \
        and submit it through the submit_job tool. Extract ALL available \
        information; for jobDescription include the COMPLETE description with all \
        responsibilities, requirements, qualifications, and benefits — do not \
        summarize or truncate. For any field the posting does not state, use the \
        exact string "Not specified".
        """
    }

    private var tools: [AnthropicTool] {
        switch mode {
        case .url: return JobImportToolSchemas.urlModeTools
        case .text: return JobImportToolSchemas.textModeTools
        }
    }

    // MARK: - AnthropicToolLoopDelegate

    var completionToolName: String { JobImportToolSchemas.submitJobToolName }

    func maxTurnsError() -> Error { JobImportError.toolLoopExceeded }

    func initialMessages() -> [AnthropicMessage] {
        switch mode {
        case .url(let url):
            return [.user(
                "Fetch the job posting at \(url.absoluteString) using web_fetch (use web_search "
                + "first only if that URL does not resolve to the posting), then call submit_job "
                + "with the extracted fields."
            )]
        case .text(let postingText):
            return [.user(
                "Extract the structured job information from this job posting text and call "
                + "submit_job:\n\n\(postingText)"
            )]
        }
    }

    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult {
        let toolChoice: AnthropicToolChoice
        switch mode {
        case .text:
            // Text is already in hand — extract and submit in one turn.
            toolChoice = .tool(name: completionToolName)
        case .url:
            toolChoice = forceCompletionNextTurn ? .tool(name: completionToolName) : .auto
        }
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
        // web_search/web_fetch run server-side and submit_job terminates the
        // loop, so no client tool should ever reach here. Answer defensively so
        // an unexpected call never orphans a tool_use.
        toolCalls.reduce(into: [:]) { outputs, call in
            outputs[call.id] = AnthropicToolOutput(
                content: "Unknown tool '\(call.name)' — only \(completionToolName) runs client-side.",
                isError: true
            )
        }
    }

    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> JobApp {
        let fields: ImportedJobFields
        do {
            fields = try JSONDecoder().decode(ImportedJobFields.self, from: call.input.jsonData)
        } catch {
            throw JobImportError.extractionInvalid(
                "submit_job payload failed to decode: \(error.localizedDescription). Resubmit with every field present."
            )
        }
        guard let jobApp = JobURLImportService.makeJobApp(from: fields, sourceURL: sourceURL) else {
            throw JobImportError.extractionInvalid(
                "The posting is missing a job title or company — re-read the page and resubmit with both populated."
            )
        }
        await onProgress?("Extracted \(jobApp.jobPosition) at \(jobApp.companyName)")
        return jobApp
    }

    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision {
        idleNoToolTurns += 1
        if idleNoToolTurns >= 2 {
            forceCompletionNextTurn = true
            return .nudge(
                "Call \(completionToolName) now with the job fields you have extracted so far."
            )
        }
        return .nudge(
            "Continue: fetch the posting page with web_fetch if you have not yet, then call "
            + "\(completionToolName) with the extracted fields."
        )
    }

    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> JobApp? {
        // Don't discard the fetch: force one submit_job call from the
        // conversation so far. Nil (schema-invalid forced payload) falls back to
        // the runner throwing maxTurnsError().
        var conversation = messages
        conversation.append(.user(
            "You are out of turns. Call \(completionToolName) NOW with every field you have "
            + "extracted. Do not call any other tool."
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
            Logger.error("Job import: forced completion returned no \(completionToolName) call", category: .ai)
            return nil
        }
        return try? await parseCompletion(completionCall)
    }

    // MARK: - Request Execution (pause_turn handling)

    /// Send the conversation, transparently continuing while the server-side
    /// tool loop pauses (`stop_reason == "pause_turn"`). Mirrors
    /// EventDiscoveryLoop.runPausableRequest.
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
                tools: tools,
                toolChoice: toolChoice
            )

            let response: AnthropicMessageResponse
            do {
                response = try await llmFacade.anthropicMessages(parameters: parameters)
            } catch {
                throw Self.mapServerToolRejection(error)
            }

            let sawServerBlocks = await reportServerToolActivity(response.content)
            hadServerActivity = hadServerActivity || sawServerBlocks

            if response.stopReason == "pause_turn", pauseContinuations < maxPauseContinuations {
                pauseContinuations += 1
                pausedSegments.append(response.content)
                conversation.append(AnthropicTurnResult.assistantEcho(of: response.content))
                continue
            }
            if response.stopReason == "pause_turn" {
                Logger.warning("Job import: pause_turn continuation cap reached; treating turn as final", category: .ai)
            }
            return (response, pausedSegments, hadServerActivity)
        }
    }

    // MARK: - Prompt-Cache Breakpoints

    /// System block with a cache breakpoint (caches tools + system).
    static func systemContent(_ prompt: String) -> AnthropicSystemContent {
        .blocks([AnthropicSystemBlock(text: prompt, cacheControl: .ephemeral)])
    }

    /// Moving conversation breakpoint on the last cache-controllable block —
    /// applied to a per-request copy only, so the runner's stored history stays
    /// clean. Same pattern as EventDiscoveryLoop.
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
                    Logger.warning("Job import web_search error: \(error.errorCode)", category: .ai)
                }
            case .webFetchToolResult(let result):
                sawServerBlock = true
                if case .error(let error) = result.content {
                    await onProgress?("Fetch failed: \(error.errorCode)")
                    Logger.warning("Job import web_fetch error: \(error.errorCode)", category: .ai)
                }
            case .text, .toolUse:
                break
            }
        }
        return sawServerBlock
    }

    /// The web_search/web_fetch tool variants require current-generation models.
    /// When the API 400s on the tool declaration, name the fix (the Job Import
    /// model setting) instead of surfacing a raw wire error.
    static func mapServerToolRejection(_ error: Error) -> Error {
        guard let apiError = error as? APIError,
              case .responseUnsuccessful(_, let statusCode, let responseBody) = apiError,
              statusCode == 400,
              let body = responseBody?.lowercased(),
              body.contains("web_search") || body.contains("web_fetch") else {
            return error
        }
        return JobImportError.serverToolRejected
    }
}
