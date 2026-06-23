//
//  AnthropicToolLoopRunner.swift
//  Sprung
//
//  Shared driver for the multi-turn Anthropic Messages tool loop that was
//  previously hand-rolled in every agent (CardMergeAgent, GitAnalysisAgent,
//  ResumeRevisionAgent, …), each re-deriving the load-bearing invariant:
//  EVERY tool_use in an assistant turn MUST get exactly one tool_result, all in
//  the next user message, in tool_use order — or the next request 400s.
//
//  The runner owns the parts that are identical across agents and the parts that
//  are easy to get subtly wrong:
//  - turn counting / maxTurns / timeout
//  - the assistant-echo turn (text blocks + tool_use blocks)
//  - the no-tool nudge / abort branch
//  - the completion-tool check (terminate, or answer-and-continue on parse error)
//  - tool_result assembly with the every-tool_use-answered guarantee
//  - the max-turns terminal (forced completion or throw)
//
//  Agents supply only what genuinely differs, through AnthropicToolLoopDelegate:
//  the request/LLM call (runModelTurn — streaming-swappable), tool execution
//  (sequential or concurrent), completion parsing, the no-tool policy, and a few
//  optional lifecycle hooks. For any agent driven by this runner the pairing
//  invariant holds by construction. (ResumeRevisionAgent deliberately does NOT use
//  the runner — its streaming + human-in-the-loop loop is a genuinely different
//  shape — so it keeps its own hand-rolled loop and still relies on
//  AnthropicConversationRepairer as a defensive safety net for orphaned tool_use
//  ids.)
//

import Foundation
import SwiftOpenAI

// MARK: - Turn Result

/// Normalized result of one assistant turn. Non-streaming callers build this from
/// an `AnthropicMessageResponse` via `init(response:)`; the streaming
/// RevisionAgent will produce the same shape from its stream processor, so the
/// runner is agnostic to how the turn was obtained.
struct AnthropicTurnResult {
    /// Text blocks in response order (raw, untrimmed).
    let textBlocks: [String]
    /// Tool-use blocks in response order.
    let toolCalls: [AnthropicToolUseResponseBlock]
    let usage: AnthropicUsage
    let stopReason: String?

    init(
        textBlocks: [String],
        toolCalls: [AnthropicToolUseResponseBlock],
        usage: AnthropicUsage,
        stopReason: String? = nil
    ) {
        self.textBlocks = textBlocks
        self.toolCalls = toolCalls
        self.usage = usage
        self.stopReason = stopReason
    }

    /// Build from a non-streaming Messages API response, splitting content into
    /// text and tool_use blocks.
    init(response: AnthropicMessageResponse) {
        var texts: [String] = []
        var calls: [AnthropicToolUseResponseBlock] = []
        for block in response.content {
            switch block {
            case .text(let textBlock): texts.append(textBlock.text)
            case .toolUse(let toolUse): calls.append(toolUse)
            }
        }
        self.init(textBlocks: texts, toolCalls: calls, usage: response.usage, stopReason: response.stopReason)
    }
}

// MARK: - Tool Output

/// One tool's result, as returned by the delegate's executor.
struct AnthropicToolOutput {
    let content: String
    var isError: Bool = false
}

// MARK: - No-Tool Decision

/// What to do when an assistant turn returns no tool calls. The delegate owns any
/// counter / abort policy; the runner just acts on the decision.
enum AnthropicNoToolDecision {
    /// Append `text` as a new user message and continue the loop.
    case nudge(String)
    /// Abort the loop by throwing this error.
    case abort(Error)
}

// MARK: - Delegate

/// Agent-specific behavior the runner drives. Conformers are `@MainActor` classes
/// (the agents), so the protocol is main-actor-isolated.
@MainActor
protocol AnthropicToolLoopDelegate: AnyObject {
    /// The value `run()` returns on completion.
    associatedtype Output

    // Configuration
    var maxTurns: Int { get }
    /// Name of the tool whose call terminates the loop.
    var completionToolName: String { get }

    // Terminal errors (so the runner throws agent-typed errors)
    func maxTurnsError() -> Error

    /// Seed conversation (must start with a user message per the Anthropic API).
    func initialMessages() -> [AnthropicMessage]

    /// Run one assistant turn: build the request from `messages`, call the model
    /// (streaming or not), record usage, and return the normalized result.
    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult

    /// Execute the given tool calls and return id → output. May run sequentially
    /// or concurrently. The runner assembles result blocks in tool_use order and
    /// guarantees every id is answered (a missing id is filled defensively), so
    /// the implementation only needs to produce outputs.
    func executeTools(_ toolCalls: [AnthropicToolUseResponseBlock]) async -> [String: AnthropicToolOutput]

    /// Parse the completion tool's input into `Output`, or throw to send a
    /// corrective tool_result and continue. Async so conformers can finalize
    /// (emit events, await background work) before returning.
    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> Output

    /// Policy for an assistant turn with no tool calls. The runner tracks the
    /// consecutive-no-tool count and passes it in; conformers decide nudge vs
    /// abort without holding their own counter.
    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision

    /// Max turns reached: produce `Output` (e.g. a forced completion) using the
    /// conversation so far, or return nil to throw `maxTurnsError()`.
    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> Output?

    // MARK: Optional hooks (defaulted)

    /// When the completion tool parses successfully but other tools were also
    /// called this turn: if true, execute those tools (for their side effects)
    /// before returning. Default false — completion returns immediately.
    var executesPendingToolsOnCompletion: Bool { get }

    /// tool_result content sent back when `parseCompletion` throws.
    func completionRetryContent(for error: Error) -> String

    /// Called at the start of each turn (sync UI state, transcript, events).
    func willStartTurn(_ turnCount: Int) async

    /// Mutate stored history before tool results are appended (e.g. context
    /// pruning). Runs each turn that produces tool results.
    func pruneBeforeResults(_ messages: inout [AnthropicMessage], turnCount: Int)

    /// Called after a tool_result user message is appended at `messageIndex`.
    /// `orderedToolCallIds` is the tool_use order (== block order), so a hook can
    /// recover the (messageIndex, blockIndex) of any result it cares about.
    func didAppendToolResults(messageIndex: Int, orderedToolCallIds: [String], turnCount: Int)
}

// MARK: - Delegate defaults

extension AnthropicToolLoopDelegate {
    var executesPendingToolsOnCompletion: Bool { false }

    func completionRetryContent(for error: Error) -> String {
        "Error: \(error.localizedDescription). Please correct and retry."
    }

    func willStartTurn(_ turnCount: Int) async {}
    func pruneBeforeResults(_ messages: inout [AnthropicMessage], turnCount: Int) {}
    func didAppendToolResults(messageIndex: Int, orderedToolCallIds: [String], turnCount: Int) {}
}

// MARK: - Runner

/// Drives the shared Anthropic tool loop for a delegate. Owns the conversation
/// array and enforces the tool_use→tool_result pairing invariant.
@MainActor
final class AnthropicToolLoopRunner<Delegate: AnthropicToolLoopDelegate> {
    private let delegate: Delegate

    init(delegate: Delegate) {
        self.delegate = delegate
    }

