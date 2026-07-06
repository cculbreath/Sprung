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
//    - clampBreakpointCandidates(_:reservedBreakpointCount:) — the HARD CLAMP
//      (≤4 cache_control blocks INCLUDING reserved system/tool breakpoints; the
//      lowest-priority candidate is dropped first; the first/tail always survives)
//    - addingCacheControl(to:cacheControl:) — per-block-kind cache_control
//      attachment, returning nil for tool_use (cannot carry cache_control)
//    - BlockPosition value semantics
//    - plan(messages:)                  — the assembled placement for BOTH real
//      configs: onboarding (reserve the system block, .ephemeral) and revision
//      (1h TTL, reserve tool + system = 2). Both place only the moving tail +
//      >20-block lookback; large early payloads ride inside the cached prefix and
//      get NO fixed breakpoint of their own (a fixed early breakpoint strands the
//      cache once the moving breakpoints drift >20 blocks past it).
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
        case .toolUse, .serverToolUse, .webSearchToolResult, .webFetchToolResult: return nil
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

    func testKeepsAllCandidatesWhenUnderBudget() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        let extra = Pos(messageIndex: 2, blockIndex: 1)
        // budget = 4 - 0 = 4 -> all supplied candidates survive, in priority order.
        let kept = Planner.clampBreakpointCandidates(
            [tail, lookback, extra], reservedBreakpointCount: 0)
        XCTAssertEqual(kept, [tail, lookback, extra])
    }

    func testRealConfigsKeepTailAndLookback() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        // Onboarding (system reserved): budget = 4 - 1 = 3 -> both fit, one slot free.
        XCTAssertEqual(
            Planner.clampBreakpointCandidates([tail, lookback], reservedBreakpointCount: 1),
            [tail, lookback], "onboarding keeps tail + lookback with a slot to spare")
        // Revision (tool + system reserved): budget = 4 - 2 = 2 -> both fit exactly.
        XCTAssertEqual(
            Planner.clampBreakpointCandidates([tail, lookback], reservedBreakpointCount: 2),
            [tail, lookback], "revision keeps tail + lookback at exactly budget")
    }

    func testDropsLowestPriorityOnOverflow() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        let extra = Pos(messageIndex: 2, blockIndex: 1)

        // budget = 4 - 2 = 2 -> the third (lowest-priority) candidate is dropped.
        XCTAssertEqual(
            Planner.clampBreakpointCandidates([tail, lookback, extra], reservedBreakpointCount: 2),
            [tail, lookback], "lowest-priority candidate dropped first on overflow")

        // budget = 4 - 3 = 1 -> only the first (tail) survives.
        XCTAssertEqual(
            Planner.clampBreakpointCandidates([tail, lookback, extra], reservedBreakpointCount: 3),
            [tail], "the first/tail breakpoint always survives")
    }

    func testZeroBudgetKeepsNothing() {
        let tail = Pos(messageIndex: 5, blockIndex: 0)
        // budget = max(0, 4 - 4) = 0
        let kept = Planner.clampBreakpointCandidates([tail], reservedBreakpointCount: 4)
        XCTAssertTrue(kept.isEmpty)
    }

    func testOverlargeReservedCountClampsBudgetToZero() {
        // Defensive: a reservedBreakpointCount > 4 must not yield a negative budget.
        let tail = Pos(messageIndex: 0, blockIndex: 0)
        let kept = Planner.clampBreakpointCandidates([tail], reservedBreakpointCount: 9)
        XCTAssertTrue(kept.isEmpty, "budget is floored at zero, never negative")
    }

    func testNilCandidatesAreSkipped() {
        let lookback = Pos(messageIndex: 1, blockIndex: 0)
        // Only lookback is non-nil; it is kept even though the tail slot is absent.
        let kept = Planner.clampBreakpointCandidates([nil, lookback], reservedBreakpointCount: 0)
        XCTAssertEqual(kept, [lookback])
    }

    func testDuplicatePositionsCollapse() {
        // tail and lookback resolve to the same block -> the duplicate is not
        // double-counted, freeing budget for the distinct third candidate.
        let shared = Pos(messageIndex: 3, blockIndex: 2)
        let other = Pos(messageIndex: 1, blockIndex: 0)
        let kept = Planner.clampBreakpointCandidates([shared, shared, other], reservedBreakpointCount: 2)
        // budget = 2: [shared, (dup shared skipped), other] -> two distinct.
        XCTAssertEqual(kept, [shared, other], "duplicate positions collapse to one")
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
        let planner = Planner(cacheControl: .ephemeral, reservedBreakpointCount: 1)
        XCTAssertTrue(planner.plan(messages: []).isEmpty)
    }

    func testPlanMarksTailWithConfiguredTTL() {
        // Revision config: a single short message -> only the tail breakpoint, 1h TTL.
        let planner = Planner(cacheControl: oneHour, reservedBreakpointCount: 2)
        let planned = planner.plan(messages: [
            AnthropicMessage(role: "user", content: .blocks([.text(AnthropicTextBlock(text: "hello"))]))
        ])
        XCTAssertEqual(cacheControl(of: blocks(of: planned[0])[0])?.ttl, "1h",
                       "the tail breakpoint carries the configured 1h TTL")
    }

    func testPlanTailWalksBackOverToolUse() {
        // tool_use is the last block of the final message; the tail breakpoint must
        // walk back to the preceding markable (text) block.
        let planner = Planner(cacheControl: .ephemeral, reservedBreakpointCount: 2)
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

    func testPlanNeverMarksDocumentAsItsOwnBreakpoint() {
        // A document block is NEVER a breakpoint — the PDF rides inside the cached
        // prefix the moving tail/lookback chain extends over. A fixed breakpoint on
        // the early document would strand the read once the moving breakpoints drift
        // >20 blocks past it (the bug this placement removes).
        let planner = Planner(cacheControl: .ephemeral, reservedBreakpointCount: 1)
        let planned = planner.plan(messages: [
            AnthropicMessage(role: "user", content: .blocks([documentBlock(), .text(AnthropicTextBlock(text: "context"))])),
            AnthropicMessage(role: "assistant", content: .blocks([.text(AnthropicTextBlock(text: "reply"))]))
        ])
        let m0 = blocks(of: planned[0])
        let m1 = blocks(of: planned[1])
        XCTAssertNil(cacheControl(of: m0[0]), "the document block is not a breakpoint")
        XCTAssertNil(cacheControl(of: m0[1]), "the text after the document is not a breakpoint")
        XCTAssertNotNil(cacheControl(of: m1[0]), "only the moving tail breakpoint is planted")
    }

    func testPlanPlantsLookbackOnLargeConversation() {
        // >20 content blocks -> the lookback anchor fires, landing on the last
        // markable block ending at least 20 blocks before the end of the array.
        let planner = Planner(cacheControl: .ephemeral, reservedBreakpointCount: 2)
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
