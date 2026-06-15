//
//  AnthropicRequestBuilderTests.swift
//  SprungTests
//
//  Phase 5 (LLM-driven subsystem tests — pure units).
//
//  AnthropicRequestBuilder's request-construction methods (buildUserMessageRequest,
//  buildToolResponseRequest, …) resolve a model id (can throw), drive
//  StateCoordinator / ToolRegistry / history builders, and feed an Anthropic
//  stream — none of which is a pure unit. They are covered end-to-end by the
//  replay infra. What IS pure and load-bearing here is the prompt-cache
//  breakpoint math: two static helpers explicitly written "so the invariant is
//  inspectable in isolation":
//    - clampBreakpointCandidates(...)   — the HARD CLAMP (≤4 cache_control blocks
//      INCLUDING system; drop lookback first, then document; tail always survives)
//    - addingEphemeralCacheControl(...) — per-block-kind cache_control attachment,
//      returning nil for tool_use (which cannot carry cache_control in the fork)
//  Plus the nested BlockPosition value type. These are the only request-side
//  pieces testable without LLMFacade / heavy deps.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

final class AnthropicRequestBuilderTests: XCTestCase {

    private typealias Pos = AnthropicRequestBuilder.BlockPosition

    // MARK: - BlockPosition value semantics

    func testBlockPositionEquatable() {
        XCTAssertEqual(Pos(messageIndex: 1, blockIndex: 2), Pos(messageIndex: 1, blockIndex: 2))
        XCTAssertNotEqual(Pos(messageIndex: 1, blockIndex: 2), Pos(messageIndex: 1, blockIndex: 3))
        XCTAssertNotEqual(Pos(messageIndex: 0, blockIndex: 2), Pos(messageIndex: 1, blockIndex: 2))
    }

    // MARK: - clampBreakpointCandidates: budget = 4 - systemBreakpointCount