    func run() async throws -> Delegate.Output {
        var messages = delegate.initialMessages()
        var turnCount = 0
        var consecutiveNoTool = 0

        // No wall-clock timeout: `maxTurns` is the bound. A slow-but-progressing
        // agent (e.g. a large repo on a loaded machine) is allowed to finish rather
        // than be killed mid-flight and have its exploration discarded.
        while turnCount < delegate.maxTurns {

            turnCount += 1
            await delegate.willStartTurn(turnCount)

            let result = try await delegate.runModelTurn(messages: messages)

            // Echo the assistant turn so every tool_use has its tool_result in the
            // next user message and role alternation holds.
            messages.append(Self.assistantEcho(from: result))

            // No tool calls → delegate policy (nudge or abort).
            if result.toolCalls.isEmpty {
                consecutiveNoTool += 1
                switch delegate.handleNoTool(turnCount: turnCount, consecutiveNoToolTurns: consecutiveNoTool) {
                case .nudge(let text):
                    messages.append(.user(text))
                    continue
                case .abort(let error):
                    throw error
                }
            }
            consecutiveNoTool = 0

            // Completion tool present?
            if let completion = result.toolCalls.first(where: { $0.name == delegate.completionToolName }) {
                let pending = result.toolCalls.filter { $0.name != delegate.completionToolName }

                // Agents that want co-called tools' side effects regardless of the
                // completion outcome run them BEFORE parsing (so e.g. a final-count
                // read sees post-mutation state). Their results are discarded on
                // success and reused on parse failure.
                var pendingResults: [String: AnthropicToolOutput] = [:]
                if delegate.executesPendingToolsOnCompletion, !pending.isEmpty {
                    delegate.pruneBeforeResults(&messages, turnCount: turnCount)
                    pendingResults = await delegate.executeTools(pending)
                }

                do {
                    return try await delegate.parseCompletion(completion)
                } catch {
                    // Parse failed: answer the completion call (and any duplicate
                    // completion calls) with a corrective error, answer every other
                    // tool_use, and continue. Run the pending tools now if they were
                    // not already run, so no tool_use is orphaned.
                    let errorContent = delegate.completionRetryContent(for: error)
                    if !delegate.executesPendingToolsOnCompletion, !pending.isEmpty {
                        delegate.pruneBeforeResults(&messages, turnCount: turnCount)
                        pendingResults = await delegate.executeTools(pending)
                    }
                    let blocks = Self.assembleResults(
                        toolCalls: result.toolCalls,
                        executed: pendingResults,
                        completionToolName: delegate.completionToolName,
                        completionFailure: (id: completion.id, content: errorContent)
                    )
                    appendResults(blocks, toolCalls: result.toolCalls, turnCount: turnCount, into: &messages)
                    continue
                }
            }

            // Normal tool turn.
            delegate.pruneBeforeResults(&messages, turnCount: turnCount)
            let executed = await delegate.executeTools(result.toolCalls)
            let blocks = Self.assembleResults(
                toolCalls: result.toolCalls,
                executed: executed,
                completionToolName: delegate.completionToolName,
                completionFailure: nil
            )
            guard !blocks.isEmpty else { continue }
            appendResults(blocks, toolCalls: result.toolCalls, turnCount: turnCount, into: &messages)
        }

        // Max turns reached.
        if let output = try await delegate.onMaxTurnsReached(messages: messages) {
            return output
        }
        throw delegate.maxTurnsError()
    }

    // MARK: - Assembly

    private func appendResults(
        _ blocks: [AnthropicContentBlock],
        toolCalls: [AnthropicToolUseResponseBlock],
        turnCount: Int,
        into messages: inout [AnthropicMessage]
    ) {
        let messageIndex = messages.count
        messages.append(AnthropicMessage(role: "user", content: .blocks(blocks)))
        delegate.didAppendToolResults(
            messageIndex: messageIndex,
            orderedToolCallIds: toolCalls.map(\.id),
            turnCount: turnCount
        )
    }

    /// Build the assistant echo: each non-empty (after trim) text block kept as
    /// its own block (original text), then tool_use blocks. A placeholder keeps a
    /// fully-empty turn API-valid.
    static func assistantEcho(from result: AnthropicTurnResult) -> AnthropicMessage {
        var blocks: [AnthropicContentBlock] = []
        for text in result.textBlocks where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(.text(AnthropicTextBlock(text: text)))
        }
        for call in result.toolCalls {
            blocks.append(.toolUse(AnthropicToolUseBlock(
                id: call.id,
                name: call.name,
                input: call.input.mapValues { $0.value }
            )))
        }
        if blocks.isEmpty {
            // The API rejects empty assistant messages.
            blocks.append(.text(AnthropicTextBlock(text: "(continuing)")))
        }
        return AnthropicMessage(role: "assistant", content: .blocks(blocks))
    }

    /// Assemble tool_result blocks in tool_use order, guaranteeing every id is
    /// answered. On a completion-parse-error turn, `completionFailure` supplies the
    /// error content for the failed completion id; any *duplicate* completion-named
    /// calls get a "answered by the first" note so no id is orphaned.
    static func assembleResults(
        toolCalls: [AnthropicToolUseResponseBlock],
        executed: [String: AnthropicToolOutput],
        completionToolName: String,
        completionFailure: (id: String, content: String)?
    ) -> [AnthropicContentBlock] {
        toolCalls.map { call in
            if let failure = completionFailure, call.name == completionToolName {
                let content = call.id == failure.id
                    ? failure.content
                    : "Duplicate \(completionToolName) call — answered by the first call's result."
                return .toolResult(AnthropicToolResultBlock(toolUseId: call.id, content: content, isError: true))
            }
            if let output = executed[call.id] {
                return .toolResult(AnthropicToolResultBlock(
                    toolUseId: call.id, content: output.content, isError: output.isError
                ))
            }
            // Invariant guard: a missing result would orphan this tool_use and 400
            // the next request. Answer defensively rather than drop it.
            return .toolResult(AnthropicToolResultBlock(
                toolUseId: call.id, content: "Tool did not produce a result.", isError: true
            ))
        }
    }
}
