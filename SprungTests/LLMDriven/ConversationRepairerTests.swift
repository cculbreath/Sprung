//
//  ConversationRepairerTests.swift
//  SprungTests
//
//  Phase 5 (LLM-driven subsystem tests — pure units).
//
//  AnthropicConversationRepairer is the revision agent's safety net that keeps
//  the Anthropic conversation valid: every assistant `tool_use` block must be
//  answered by a `tool_result` in the immediately following user message. It is
//  a pure, static, in-place mutation over [AnthropicMessage] — perfect for unit
//  testing malformed -> repaired sequences with no LLMFacade, no network.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

final class ConversationRepairerTests: XCTestCase {

    // MARK: - Builders (exact fork-type constructors)

    private func toolUse(_ id: String, name: String = "glob") -> AnthropicContentBlock {
        .toolUse(AnthropicToolUseBlock(id: id, name: name, input: [:]))
    }

    private func toolResult(_ id: String, content: String = "ok") -> AnthropicContentBlock {
        .toolResult(AnthropicToolResultBlock(toolUseId: id, content: content))
    }

    private func text(_ s: String) -> AnthropicContentBlock {
        .text(AnthropicTextBlock(text: s))
    }

    private func assistant(_ blocks: [AnthropicContentBlock]) -> AnthropicMessage {
        AnthropicMessage(role: "assistant", content: .blocks(blocks))
    }

    private func user(_ blocks: [AnthropicContentBlock]) -> AnthropicMessage {
        AnthropicMessage(role: "user", content: .blocks(blocks))
    }

    // Collect the tool_result ids found in a (user) message, in order.
    private func toolResultIds(_ message: AnthropicMessage) -> [String] {
        guard case .blocks(let blocks) = message.content else { return [] }
        return blocks.compactMap { block in
            if case .toolResult(let tr) = block { return tr.toolUseId }
            return nil
        }
    }

    // MARK: - Well-formed sequences are untouched

    func testFullyAnsweredToolUseNeedsNoRepair() {
        var messages: [AnthropicMessage] = [
            .user("Find the swift files"),
            assistant([toolUse("toolu_1")]),
            user([toolResult("toolu_1")]),
        ]
        let before = messages
        let repaired = AnthropicConversationRepairer.repairOrphanedToolUse(in: &messages)
        XCTAssertFalse(repaired, "a fully-answered tool_use must not trigger a repair")
        XCTAssertEqual(messages.count, before.count, "no messages added when nothing is orphaned")
        XCTAssertEqual(toolResultIds(messages[2]), ["toolu_1"], "existing result preserved unchanged")
    }

    func testTextOnlyAssistantMessageIsSkipped() {
        var messages: [AnthropicMessage] = [
            .user("hello"),
            .assistant("Hi there, how can I help?"),
            .user("more"),
        ]
        let repaired = AnthropicConversationRepairer.repairOrphanedToolUse(in: &messages)
        XCTAssertFalse(repaired, "an assistant message with no tool_use blocks is never repaired")
        XCTAssertEqual(messages.count, 3)
    }

    func testMultipleToolUsesAllAnsweredNeedsNoRepair() {
        var messages: [AnthropicMessage] = [
            assistant([toolUse("a"), toolUse("b"), toolUse("c")]),
            user([toolResult("a"), toolResult("b"), toolResult("c")]),
        ]
        let repaired = AnthropicConversationRepairer.repairOrphanedToolUse(in: &messages)
        XCTAssertFalse(repaired)
        XCTAssertEqual(toolResultIds(messages[1]), ["a", "b", "c"])
    }

    // MARK: - Orphaned tool_use, no following user message

