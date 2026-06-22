//
//  DocumentResumeFailureMergeTests.swift
//  SprungTests
//
//  Locks the contract for DocumentProcessingService.mergedFailures — the
//  failure-recompute applied when a timed-out document analysis pass is resumed
//  against the saved IR. A resume must (1) drop the timeout failures it just
//  retried, (2) keep unrelated failures (e.g. a budget outage on another pass),
//  and (3) fold in whatever the rerun reported.
//

import XCTest
@testable import Sprung

final class DocumentResumeFailureMergeTests: XCTestCase {

    func testRetriedTimeoutClearedWhenRerunSucceeds() {
        let merged = DocumentProcessingService.mergedFailures(
            prior: ["summary — wpaf22.pdf: Request timed out"],
            reran: []
        )
        XCTAssertTrue(merged.isEmpty, "A timeout failure must be removed once its pass is re-run cleanly")
    }

    func testBudgetFailureSurvivesTimeoutResume() {
        // Co-occurring failures: skills failed on budget, summary on timeout. Resuming
        // only the timeout pass must NOT erase the budget failure (it still needs a top-up).
        let merged = DocumentProcessingService.mergedFailures(
            prior: [
                "skill extraction — wpaf22.pdf: Your credit balance is too low",
                "summary — wpaf22.pdf: Request timed out"
            ],
            reran: []
        )
        XCTAssertEqual(
            merged,
            ["skill extraction — wpaf22.pdf: Your credit balance is too low"],
            "Non-timeout (budget) failures must survive a timeout resume"
        )
    }

    func testRerunFailureFoldedIn() {
        // The retried pass timed out again / failed differently — its fresh outcome
        // replaces the old timeout label rather than accumulating both.
        let merged = DocumentProcessingService.mergedFailures(
            prior: ["summary — wpaf22.pdf: Request timed out"],
            reran: ["summary — wpaf22.pdf: Status 400 — malformed response"]
        )
        XCTAssertEqual(merged, ["summary — wpaf22.pdf: Status 400 — malformed response"])
    }

    func testMultipleTimeoutsAllRetried() {
        let merged = DocumentProcessingService.mergedFailures(
            prior: [
                "summary — wpaf22.pdf: Request timed out",
                "narrative cards — wpaf22.pdf: The request timed out."
            ],
            reran: []
        )
        XCTAssertTrue(merged.isEmpty)
    }
}
