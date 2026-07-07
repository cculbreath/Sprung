//
//  CaptureURLBufferTests.swift
//  SprungTests
//
//  Pure-logic coverage for AppDelegate.CaptureURLBuffer: the one-shot buffer that
//  holds a sprung://capture-job URL arriving before the main window's capture
//  consumer (AppSheetsModifier, hosted by UnifiedAppLayout) has mounted and
//  subscribed to .captureJobFromURL. Guards against silently dropping a capture
//  that fires during a cold launch.
//

import XCTest
@testable import Sprung

final class CaptureURLBufferTests: XCTestCase {

    // MARK: - Consumer already ready

    func testCaptureDeliversImmediatelyWhenConsumerAlreadyReady() {
        var buffer = CaptureURLBuffer()
        XCTAssertNil(buffer.consumerDidBecomeReady(), "no URL captured yet; nothing to drain")

        let delivered = buffer.capture("https://example.com/job/1")
        XCTAssertEqual(delivered, "https://example.com/job/1",
                       "once the consumer is ready, capture should hand back the URL for immediate delivery")
    }

    // MARK: - Cold-launch buffering

    func testCaptureBuffersWhenConsumerNotYetReady() {
        var buffer = CaptureURLBuffer()

        let delivered = buffer.capture("https://example.com/job/2")
        XCTAssertNil(delivered, "consumer not ready yet; capture must buffer, not drop or deliver")
    }

    func testConsumerDidBecomeReadyDrainsBufferedURL() {
        var buffer = CaptureURLBuffer()
        _ = buffer.capture("https://example.com/job/3")

        let drained = buffer.consumerDidBecomeReady()
        XCTAssertEqual(drained, "https://example.com/job/3",
                       "the buffered URL must be delivered exactly once the consumer signals ready")
    }

    // MARK: - One-shot delivery (never double-deliver)

    func testDrainIsIdempotentAfterFirstReadySignal() {
        var buffer = CaptureURLBuffer()
        _ = buffer.capture("https://example.com/job/4")

        XCTAssertEqual(buffer.consumerDidBecomeReady(), "https://example.com/job/4")
        XCTAssertNil(buffer.consumerDidBecomeReady(),
                     "a second ready signal (e.g. a re-mount) must not re-deliver the same URL")
    }

    func testSubsequentCapturesAfterConsumerReadyDeliverDirectlyEachTime() {
        var buffer = CaptureURLBuffer()
        XCTAssertNil(buffer.consumerDidBecomeReady())

        XCTAssertEqual(buffer.capture("https://example.com/job/5"), "https://example.com/job/5")
        XCTAssertEqual(buffer.capture("https://example.com/job/6"), "https://example.com/job/6")
    }

    // MARK: - Latest-wins semantics (single-slot buffer)

    func testLatestCaptureWinsWhenMultipleArriveBeforeReady() {
        var buffer = CaptureURLBuffer()

        XCTAssertNil(buffer.capture("https://example.com/job/first"))
        XCTAssertNil(buffer.capture("https://example.com/job/second"))

        XCTAssertEqual(buffer.consumerDidBecomeReady(), "https://example.com/job/second",
                       "buffer holds one slot; the most recent pre-ready capture should win")
    }

    // MARK: - Never drop: buffer-then-ready-then-capture-again round trip

    func testBufferThenReadyThenNewCaptureDoesNotResurfaceOldURL() {
        var buffer = CaptureURLBuffer()
        _ = buffer.capture("https://example.com/job/stale")
        XCTAssertEqual(buffer.consumerDidBecomeReady(), "https://example.com/job/stale")

        // A fresh capture after the consumer is already ready should deliver only
        // the new URL — the drained one must not leak back in.
        XCTAssertEqual(buffer.capture("https://example.com/job/fresh"), "https://example.com/job/fresh")
    }
}