    func testOrphanedToolUseWithNoFollowingMessageInsertsSyntheticResult() {
        var messages: [AnthropicMessage] = [
            assistant([toolUse("toolu_1")]),  // last message, never answered
        ]
        let repaired = AnthropicConversationRepairer.repairOrphanedToolUse(in: &messages)
        XCTAssertTrue(repaired, "an unanswered trailing tool_use must be repaired")
        XCTAssertEqual(messages.count, 2, "a synthetic user message is inserted")
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertEqual(toolResultIds(messages[1]), ["toolu_1"],
                       "the synthetic result answers the orphaned tool_use id")

        // The synthetic result is flagged as an error result.
        guard case .blocks(let blocks) = messages[1].content,
              case .toolResult(let tr) = blocks.first else {
            return XCTFail("synthetic message must contain a tool_result block")
        }
        XCTAssertEqual(tr.isError, true, "synthetic results are error results")
        XCTAssertTrue(tr.content.contains("cancelled"), "synthetic content marks the call cancelled")
    }

    // MARK: - Orphaned tool_use, following user message exists

    func testPartiallyAnsweredUserMessageGetsSyntheticPrepended() {
        // toolu_1 answered, toolu_2 orphaned; the following user message exists
        // (with one real result) so the synthetic result is PREPENDED to it.
        var messages: [AnthropicMessage] = [
            assistant([toolUse("toolu_1"), toolUse("toolu_2")]),
            user([toolResult("toolu_1")]),
        ]
        let repaired = AnthropicConversationRepairer.repairOrphanedToolUse(in: &messages)
        XCTAssertTrue(repaired)
        XCTAssertEqual(messages.count, 2, "no new message — the synthetic block is merged in")
        // Synthetic (orphan) result is prepended, ahead of the existing real result.
        XCTAssertEqual(toolResultIds(messages[1]), ["toolu_2", "toolu_1"],
                       "orphan result is inserted at index 0, before existing results")
    }

    func testOrphanWithTextOnlyFollowingUserMessageWrapsTextIntoBlocks() {
        // The following user message is plain text (e.g. interview context). The
        // repairer must convert it to blocks with the synthetic result first and
        // the original text preserved after it.
        var messages: [AnthropicMessage] = [
            assistant([toolUse("toolu_1")]),
            .user("some trailing user text"),
        ]
        let repaired = AnthropicConversationRepairer.repairOrphanedToolUse(in: &messages)
        XCTAssertTrue(repaired)
        XCTAssertEqual(messages.count, 2)
        guard case .blocks(let blocks) = messages[1].content else {
            return XCTFail("text content must be rewritten to blocks")
        }
        XCTAssertEqual(blocks.count, 2, "synthetic result + preserved text")
        guard case .toolResult(let tr) = blocks[0] else {
            return XCTFail("synthetic tool_result must be first")
        }
        XCTAssertEqual(tr.toolUseId, "toolu_1")
        guard case .text(let textBlock) = blocks[1] else {
            return XCTFail("original text must be preserved after the synthetic result")
        }
        XCTAssertEqual(textBlock.text, "some trailing user text")
    }

    // MARK: - Multiple orphans across the conversation

    func testTwoSeparateOrphansBothRepaired() {
        var messages: [AnthropicMessage] = [
            assistant([toolUse("a")]),       // orphan #1 (no following user)
            assistant([toolUse("b")]),       // orphan #2 (no following user)
        ]
        // After repairing the first, the loop skips past the repaired pair; it
        // must still catch the second orphan.
        let repaired = AnthropicConversationRepairer.repairOrphanedToolUse(in: &messages)
        XCTAssertTrue(repaired)
        // Each orphan gets its own inserted synthetic user message.
        let resultIds = messages.compactMap { msg -> [String]? in
            let ids = toolResultIds(msg)
            return ids.isEmpty ? nil : ids
        }.flatMap { $0 }
        XCTAssertEqual(Set(resultIds), ["a", "b"], "both orphaned tool_use ids are answered")
    }

    // MARK: - Empty input

    func testEmptyConversationIsNoOp() {
        var messages: [AnthropicMessage] = []
        XCTAssertFalse(AnthropicConversationRepairer.repairOrphanedToolUse(in: &messages))
        XCTAssertTrue(messages.isEmpty)
    }
}
