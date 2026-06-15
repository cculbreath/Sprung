//
//  AnthropicCacheBreakpointPlannerTests.swift
//  SprungTests
//
//  Phase 5 (LLM-driven subsystem tests — pure units), updated for tech-debt 1B.
//
//  AnthropicCacheBreakpointPlanner owns the prompt-cache breakpoint placement
//  that was previously duplicated near-verbatim in AnthropicRequestBuilder
//  (onboarding) and ResumeRevisionAgent (revision). It is BYTE-SENSITIVE — the
//  prompt-cache replay surface — and explicitly written "so the invariant is
//  inspectable in isolation". This suite locks:
//    - clampBreakpointCandidates(...)   — the HARD CLAMP (≤4 cache_control blocks
//      INCLUDING reserved system/tool breakpoints; drop lookback first, then
//      document; tail always survives)
//    - addingCacheControl(to:cacheControl:) — per-block-kind cache_control
//      attachment, returning nil for tool_use (cannot carry cache_control)
//    - BlockPosition value semantics
//    - plan(messages:)                  — the assembled placement for BOTH real
//      configs: onboarding (document breakpoint on, reserve the system block) and
//      revision (document off, 1h TTL, reserve tool + system = 2).
//  The end-to-end byte stability of the live onboarding path is additionally
//  gated by the replay suite + CachePrefixAuditor.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

final class AnthropicCacheBreakpointPlannerTests: XCTestCase {

    private typealias Planner = AnthropicCacheBreakpointPlanner
    private typealias Pos = AnthropicCacheBreakpointPlanner.BlockPosition

    /// The 1-hour TTL the revision agent uses for every breakpoint.
    private let oneHour = AnthropicCacheControl(type: "ephemeral", ttl: "1h")

    // MARK: - Helpers

    private func cacheControl(of block: AnthropicContentBlock) -> AnthropicCacheControl? {
        switch block {
        case .text(let b): return b.cacheControl
        case .image(let b): return b.cacheControl
        case .document(let b): return b.cacheControl
        case .toolResult(let b): return b.cacheControl
        case .toolUse: return nil
        }
    }

    private func blocks(of message: AnthropicMessage) -> [AnthropicContentBlock] {
        Planner.contentBlocks(of: message)
    }

    private func documentBlock(_ data: String = "PDF64") -> AnthropicContentBlock {
        .document(AnthropicDocumentBlock(source: AnthropicDocumentSource(mediaType: "application/pdf", data: data)))
    }

    // MARK: - BlockPosition value semantics

    func testBlockPositionEquatable() {
        XCTAssertEqual(Pos(messageIndex: 1, blockIndex: 2), Pos(messageIndex: 1, blockIndex: 2))
        XCTAssertNotEqual(Pos(messageIndex: 1, blockIndex: 2), Pos(messageIndex: 1, blockIndex: 3))
        XCTAssertNotEqual(Pos(messageIndex: 0, blockIndex: 2), Pos(messageIndex: 1, blockIndex: 2))
    }

    // MARK: - clampBreakpointCandidates: budget = 4 - reservedBreakpointCount

