//
//  JobScoutLoop.swift
//  Sprung
//
//  Agent loop for the Job Scout: a client-side-tool Anthropic loop on the
//  shared AnthropicToolLoopRunner, mirroring SiteJobSearchLoop's shape but
//  with local tools instead of server-side web tools. The agent searches the
//  run's enabled boards through `search_board`, drills into promising
//  LinkedIn postings through `get_job_details`, and terminates by submitting
//  its picks through the strict `recommend_jobs` tool.
//
//  Tool execution is injected as closures (JobScoutService owns the board
//  services, dedup state, and run notes), so this delegate stays LLM-pure:
//  request construction, decode/validation, no-tool policy, and the
//  max-turns forced completion — the halves the unit tests cover.
//
//  Cancellation is cooperative through the runner's existing seam
//  (Task.checkCancellation before every turn); maxTurns is the only bound —
//  no wall-clock timeout, in-progress scouting is never discarded on a
//  deadline.
//

import Foundation
import SwiftOpenAI

// MARK: - Errors

enum JobScoutError: Error, LocalizedError {
    case promptTemplateMissing(String)
    case toolLoopExceeded
    case notConfigured(String)
    case noBoardsAvailable(String)
    case llmError(String)

    var errorDescription: String? {
        switch self {
        case .promptTemplateMissing(let name):
            return "A required prompt template (\(name)) is missing — the app may need to be reinstalled."
        case .toolLoopExceeded:
            return "The job scout ran out of turns before submitting recommendations."
        case .notConfigured(let detail):
            return "The job scout isn't ready to run: \(detail)"
        case .noBoardsAvailable(let detail):
            return "No boards were available to scout: \(detail)"
        case .llmError(let reason):
            return "LLM error: \(reason)"
        }
    }
}

// MARK: - Wire Types (camelCase keys we control)

/// `search_board`'s decoded input. Strict tool use sends explicit JSON null
/// (never absent) for the nullable leaves, which decodes to nil here.
struct JobScoutSearchBoardArgs: Codable {
    let board: String
    let keywords: String
    let location: String?
    let datePosted: String?
}

/// One recommendation from the `recommend_jobs` completion payload — the
/// pre-import draft. JobScoutService turns each into a
/// `JobScoutService.ScoutRecommendation` with its `imported` outcome.
struct JobScoutRecommendationDraft: Codable, Hashable {
    let url: String
    let title: String
    let company: String
    let reasoning: String
}

/// The `recommend_jobs` payload: the picks, plus an honest reason when the
/// list is empty so an empty run surfaces to the user instead of reading as
/// a quiet success.
struct JobScoutSubmission: Codable {
    let recommendations: [JobScoutRecommendationDraft]
    let emptyReason: String?
}

// MARK: - Loop

@MainActor
final class JobScoutLoop: AnthropicToolLoopDelegate {
    private let llmFacade: LLMFacade
    private let modelId: String
    private let systemPrompt: String
    private let userMessage: String
    /// Boards enabled for THIS run (post-consent-gate) — `search_board` calls
    /// naming any other board get a corrective error result.
    private let enabledBoards: Set<JobScoutService.ScoutBoard>
    /// Executes one validated board search (owned by JobScoutService: board
    /// routing, dedup, run-state bookkeeping).
    private let searchBoard: @MainActor (JobScoutService.ScoutBoard, JobScoutSearchBoardArgs) async -> AnthropicToolOutput
    /// Fetches LinkedIn posting text (owned by JobScoutService: server
    /// lifecycle, shared budget, auth doctrine).
    private let fetchJobDetails: @MainActor (String) async -> AnthropicToolOutput
    /// Terse progress lines for the background-activity pill.
    private let onProgress: (@MainActor (String) async -> Void)?

    /// Set after repeated no-tool turns so the next turn forces `recommend_jobs`.
    private var forceCompletionNextTurn = false

    let maxTurns = 16
    /// Explicit output cap — a truncated recommend_jobs payload fails to
    /// decode and silently loses recommendations, so leave generous headroom.
    private let maxResponseTokens = 8192

    init(
        llmFacade: LLMFacade,
        modelId: String,
        systemPrompt: String,
        userMessage: String,
        enabledBoards: Set<JobScoutService.ScoutBoard>,
        searchBoard: @escaping @MainActor (JobScoutService.ScoutBoard, JobScoutSearchBoardArgs) async -> AnthropicToolOutput,
        fetchJobDetails: @escaping @MainActor (String) async -> AnthropicToolOutput,
        onProgress: (@MainActor (String) async -> Void)? = nil
    ) {
        self.llmFacade = llmFacade
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.userMessage = userMessage
        self.enabledBoards = enabledBoards
        self.searchBoard = searchBoard
        self.fetchJobDetails = fetchJobDetails
        self.onProgress = onProgress
    }

