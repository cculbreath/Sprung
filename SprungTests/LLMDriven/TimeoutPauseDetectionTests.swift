//
//  TimeoutPauseDetectionTests.swift
//  SprungTests
//
//  Covers the pure halves of the document-analysis timeout pause/retry feature:
//  (1) detecting a request-timeout across the error shapes onboarding actually sees,
//  kept DISJOINT from the budget predicate, and (2) partitioning extraction-pass
//  failure labels into the timeout-failed passes (mirrors BudgetPauseDetectionTests).
//

import XCTest
import SwiftOpenAI
@testable import Sprung

final class TimeoutPauseDetectionTests: XCTestCase {

    private let handler = LLMErrorHandler()

    // MARK: - isTimeoutError

    /// The real onboarding signature for a slow large-PDF chunk: URLSession aborts
    /// the request when time-to-first-byte exceeds `timeoutIntervalForRequest`.
    func testURLErrorTimedOutIsDetected() {
        XCTAssertTrue(handler.isTimeoutError(URLError(.timedOut)))
    }

    /// The fork surfaces its own timeout case for streamed requests.
    func testAPIErrorTimeOutIsDetected() {
        XCTAssertTrue(handler.isTimeoutError(APIError.timeOutError))
    }

    /// A stringified "request timed out" (e.g. carried in a pass-failure label).
    func testTimedOutDescriptionIsDetected() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                            userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        XCTAssertTrue(handler.isTimeoutError(error))
    }

    /// Disjoint from budget: an exhausted-balance error is NOT a timeout.
    func testInsufficientBalanceIsNotATimeout() {
        let body = #"{"error":{"message":"Your credit balance is too low. Please go to Plans & Billing."}}"#
        let error = APIError.responseUnsuccessful(description: "Request failed", statusCode: 400, responseBody: body)
        XCTAssertFalse(handler.isTimeoutError(error))
    }

    /// And the converse: a timeout is NOT an insufficient-balance error, so the two
    /// modals can never both claim the same failure.
    func testTimeoutIsNotInsufficientBalance() {
        XCTAssertFalse(handler.isInsufficientBalanceError(URLError(.timedOut)))
        XCTAssertFalse(handler.isInsufficientBalanceError(APIError.timeOutError))
    }

    func testUnrelatedErrorIsNotATimeout() {
        let error = APIError.responseUnsuccessful(description: "Overloaded", statusCode: 503, responseBody: "upstream overloaded")
        XCTAssertFalse(handler.isTimeoutError(error))
    }

    // MARK: - descriptionIndicatesTimeout (string predicate)

    func testDescriptionPredicateMatchesTimeoutStrings() {
        XCTAssertTrue(LLMErrorHandler.descriptionIndicatesTimeout("The request timed out."))
        XCTAssertTrue(LLMErrorHandler.descriptionIndicatesTimeout("Status: timeout while streaming"))
        // The fork's APIError.timeOutError stringifies to "Time Out Error." — a
        // pass-failure label built from it must still be recognized as a timeout.
        XCTAssertTrue(LLMErrorHandler.descriptionIndicatesTimeout("skill extraction — CV.pdf: Time Out Error."))
    }

    func testDescriptionPredicateRejectsBudgetStrings() {
        XCTAssertFalse(LLMErrorHandler.descriptionIndicatesTimeout("Your credit balance is too low"))
        XCTAssertFalse(LLMErrorHandler.descriptionIndicatesTimeout("Status 402: insufficient credits"))
    }

    // MARK: - Failure-label aggregation

    /// Only timeout failures are collected, OR-merged into one selection. The real
    /// pass-failure label format is "<pass> — <file>: <error>".
    func testTimeoutFailedPassSelectionMergesOnlyTimeoutFailures() {
        let timeoutMsg = "Request timed out"
        let failures = [
            "skill extraction — Doc.pdf: \(timeoutMsg)",
            "narrative cards — Doc.pdf: \(timeoutMsg)",
            "summary — Doc.pdf: Decoding strategies failed."   // non-timeout — ignored
        ]
        let passes = DocumentArtifactHandler.timeoutFailedPassSelection(from: failures)
        XCTAssertNotNil(passes)
        XCTAssertEqual(passes?.skills, true)
        XCTAssertEqual(passes?.narrativeCards, true)
        XCTAssertEqual(passes?.enrichment, true)   // cards re-select enrichment
        XCTAssertEqual(passes?.summary, false)     // its only failure was non-timeout
    }

    func testTimeoutFailedPassSelectionReturnsNilWhenNoTimeoutFailures() {
        let failures = [
            "summary — Doc.pdf: Decoding strategies failed.",
            "skill extraction — Doc.pdf: Status 400: Your credit balance is too low"
        ]
        XCTAssertNil(DocumentArtifactHandler.timeoutFailedPassSelection(from: failures))
    }

    /// A whole-document timeout (the no-silent-fallback foundation labels a total
    /// analysis failure "document analysis — <file>: …") selects every pass.
    func testDocumentAnalysisTimeoutSelectsAllPasses() {
        let passes = DocumentArtifactHandler.timeoutFailedPassSelection(
            from: ["document analysis — wpaf22.pdf: The request timed out."]
        )
        XCTAssertEqual(passes?.summary, true)
        XCTAssertEqual(passes?.skills, true)
        XCTAssertEqual(passes?.narrativeCards, true)
        XCTAssertEqual(passes?.enrichment, true)
    }

    // MARK: - Gate continuation

    /// The gate resolves its suspended continuation with the user's choice.
    @MainActor
    func testGateResolvesContinuation() async {
        let gate = TimeoutPauseGate()
        let info = TimeoutPauseInfo(filename: "wpaf22.pdf", attempt: 1)

        async let resolution = gate.awaitResolution(info)
        // Let awaitResolution install its continuation + set pendingPause.
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertNotNil(gate.pendingPause)
        gate.resolve(.keepWaiting)

        let result = await resolution
        if case .keepWaiting = result {} else { XCTFail("expected .keepWaiting") }
        XCTAssertNil(gate.pendingPause)
    }

    /// interrupt() force-aborts a pending pause (global stop / session reset).
    @MainActor
    func testGateInterruptAborts() async {
        let gate = TimeoutPauseGate()
        async let resolution = gate.awaitResolution(TimeoutPauseInfo(filename: "x.pdf", attempt: 1))
        try? await Task.sleep(for: .milliseconds(20))
        gate.interrupt()

        let result = await resolution
        if case .abort = result {} else { XCTFail("expected .abort") }
        XCTAssertNil(gate.pendingPause)
    }
}