    func testKeepsAllThreeWhenSystemHasNoBreakpoint() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        let document = Pos(messageIndex: 2, blockIndex: 1)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        // budget = 4 - 0 = 4 -> all three survive, in priority order.
        let kept = AnthropicRequestBuilder.clampBreakpointCandidates(
            tail: tail, document: document, lookback: lookback, systemBreakpointCount: 0)
        XCTAssertEqual(kept, [tail, document, lookback])
    }

    func testWithSystemBreakpointBudgetIsThree() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        let document = Pos(messageIndex: 2, blockIndex: 1)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        // budget = 4 - 1 = 3 -> all three message breakpoints still fit.
        let kept = AnthropicRequestBuilder.clampBreakpointCandidates(
            tail: tail, document: document, lookback: lookback, systemBreakpointCount: 1)
        XCTAssertEqual(kept, [tail, document, lookback])
    }

    func testDropsLookbackFirstThenDocumentOnOverflow() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        let document = Pos(messageIndex: 2, blockIndex: 1)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)

        // budget = 4 - 2 = 2 -> lookback (lowest priority) is dropped first.
        let twoKept = AnthropicRequestBuilder.clampBreakpointCandidates(
            tail: tail, document: document, lookback: lookback, systemBreakpointCount: 2)
        XCTAssertEqual(twoKept, [tail, document], "lookback dropped first on overflow")

        // budget = 4 - 3 = 1 -> document dropped next; the tail always survives.
        let oneKept = AnthropicRequestBuilder.clampBreakpointCandidates(
            tail: tail, document: document, lookback: lookback, systemBreakpointCount: 3)
        XCTAssertEqual(oneKept, [tail], "document dropped next; tail breakpoint always survives")
    }

    func testZeroBudgetKeepsNothing() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        // budget = max(0, 4 - 4) = 0
        let kept = AnthropicRequestBuilder.clampBreakpointCandidates(
            tail: tail, document: nil, lookback: nil, systemBreakpointCount: 4)
        XCTAssertTrue(kept.isEmpty)
    }

    func testOverlargeSystemCountClampsBudgetToZero() {
        // Defensive: a systemBreakpointCount > 4 must not yield a negative budget.
        let tail = Pos(messageIndex: 0, blockIndex: 0)
        let kept = AnthropicRequestBuilder.clampBreakpointCandidates(
            tail: tail, document: nil, lookback: nil, systemBreakpointCount: 9)
        XCTAssertTrue(kept.isEmpty, "budget is floored at zero, never negative")
    }

    func testNilCandidatesAreSkipped() {
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        // Only lookback is non-nil; it is kept even though tail/document are absent.
        let kept = AnthropicRequestBuilder.clampBreakpointCandidates(
            tail: nil, document: nil, lookback: lookback, systemBreakpointCount: 0)
        XCTAssertEqual(kept, [lookback])
    }

    func testDuplicatePositionsCollapse() {
        // tail and document resolve to the same block -> the duplicate is not
        // double-counted, freeing budget for the distinct lookback.
        let shared = Pos(messageIndex: 3, blockIndex: 2)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        let kept = AnthropicRequestBuilder.clampBreakpointCandidates(
            tail: shared, document: shared, lookback: lookback, systemBreakpointCount: 2)
        // budget = 2: [shared, (dup shared skipped), lookback] -> two distinct.
        XCTAssertEqual(kept, [shared, lookback], "duplicate positions collapse to one")
    }

    // MARK: - addingEphemeralCacheControl: per-kind behavior

    func testAddsCacheControlToTextBlock() throws {
        let block = AnthropicContentBlock.text(AnthropicTextBlock(text: "hi"))
        let marked = try XCTUnwrap(AnthropicRequestBuilder.addingEphemeralCacheControl(to: block))
        guard case .text(let t) = marked else { return XCTFail("kind must be preserved") }
        XCTAssertEqual(t.text, "hi", "text content is preserved")
        XCTAssertEqual(t.cacheControl?.type, "ephemeral", "an ephemeral cache_control is attached")
    }

    func testAddsCacheControlToToolResultBlockPreservingFields() throws {
        let block = AnthropicContentBlock.toolResult(
            AnthropicToolResultBlock(toolUseId: "toolu_9", content: "result-body", isError: true))
        let marked = try XCTUnwrap(AnthropicRequestBuilder.addingEphemeralCacheControl(to: block))
        guard case .toolResult(let tr) = marked else { return XCTFail("kind must be preserved") }
        XCTAssertEqual(tr.toolUseId, "toolu_9")
        XCTAssertEqual(tr.content, "result-body", "tool result content is preserved")
        XCTAssertEqual(tr.isError, true, "error flag is preserved")
        XCTAssertEqual(tr.cacheControl?.type, "ephemeral")
    }

    func testAddsCacheControlToImageAndDocumentBlocks() throws {
        let image = AnthropicContentBlock.image(
            AnthropicImageBlock(source: AnthropicImageSource(mediaType: "image/png", data: "BASE64")))
        let markedImage = try XCTUnwrap(AnthropicRequestBuilder.addingEphemeralCacheControl(to: image))
        guard case .image(let i) = markedImage else { return XCTFail("image kind preserved") }
        XCTAssertEqual(i.cacheControl?.type, "ephemeral")
        XCTAssertEqual(i.source.data, "BASE64", "image source preserved")

        let document = AnthropicContentBlock.document(
            AnthropicDocumentBlock(source: AnthropicDocumentSource(mediaType: "application/pdf", data: "PDF64")))
        let markedDoc = try XCTUnwrap(AnthropicRequestBuilder.addingEphemeralCacheControl(to: document))
        guard case .document(let d) = markedDoc else { return XCTFail("document kind preserved") }
        XCTAssertEqual(d.cacheControl?.type, "ephemeral")
    }

    func testToolUseBlockCannotCarryCacheControl() {
        // tool_use blocks cannot carry cache_control in the fork's types — the
        // helper returns nil so placement skips them.
        let block = AnthropicContentBlock.toolUse(
            AnthropicToolUseBlock(id: "toolu_1", name: "glob", input: [:]))
        XCTAssertNil(AnthropicRequestBuilder.addingEphemeralCacheControl(to: block),
                     "tool_use returns nil — it cannot be a cache breakpoint")
    }
}
