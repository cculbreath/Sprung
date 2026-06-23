//
//  AnthropicToolLoopRunnerTests.swift
//  SprungTests
//
//  Tech-debt Phase 1A. AnthropicToolLoopRunner is the shared multi-turn Anthropic
//  tool loop. Its load-bearing invariant — EVERY tool_use gets exactly one
//  tool_result, in tool_use order, in the next user message — is what lets us
//  delete AnthropicConversationRepairer (1F). These paths are NOT in the replay
//  byte-gate, so this suite is the primary automated proof of the invariant.
//
//  The runner is driven through AnthropicToolLoopDelegate, so it is exercised
//  with a FAKE delegate that returns scripted turns — no LLMFacade, no network.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

// MARK: - Fixtures

private enum LoopTestError: Error, Equatable {
    case maxTurns
    case aborted
    case badCompletion
}

/// Decode helpers — AnthropicUsage / AnthropicToolUseResponseBlock live in the
/// SwiftOpenAI module and expose no public memberwise init, so build them from
/// JSON (their public Decodable conformance).
private func makeUsage() -> AnthropicUsage {
    // swiftlint:disable:next force_try
    try! JSONDecoder().decode(AnthropicUsage.self, from: Data(#"{"input_tokens":1,"output_tokens":1}"#.utf8))
}

private func makeToolCall(id: String, name: String) -> AnthropicToolUseResponseBlock {
    let dict: [String: Any] = ["type": "tool_use", "id": id, "name": name, "input": [:]]
    let data = try! JSONSerialization.data(withJSONObject: dict)  // swiftlint:disable:this force_try
    return try! JSONDecoder().decode(AnthropicToolUseResponseBlock.self, from: data)  // swiftlint:disable:this force_try
}

private func turn(text: [String] = [], tools: [AnthropicToolUseResponseBlock] = []) -> AnthropicTurnResult {
    AnthropicTurnResult(textBlocks: text, toolCalls: tools, usage: makeUsage())
}

/// Pull tool_result ids (in order) out of a user message's blocks.
private func toolResultIds(of message: AnthropicMessage) -> [String] {
    guard case .blocks(let blocks) = message.content else { return [] }
    return blocks.compactMap { if case .toolResult(let r) = $0 { return r.toolUseId } else { return nil } }
}

@MainActor
private final class FakeLoopDelegate: AnthropicToolLoopDelegate {
    typealias Output = String

    var maxTurns = 10
    let completionToolName = "complete"

    private let turns: [AnthropicTurnResult]
    private var cursor = 0
    /// When scripted turns run out, repeat the last one (to drive max-turns tests).
    var repeatLastTurn = false

    // Behavior knobs
    var noToolDecision: (Int) -> AnthropicNoToolDecision = { _ in .nudge("nudge") }
    var completionParseError: Error?
    var maxTurnsOutput: String?
    var toolOutputs: [String: AnthropicToolOutput] = [:]
    var pendingOnCompletion = false

    // Recordings
    private(set) var receivedMessagesPerTurn: [[AnthropicMessage]] = []
    private(set) var executeToolsCalls: [[String]] = []
    private(set) var prunedTurns: [Int] = []
    private(set) var appendedResults: [(messageIndex: Int, ids: [String])] = []
    private(set) var parseCompletionCalls = 0
    /// Ordered log of "exec" / "parse" to assert relative ordering.
    private(set) var eventLog: [String] = []

    init(turns: [AnthropicTurnResult]) { self.turns = turns }

    var executesPendingToolsOnCompletion: Bool { pendingOnCompletion }

    func maxTurnsError() -> Error { LoopTestError.maxTurns }

    func initialMessages() -> [AnthropicMessage] { [.user("start")] }

    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult {
        receivedMessagesPerTurn.append(messages)
        if cursor < turns.count {
            let t = turns[cursor]; cursor += 1; return t
        }
        if repeatLastTurn, let last = turns.last { return last }
        return turn(text: ["(exhausted)"])  // no tools → exercises the no-tool path
    }

    func executeTools(_ toolCalls: [AnthropicToolUseResponseBlock]) async -> [String: AnthropicToolOutput] {
        executeToolsCalls.append(toolCalls.map(\.id))
        eventLog.append("exec")
        var out: [String: AnthropicToolOutput] = [:]
        for call in toolCalls {
            out[call.id] = toolOutputs[call.id] ?? AnthropicToolOutput(content: "result:\(call.id)")
        }
        return out
    }

    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> String {
        parseCompletionCalls += 1
        eventLog.append("parse")
        if let error = completionParseError { throw error }
        return "completed:\(call.id)"
    }

    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision {
        noToolDecision(consecutiveNoToolTurns)
    }

    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> String? {
        maxTurnsOutput
    }

    func pruneBeforeResults(_ messages: inout [AnthropicMessage], turnCount: Int) {
        prunedTurns.append(turnCount)
    }

    func didAppendToolResults(messageIndex: Int, orderedToolCallIds: [String], turnCount: Int) {
        appendedResults.append((messageIndex, orderedToolCallIds))
    }
}

// MARK: - Tests

@MainActor
final class AnthropicToolLoopRunnerTests: XCTestCase {

    private typealias Runner = AnthropicToolLoopRunner<FakeLoopDelegate>

    // MARK: assembleResults — the pairing invariant

    func testAssembleAnswersEveryToolUseInOrder() {
        let calls = [makeToolCall(id: "a", name: "read"),
                     makeToolCall(id: "b", name: "glob"),
                     makeToolCall(id: "c", name: "grep")]
        let executed: [String: AnthropicToolOutput] = [
            "a": .init(content: "A"), "b": .init(content: "B"), "c": .init(content: "C")
        ]
        let blocks = Runner.assembleResults(
            toolCalls: calls, executed: executed, completionToolName: "complete", completionFailure: nil)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(toolResultIds(of: AnthropicMessage(role: "user", content: .blocks(blocks))), ["a", "b", "c"],
                       "result blocks are in tool_use order")
    }

    func testAssembleFillsMissingResultDefensively() {
        // A tool_use with no execution result must still be answered, or the next
        // request 400s. The runner fills a defensive error result.
        let calls = [makeToolCall(id: "a", name: "read"), makeToolCall(id: "missing", name: "glob")]
        let blocks = Runner.assembleResults(
            toolCalls: calls, executed: ["a": .init(content: "A")], completionToolName: "complete", completionFailure: nil)
        XCTAssertEqual(toolResultIds(of: AnthropicMessage(role: "user", content: .blocks(blocks))), ["a", "missing"])
        guard case .toolResult(let missing) = blocks[1] else { return XCTFail("expected tool_result") }
        XCTAssertEqual(missing.isError, true, "the unanswered tool_use is filled with an error result, never orphaned")
    }

    func testAssembleCompletionFailureAnswersCompletionAndDuplicates() {
        // Completion parse error: the completion id carries the error content, a
        // second completion-named call gets a "duplicate" note, others get results.
        let calls = [makeToolCall(id: "x", name: "read"),
                     makeToolCall(id: "c1", name: "complete"),
                     makeToolCall(id: "c2", name: "complete")]
        let blocks = Runner.assembleResults(
            toolCalls: calls,
            executed: ["x": .init(content: "X")],
            completionToolName: "complete",
            completionFailure: (id: "c1", content: "FIX YOUR JSON"))
        XCTAssertEqual(toolResultIds(of: AnthropicMessage(role: "user", content: .blocks(blocks))), ["x", "c1", "c2"])
        guard case .toolResult(let c1) = blocks[1], case .toolResult(let c2) = blocks[2] else {
            return XCTFail("expected tool_result blocks")
        }
        XCTAssertEqual(c1.content, "FIX YOUR JSON")
        XCTAssertEqual(c1.isError, true)
        XCTAssertTrue(c2.content.contains("Duplicate"), "duplicate completion call is answered, not orphaned")
    }

    // MARK: assistantEcho

    func testAssistantEchoKeepsTextAndToolBlocks() {
        let result = turn(text: ["  ", "hello"], tools: [makeToolCall(id: "a", name: "read")])
        guard case .blocks(let blocks) = Runner.assistantEcho(from: result).content else { return XCTFail() }
        // The whitespace-only block is dropped; "hello" + the tool_use survive.
        XCTAssertEqual(blocks.count, 2)
        guard case .text(let t) = blocks[0], case .toolUse(let u) = blocks[1] else { return XCTFail() }
        XCTAssertEqual(t.text, "hello")
        XCTAssertEqual(u.id, "a")
    }

    func testAssistantEchoPlaceholderWhenEmpty() {
        guard case .blocks(let blocks) = Runner.assistantEcho(from: turn()).content else { return XCTFail() }
        XCTAssertEqual(blocks.count, 1)
        guard case .text(let t) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(t.text, "(continuing)", "an all-empty turn gets a placeholder so the API does not 400")
    }

    // MARK: run() — completion

    func testCompletionReturnsOutput() async throws {
        let delegate = FakeLoopDelegate(turns: [turn(tools: [makeToolCall(id: "c", name: "complete")])])
        let output = try await Runner(delegate: delegate).run()
        XCTAssertEqual(output, "completed:c")
        XCTAssertEqual(delegate.executeToolsCalls.count, 0, "completion-only turn executes no other tools by default")
    }

    func testToolTurnThenCompletionAnswersEveryToolUse() async throws {
        let delegate = FakeLoopDelegate(turns: [
            turn(tools: [makeToolCall(id: "a", name: "read"), makeToolCall(id: "b", name: "glob")]),
            turn(tools: [makeToolCall(id: "c", name: "complete")])
        ])
        let output = try await Runner(delegate: delegate).run()
        XCTAssertEqual(output, "completed:c")

        // The completion turn saw a history whose last user message answered both
        // tool_uses from turn 1, in order.
        let secondTurnMessages = delegate.receivedMessagesPerTurn[1]
        XCTAssertEqual(toolResultIds(of: secondTurnMessages.last!), ["a", "b"])
        // And the hook reported the same ordering at the right message index.
        XCTAssertEqual(delegate.appendedResults.first?.ids, ["a", "b"])
        XCTAssertEqual(delegate.appendedResults.first?.messageIndex, 2,
                       "[user start, assistant echo, user tool_results] -> index 2")
        XCTAssertEqual(delegate.prunedTurns, [1], "pruneBeforeResults fires on the tool turn")
    }

    func testCompletionExecutesPendingToolsWhenConfigured() async throws {
        let delegate = FakeLoopDelegate(turns: [
            turn(tools: [makeToolCall(id: "w", name: "write"), makeToolCall(id: "c", name: "complete")])
        ])
        delegate.pendingOnCompletion = true
        let output = try await Runner(delegate: delegate).run()
        XCTAssertEqual(output, "completed:c")
        XCTAssertEqual(delegate.executeToolsCalls, [["w"]],
                       "co-called non-completion tools run for side effects when executesPendingToolsOnCompletion is true")
        XCTAssertEqual(delegate.eventLog, ["exec", "parse"],
                       "pending tools run BEFORE parseCompletion so side effects precede the final read")
    }

    func testCompletionParseErrorAnswersAndContinues() async throws {
        // Turn 1: a completion that fails to parse, alongside a real tool. Turn 2:
        // a completion that succeeds. The parse-error turn must answer EVERY
        // tool_use (real tool + the failed completion) so the loop can continue.
        let delegate = OneShotFailDelegate(turns: [
            turn(tools: [makeToolCall(id: "r", name: "read"), makeToolCall(id: "c1", name: "complete")]),
            turn(tools: [makeToolCall(id: "c2", name: "complete")])
        ])
        let output = try await AnthropicToolLoopRunner<OneShotFailDelegate>(delegate: delegate).run()
        XCTAssertEqual(output, "completed:c2")
        // Turn 2 saw the turn-1 results: the read answered + the completion
        // answered with its corrective error, in tool_use order.
        let secondTurnMessages = delegate.receivedMessagesPerTurn[1]
        XCTAssertEqual(toolResultIds(of: secondTurnMessages.last!), ["r", "c1"],
                       "the parse-error turn still answered every tool_use")
    }

    // MARK: run() — no-tool policy

    func testNoToolNudgeContinuesThenCompletes() async throws {
        let delegate = FakeLoopDelegate(turns: [
            turn(text: ["thinking, no tools"]),
            turn(tools: [makeToolCall(id: "c", name: "complete")])
        ])
        let output = try await Runner(delegate: delegate).run()
        XCTAssertEqual(output, "completed:c")
        // The nudge produced a trailing user message (.user(_) → .text content)
        // that turn 2 then saw.
        let secondTurnMessages = delegate.receivedMessagesPerTurn[1]
        guard case .text(let nudge)? = secondTurnMessages.last?.content else {
            return XCTFail("expected a trailing nudge user message")
        }
        XCTAssertEqual(nudge, "nudge")
    }

    func testNoToolAbortThrows() async {
        let delegate = FakeLoopDelegate(turns: [turn(text: ["no tools"])])
        delegate.noToolDecision = { _ in .abort(LoopTestError.aborted) }
        do {
            _ = try await Runner(delegate: delegate).run()
            XCTFail("expected abort to throw")
        } catch let error as LoopTestError {
            XCTAssertEqual(error, .aborted)
        } catch { XCTFail("unexpected error: \(error)") }
    }

    func testNoToolConsecutiveCountIncrements() async {
        // The runner tracks the consecutive-no-tool count and passes it in; the
        // delegate aborts on the 3rd consecutive no-tool turn.
        let delegate = FakeLoopDelegate(turns: [turn(text: ["x"]), turn(text: ["y"]), turn(text: ["z"])])
        var counts: [Int] = []
        delegate.noToolDecision = { count in
            counts.append(count)
            return count >= 3 ? .abort(LoopTestError.aborted) : .nudge("again")
        }
        _ = try? await Runner(delegate: delegate).run()
        XCTAssertEqual(counts, [1, 2, 3], "consecutive-no-tool count increments across turns")
    }

    // MARK: run() — max turns

    func testMaxTurnsReachedReturnsForcedOutput() async throws {
        let delegate = FakeLoopDelegate(turns: [turn(tools: [makeToolCall(id: "t", name: "read")])])
        delegate.repeatLastTurn = true   // always a tool turn → never completes
        delegate.maxTurns = 2
        delegate.maxTurnsOutput = "forced"
        let output = try await Runner(delegate: delegate).run()
        XCTAssertEqual(output, "forced")
        XCTAssertEqual(delegate.executeToolsCalls.count, 2, "ran exactly maxTurns tool turns before forcing")
    }

    func testMaxTurnsReachedThrowsWhenNoForcedOutput() async {
        let delegate = FakeLoopDelegate(turns: [turn(tools: [makeToolCall(id: "t", name: "read")])])
        delegate.repeatLastTurn = true
        delegate.maxTurns = 2
        delegate.maxTurnsOutput = nil
        do {
            _ = try await Runner(delegate: delegate).run()
            XCTFail("expected maxTurnsError")
        } catch let error as LoopTestError {
            XCTAssertEqual(error, .maxTurns)
        } catch { XCTFail("unexpected error: \(error)") }
    }
}

// MARK: - One-shot parse-fail delegate

/// Fails `parseCompletion` exactly once, then succeeds — to exercise the
/// completion-parse-error → answer-and-continue → complete path.
@MainActor
private final class OneShotFailDelegate: AnthropicToolLoopDelegate {
    typealias Output = String

    let maxTurns = 10
    let completionToolName = "complete"

    private let turns: [AnthropicTurnResult]
    private var cursor = 0
    private var failedOnce = false

    private(set) var receivedMessagesPerTurn: [[AnthropicMessage]] = []

    init(turns: [AnthropicTurnResult]) { self.turns = turns }

    func maxTurnsError() -> Error { LoopTestError.maxTurns }
    func initialMessages() -> [AnthropicMessage] { [.user("start")] }

    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult {
        receivedMessagesPerTurn.append(messages)
        let t = turns[cursor]; cursor += 1; return t
    }

    func executeTools(_ toolCalls: [AnthropicToolUseResponseBlock]) async -> [String: AnthropicToolOutput] {
        var out: [String: AnthropicToolOutput] = [:]
        for call in toolCalls { out[call.id] = AnthropicToolOutput(content: "result:\(call.id)") }
        return out
    }

    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> String {
        if !failedOnce {
            failedOnce = true
            throw LoopTestError.badCompletion
        }
        return "completed:\(call.id)"
    }

    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision {
        .nudge("nudge")
    }

    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> String? { nil }
}
