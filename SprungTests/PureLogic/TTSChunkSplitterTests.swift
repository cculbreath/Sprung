//
//  TTSChunkSplitterTests.swift
//  SprungTests
//
//  Phase 5 — pure TTS text-prep (chunking / truncation / markdown stripping)
//  extracted from OpenAITTSProvider + TTSViewModel.
//

import XCTest
@testable import Sprung

final class TTSChunkSplitterTests: XCTestCase {

    // MARK: - splitIntoChunks

    func testShortTextIsOneChunk() {
        let chunks = TTSChunkSplitter.splitIntoChunks("One sentence. Two sentences.")
        XCTAssertEqual(chunks.count, 1)
    }

    func testSplitsWhenExceedingMaxLength() {
        // Each sentence ~12 chars; maxLength 20 forces multiple chunks.
        let text = "aaaa bbbb. cccc dddd. eeee ffff. gggg hhhh."
        let chunks = TTSChunkSplitter.splitIntoChunks(text, maxLength: 20)
        XCTAssertGreaterThan(chunks.count, 1)
        // No chunk wildly exceeds the limit (a single sentence may, but combos won't grow unbounded).
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 40, "chunks should stay near the limit")
        }
    }

    func testEmptyTextProducesNoChunks() {
        XCTAssertTrue(TTSChunkSplitter.splitIntoChunks("").isEmpty)
        XCTAssertTrue(TTSChunkSplitter.splitIntoChunks("   \n  ").isEmpty)
    }

    func testTerminatorPunctuationIsNormalizedToPeriod() {
        // DOCUMENTED QUIRK (preserved from the original): the splitter breaks on
        // any of .!? but re-terminates every sentence with ". ", so "?" and "!"
        // become "." in the output. This is intentional-as-shipped, not a fix target.
        let chunks = TTSChunkSplitter.splitIntoChunks("Why? Stop!")
        XCTAssertEqual(chunks, ["Why. Stop."])
    }

    // MARK: - truncate

    func testTruncateLeavesShortTextUnchanged() {
        XCTAssertEqual(TTSChunkSplitter.truncate("hello world", maxLength: 100), "hello world")
    }

    func testTruncateCutsAtWordBoundaryWithEllipsis() {
        // "hello world foo" prefix(11) = "hello world", last space before end -> "hello..."
        let out = TTSChunkSplitter.truncate("hello world foobar", maxLength: 11)
        XCTAssertEqual(out, "hello...")
        XCTAssertFalse(out.contains("foobar"))
    }

    func testTruncateNoSpaceAppendsEllipsis() {
        XCTAssertEqual(TTSChunkSplitter.truncate("abcdefghij", maxLength: 4), "abcd...")
    }

    // MARK: - cleanMarkup

    func testCleanMarkupStripsMarkers() {
        XCTAssertEqual(TTSChunkSplitter.cleanMarkup("# Heading **bold** *italic*"), "Heading bold italic")
    }

    func testCleanMarkupTrimsWhitespace() {
        XCTAssertEqual(TTSChunkSplitter.cleanMarkup("  \n plain  \n"), "plain")
    }
}