    func testKeepsAllThreeWhenNothingReserved() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        let document = Pos(messageIndex: 2, blockIndex: 1)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        // budget = 4 - 0 = 4 -> all three survive, in priority order.
        let kept = Planner.clampBreakpointCandidates(
            tail: tail, document: document, lookback: lookback, reservedBreakpointCount: 0)
        XCTAssertEqual(kept, [tail, document, lookback])
    }

    func testWithSystemReservedBudgetIsThree() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        let document = Pos(messageIndex: 2, blockIndex: 1)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        // Onboarding with a system breakpoint: budget = 4 - 1 = 3 -> all three fit.
        let kept = Planner.clampBreakpointCandidates(
            tail: tail, document: document, lookback: lookback, reservedBreakpointCount: 1)
        XCTAssertEqual(kept, [tail, document, lookback])
    }

    func testDropsLookbackFirstThenDocumentOnOverflow() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        let document = Pos(messageIndex: 2, blockIndex: 1)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)

        // Revision (tool + system reserved): budget = 4 - 2 = 2 -> lookback dropped first.
        let twoKept = Planner.clampBreakpointCandidates(
            tail: tail, document: document, lookback: lookback, reservedBreakpointCount: 2)
        XCTAssertEqual(twoKept, [tail, document], "lookback dropped first on overflow")

        // budget = 4 - 3 = 1 -> document dropped next; the tail always survives.
        let oneKept = Planner.clampBreakpointCandidates(
            tail: tail, document: document, lookback: lookback, reservedBreakpointCount: 3)
        XCTAssertEqual(oneKept, [tail], "document dropped next; tail breakpoint always survives")
    }

    func testZeroBudgetKeepsNothing() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        // budget = max(0, 4 - 4) = 0
        let kept = Planner.clampBreakpointCandidates(
            tail: tail, document: nil, lookback: nil, reservedBreakpointCount: 4)
        XCTAssertTrue(kept.isEmpty)
    }

    func testOverlargeReservedCountClampsBudgetToZero() {
        // Defensive: a reservedBreakpointCount > 4 must not yield a negative budget.
        let tail = Pos(messageIndex: 0, blockIndex: 0)
        let kept = Planner.clampBreakpointCandidates(
            tail: tail, document: nil, lookback: nil, reservedBreakpointCount: 9)
        XCTAssertTrue(kept.isEmpty, "budget is floored at zero, never negative")
    }

    func testNilCandidatesAreSkipped() {
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        // Only lookback is non-nil; it is kept even though tail/document are absent.
        let kept = Planner.clampBreakpointCandidates(
            tail: nil, document: nil, lookback: lookback, reservedBreakpointCount: 0)
        XCTAssertEqual(kept, [lookback])
    }

    func testDuplicatePositionsCollapse() {
        // tail and document resolve to the same block -> the duplicate is not
        // double-counted, freeing budget for the distinct lookback.
        let shared = Pos(messageIndex: 3, blockIndex: 2)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        let kept = Planner.clampBreakpointCandidates(
            tail: shared, document: shared, lookback: lookback, reservedBreakpointCount: 2)
        // budget = 2: [shared, (dup shared skipped), lookback] -> two distinct.
        XCTAssertEqual(kept, [shared, lookback], "duplicate positions collapse to one")
    }

    // MARK: - addingCacheControl: per-kind behavior

    func testAddsCacheControlToTextBlock() throws {
        let block = AnthropicContentBlock.text(AnthropicTextBlock(text: "hi"))
        let marked = try XCTUnwrap(Planner.addingCacheControl(to: block, cacheControl: .ephemeral))
        guard case .text(let t) = marked else { return XCTFail("kind must be preserved") }
        XCTAssertEqual(t.text, "hi", "text content is preserved")
        XCTAssertEqual(t.cacheControl?.type, "ephemeral", "an ephemeral cache_control is attached")
    }

    func testAttachesTheConfiguredTTL() throws {
        // The revision agent passes a 1-hour TTL; it must be carried through verbatim.
        let block = AnthropicContentBlock.text(AnthropicTextBlock(text: "hi"))
        let marked = try XCTUnwrap(Planner.addingCacheControl(to: block, cacheControl: oneHour))
        guard case .text(let t) = marked else { return XCTFail("kind must be preserved") }
        XCTAssertEqual(t.cacheControl?.type, "ephemeral")
        XCTAssertEqual(t.cacheControl?.ttl, "1h", "the configured 1h TTL is attached, not the 5m default")
    }

    func testAddsCacheControlToToolResultBlockPreservingFields() throws {
        let block = AnthropicContentBlock.toolResult(
            AnthropicToolResultBlock(toolUseId: "toolu_9", content: "result-body", isError: true))
        let marked = try XCTUnwrap(Planner.addingCacheControl(to: block, cacheControl: .ephemeral))
        guard case .toolResult(let tr) = marked else { return XCTFail("kind must be preserved") }
        XCTAssertEqual(tr.toolUseId, "toolu_9")
        XCTAssertEqual(tr.content, "result-body", "tool result content is preserved")
        XCTAssertEqual(tr.isError, true, "error flag is preserved")
        XCTAssertEqual(tr.cacheControl?.type, "ephemeral")
    }

    func testAddsCacheControlToImageAndDocumentBlocks() throws {
        let image = AnthropicContentBlock.image(
            AnthropicImageBlock(source: AnthropicImageSource(mediaType: "image/png", data: "BASE64")))
        let markedImage = try XCTUnwrap(Planner.addingCacheControl(to: image, cacheControl: .ephemeral))
        guard case .image(let i) = markedImage else { return XCTFail("image kind preserved") }
        XCTAssertEqual(i.cacheControl?.type, "ephemeral")
        XCTAssertEqual(i.source.data, "BASE64", "image source preserved")

        let markedDoc = try XCTUnwrap(Planner.addingCacheControl(to: documentBlock(), cacheControl: .ephemeral))
        guard case .document(let d) = markedDoc else { return XCTFail("document kind preserved") }
        XCTAssertEqual(d.cacheControl?.type, "ephemeral")
    }

    func testToolUseBlockCannotCarryCacheControl() {
        // tool_use blocks cannot carry cache_control in the fork's types — the
        // helper returns nil so placement skips them.
        let block = AnthropicContentBlock.toolUse(
            AnthropicToolUseBlock(id: "toolu_1", name: "glob", input: [:]))
        XCTAssertNil(Planner.addingCacheControl(to: block, cacheControl: .ephemeral),
                     "tool_use returns nil — it cannot be a cache breakpoint")
    }

    // MARK: - plan(messages:) — assembled placement for both real configs

    func testPlanReturnsInputUnchangedWhenEmpty() {
        let planner = Planner(cacheControl: .ephemeral, includeDocumentBreakpoint: true, reservedBreakpointCount: 1)
        XCTAssertTrue(planner.plan(messages: []).isEmpty)
    }

    func testPlanMarksTailWithConfiguredTTL() {
        // Revision config: a single short message -> only the tail breakpoint, 1h TTL.
        let planner = Planner(cacheControl: oneHour, includeDocumentBreakpoint: false, reservedBreakpointCount: 2)
        let planned = planner.plan(messages: [
            AnthropicMessage(role: "user", content: .blocks([.text(AnthropicTextBlock(text: "hello"))]))
        ])
        XCTAssertEqual(cacheControl(of: blocks(of: planned[0])[0])?.ttl, "1h",
                       "the tail breakpoint carries the configured 1h TTL")
    }

    func testPlanTailWalksBackOverToolUse() {
        // tool_use is the last block of the final message; the tail breakpoint must
        // walk back to the preceding markable (text) block.
        let planner = Planner(cacheControl: .ephemeral, includeDocumentBreakpoint: false, reservedBreakpointCount: 2)
        let planned = planner.plan(messages: [
            AnthropicMessage(role: "assistant", content: .blocks([
                .text(AnthropicTextBlock(text: "thinking")),
                .toolUse(AnthropicToolUseBlock(id: "toolu_1", name: "glob", input: [:]))
            ]))
        ])
        let b = blocks(of: planned[0])
        XCTAssertNotNil(cacheControl(of: b[0]), "the text block carries the tail breakpoint")
        XCTAssertNil(cacheControl(of: b[1]), "tool_use cannot carry cache_control")
    }

    func testPlanMarksDocumentBreakpointWhenEnabled() {
        // Onboarding config: document breakpoint ON. The last document block is
        // marked in addition to the moving tail; the text between them is not.
        let planner = Planner(cacheControl: .ephemeral, includeDocumentBreakpoint: true, reservedBreakpointCount: 1)
        let planned = planner.plan(messages: [
            AnthropicMessage(role: "user", content: .blocks([documentBlock(), .text(AnthropicTextBlock(text: "context"))])),
            AnthropicMessage(role: "assistant", content: .blocks([.text(AnthropicTextBlock(text: "reply"))]))
        ])
        let m0 = blocks(of: planned[0])
        let m1 = blocks(of: planned[1])
        XCTAssertNotNil(cacheControl(of: m0[0]), "the document block carries the document breakpoint")
        XCTAssertNil(cacheControl(of: m0[1]), "the text between document and tail is not marked")
        XCTAssertNotNil(cacheControl(of: m1[0]), "the final message carries the tail breakpoint")
    }

    func testPlanIgnoresDocumentBreakpointWhenDisabled() {
        // Revision config: document breakpoint OFF -> a document block is NOT a
        // breakpoint even though one is present (the PDF rides in the cached prefix).
        let planner = Planner(cacheControl: oneHour, includeDocumentBreakpoint: false, reservedBreakpointCount: 2)
        let planned = planner.plan(messages: [
            AnthropicMessage(role: "user", content: .blocks([documentBlock()])),
            AnthropicMessage(role: "assistant", content: .blocks([.text(AnthropicTextBlock(text: "reply"))]))
        ])
        XCTAssertNil(cacheControl(of: blocks(of: planned[0])[0]),
                     "the document is not a breakpoint when includeDocumentBreakpoint is false")
        XCTAssertNotNil(cacheControl(of: blocks(of: planned[1])[0]), "only the tail breakpoint is planted")
    }

    func testPlanPlantsLookbackOnLargeConversation() {
        // >20 content blocks -> the lookback anchor fires, landing on the last
        // markable block ending at least 20 blocks before the end of the array.
        let planner = Planner(cacheControl: .ephemeral, includeDocumentBreakpoint: false, reservedBreakpointCount: 2)
        let bulk = (0..<25).map { AnthropicContentBlock.text(AnthropicTextBlock(text: "b\($0)")) }
        let planned = planner.plan(messages: [
            AnthropicMessage(role: "user", content: .blocks([.text(AnthropicTextBlock(text: "head"))])),
            AnthropicMessage(role: "assistant", content: .blocks(bulk)),
            AnthropicMessage(role: "user", content: .blocks([.text(AnthropicTextBlock(text: "tail"))]))
        ])
        let head = blocks(of: planned[0])
        let mid = blocks(of: planned[1])
        let tail = blocks(of: planned[2])
        XCTAssertNotNil(cacheControl(of: tail[0]), "tail breakpoint on the final message")
        XCTAssertNotNil(cacheControl(of: head[0]), "lookback anchor lands ≥20 blocks before the end")
        XCTAssertTrue(mid.allSatisfy { cacheControl(of: $0) == nil }, "no breakpoint inside the bulk middle message")
    }
}