    // MARK: - AnthropicToolLoopDelegate

    var completionToolName: String { JobScoutToolSchemas.recommendJobsToolName }

    func maxTurnsError() -> Error { JobScoutError.toolLoopExceeded }

    func initialMessages() -> [AnthropicMessage] {
        [.user(userMessage)]
    }

    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult {
        let toolChoice: AnthropicToolChoice = forceCompletionNextTurn
            ? .tool(name: completionToolName)
            : .auto
        forceCompletionNextTurn = false

        // Prompt-cache breakpoints: one on the system block (caches tools +
        // system) plus SiteJobSearchLoop's moving tail breakpoint on a
        // per-request copy — turn N+1 reads the conversation prefix turn N
        // wrote instead of re-paying the search-result-heavy history.
        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: SiteJobSearchLoop.applyingMovingCacheBreakpoint(to: messages),
            system: .blocks([AnthropicSystemBlock(text: systemPrompt, cacheControl: .ephemeral)]),
            maxTokens: maxResponseTokens,
            stream: false,
            tools: JobScoutToolSchemas.allTools,
            toolChoice: toolChoice
        )
        let response = try await llmFacade.anthropicMessages(parameters: parameters)
        let usage = response.usage
        Logger.debug(
            "🔭 JobScout usage (\(modelId)): input=\(usage.inputTokens) "
            + "cache_read=\(usage.cacheReadInputTokens ?? 0) cache_create=\(usage.cacheCreationInputTokens ?? 0) "
            + "output=\(usage.outputTokens)",
            category: .ai
        )
        return AnthropicTurnResult(response: response)
    }

    func executeTools(_ toolCalls: [AnthropicToolUseResponseBlock]) async -> [String: AnthropicToolOutput] {
        var outputs: [String: AnthropicToolOutput] = [:]
        for call in toolCalls {
            outputs[call.id] = await executeTool(call)
        }
        return outputs
    }

    private func executeTool(_ call: AnthropicToolUseResponseBlock) async -> AnthropicToolOutput {
        switch call.name {
        case JobScoutToolSchemas.searchBoardToolName:
            let args: JobScoutSearchBoardArgs
            do {
                args = try JSONDecoder().decode(JobScoutSearchBoardArgs.self, from: call.input.jsonData)
            } catch {
                return AnthropicToolOutput(
                    content: "search_board input failed to decode: \(error.localizedDescription)",
                    isError: true
                )
            }
            switch Self.validatedBoard(args.board, enabledBoards: enabledBoards) {
            case .invalid(let message):
                return AnthropicToolOutput(content: message, isError: true)
            case .valid(let board):
                await onProgress?("Searching \(board.displayName): \(args.keywords)")
                return await searchBoard(board, args)
            }

        case JobScoutToolSchemas.getJobDetailsToolName:
            guard let url = call.input["url"]?.value as? String,
                  !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return AnthropicToolOutput(content: "get_job_details needs a url string.", isError: true)
            }
            await onProgress?("Fetching posting details")
            return await fetchJobDetails(url)

        default:
            // recommend_jobs terminates the loop before reaching here; answer
            // anything else defensively so no tool_use is ever orphaned.
            return AnthropicToolOutput(
                content: "Unknown tool '\(call.name)' — only search_board and get_job_details run mid-loop.",
                isError: true
            )
        }
    }

    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> JobScoutSubmission {
        let submission = try Self.decodeSubmission(call)
        let count = submission.recommendations.count
        await onProgress?("Submitted \(count) recommendation\(count == 1 ? "" : "s")")
        Logger.info("Job scout agent submitted \(count) recommendations", category: .ai)
        return submission
    }

    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision {
        if consecutiveNoToolTurns >= 2 {
            forceCompletionNextTurn = true
            return .nudge(
                "Call \(completionToolName) now with the best recommendations you have so far "
                + "(an empty list with emptyReason if nothing qualified)."
            )
        }
        return .nudge(
            "Continue: search another enabled board or drill into a promising result — or, if your "
            + "judgment is complete, call \(completionToolName) with your final recommendations."
        )
    }

    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> JobScoutSubmission? {
        // Don't discard the run's research: force one recommend_jobs call from
        // the conversation so far. Nil (schema-invalid forced payload) falls
        // back to the runner throwing maxTurnsError().
        var conversation = messages
        conversation.append(.user(
            "You are out of research turns. Call \(completionToolName) NOW with the best recommendations "
            + "you have so far — an empty list with emptyReason if none. Do not call any other tool."
        ))
        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: SiteJobSearchLoop.applyingMovingCacheBreakpoint(to: conversation),
            system: .blocks([AnthropicSystemBlock(text: systemPrompt, cacheControl: .ephemeral)]),
            maxTokens: maxResponseTokens,
            stream: false,
            tools: JobScoutToolSchemas.allTools,
            toolChoice: .tool(name: completionToolName)
        )
        let response = try await llmFacade.anthropicMessages(parameters: parameters)
        let completionCall = response.content.compactMap { block -> AnthropicToolUseResponseBlock? in
            if case .toolUse(let call) = block, call.name == completionToolName { return call }
            return nil
        }.first
        guard let completionCall else {
            Logger.error("Job scout: forced completion returned no \(completionToolName) call", category: .ai)
            return nil
        }
        do {
            let submission = try Self.decodeSubmission(completionCall)
            Logger.info("Job scout agent force-submitted \(submission.recommendations.count) recommendations at max turns", category: .ai)
            return submission
        } catch {
            Logger.error("Job scout: forced completion payload invalid: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    // MARK: - Pure Helpers (static — covered by JobScoutLoopTests)

    /// Outcome of validating a `search_board` board argument: the resolved
    /// board, or the corrective message the runner relays as the tool_result.
    enum BoardValidation: Equatable {
        case valid(JobScoutService.ScoutBoard)
        case invalid(String)
    }

    /// Resolve a `search_board` board string against the run's enabled set.
    static func validatedBoard(
        _ raw: String,
        enabledBoards: Set<JobScoutService.ScoutBoard>
    ) -> BoardValidation {
        guard let board = JobScoutService.ScoutBoard(rawValue: raw) else {
            let known = JobScoutService.ScoutBoard.allCases.map(\.rawValue).joined(separator: ", ")
            return .invalid("Unknown board '\(raw)' — valid boards: \(known).")
        }
        guard enabledBoards.contains(board) else {
            let enabled = enabledBoards.map(\.rawValue).sorted().joined(separator: ", ")
            return .invalid(
                "\(board.displayName) is not enabled for this run. Enabled boards: "
                + (enabled.isEmpty ? "none" : enabled) + "."
            )
        }
        return .valid(board)
    }

    /// Decode and validate a `recommend_jobs` payload. Throws (with a
    /// corrective message the runner relays as the tool_result) on decode
    /// failure, essentials-missing recommendations, non-http(s) URLs, or
    /// duplicate URLs within the submission.
    static func decodeSubmission(_ call: AnthropicToolUseResponseBlock) throws -> JobScoutSubmission {
        let submission: JobScoutSubmission
        do {
            submission = try JSONDecoder().decode(JobScoutSubmission.self, from: call.input.jsonData)
        } catch {
            throw JobScoutError.llmError(
                "\(JobScoutToolSchemas.recommendJobsToolName) payload failed to decode: \(error.localizedDescription)"
            )
        }

        let incomplete = submission.recommendations.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard incomplete.isEmpty else {
            let names = incomplete.map { "'\($0.title.isEmpty ? $0.url : $0.title)'" }.joined(separator: ", ")
            throw JobScoutError.llmError(
                "These recommendations are missing a title, company, or reasoning — resubmit with every "
                + "field filled from the search result or fetched posting: \(names)"
            )
        }

        let badURLs = submission.recommendations.filter { recommendation in
            guard let url = URL(string: recommendation.url), let scheme = url.scheme?.lowercased() else { return true }
            return !(scheme == "http" || scheme == "https") || url.host == nil
        }
        guard badURLs.isEmpty else {
            let names = badURLs.map { "'\($0.title)' (url: \($0.url))" }.joined(separator: ", ")
            throw JobScoutError.llmError(
                "These recommendations have invalid posting URLs — resubmit each with the http(s) URL "
                + "exactly as the search result returned it: \(names)"
            )
        }

        var seen = Set<String>()
        let duplicated = submission.recommendations.filter { !seen.insert($0.url).inserted }
        guard duplicated.isEmpty else {
            let names = duplicated.map { "'\($0.title)' (url: \($0.url))" }.joined(separator: ", ")
            throw JobScoutError.llmError(
                "These recommendations repeat a posting URL already in the submission — each posting "
                + "appears exactly once: \(names)"
            )
        }

        return submission
    }
}
