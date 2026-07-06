//
//  AnthropicTransientRetryPolicyTests.swift
//  SprungTests
//
//  Pins the transient/terminal classification and the backoff shape for the
//  direct-Anthropic retry chokepoints in `LLMFacadeSpecializedAPIs`.
//
//  The single most load-bearing contract here: Anthropic's raw HTTP 400
//  "credit balance is too low" is TERMINAL for the retry layer but still
//  recognized by `LLMErrorHandler.isInsufficientBalanceError` — the retry
//  chokepoint must hand that error through unchanged so the BudgetPauseGate
//  pause/resume flow (and the budget-failed extraction-pass re-run) keep
//  working exactly as before.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

final class AnthropicTransientRetryPolicyTests: XCTestCase {

    private func http(_ statusCode: Int, body: String? = nil) -> Error {
        APIError.responseUnsuccessful(description: "Request failed", statusCode: statusCode, responseBody: body)
    }

    /// The wire body Anthropic sends with the exhausted-balance 400 (the error
    /// bypasses LLMRequestExecutor entirely, so it is never an `LLMError`).
    private let creditBalanceBody = #"""
    {"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."}}
    """#

    // MARK: - Transient (retryable)

    func testConnectLevelURLErrorsAreTransient() {
        let codes: [URLError.Code] = [
            .timedOut, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
        ]
        for code in codes {
            XCTAssertNotNil(
                AnthropicTransientRetryPolicy.transientLabel(for: URLError(code)),
                "URLError \(code.rawValue) is a transient network drop and must be retryable"
            )
        }
    }

    func testServerErrorsOverloadedAndRateLimitAreTransient() {
        for status in [500, 502, 503, 504, 529, 429] {
            XCTAssertNotNil(
                AnthropicTransientRetryPolicy.transientLabel(for: http(status)),
                "HTTP \(status) must be retryable"
            )
        }
        // 529 is Anthropic's overloaded_error; the label should say so.
        XCTAssertEqual(AnthropicTransientRetryPolicy.transientLabel(for: http(529)), "HTTP 529 overloaded")
        XCTAssertEqual(AnthropicTransientRetryPolicy.transientLabel(for: http(429)), "HTTP 429 rate limited")
    }

    func testForkTimeoutErrorIsTransient() {
        XCTAssertNotNil(AnthropicTransientRetryPolicy.transientLabel(for: APIError.timeOutError))
    }

    // MARK: - Terminal (never retried)

    func testInsufficientBalance400IsTerminalYetStillRecognizedByBudgetGatePredicate() {
        let error = http(400, body: creditBalanceBody)
        XCTAssertNil(
            AnthropicTransientRetryPolicy.transientLabel(for: error),
            "the credit-balance 400 must NOT be retried — BudgetPauseGate owns that flow"
        )
        // The retry layer rethrows the original error unchanged, so the budget
        // predicate downstream must still match it.
        XCTAssertTrue(
            LLMErrorHandler().isInsufficientBalanceError(error),
            "the same error must still be recognized by the insufficient-balance predicate"
        )
    }

    func testOtherClientErrorsAreTerminal() {
        for status in [400, 401, 403, 404, 422] {
            XCTAssertNil(
                AnthropicTransientRetryPolicy.transientLabel(for: http(status)),
                "HTTP \(status) is a validation/auth failure — a retry would re-fail identically"
            )
        }
    }

    func testDecodeAndRequestShapeFailuresAreTerminal() {
        // A connection dropped mid-stream can surface as a decode error; recovery
        // for the interview stream is resume, and the structured chokepoint only
        // retries genuine network/server classes — matching LLMErrorHandler's
        // long-standing doctrine that decode failures are non-transient.
        let errors: [Error] = [
            APIError.requestFailed(description: "boom"),
            APIError.invalidData,
            APIError.jsonDecodingFailure(description: "truncated"),
            APIError.dataCouldNotBeReadMissingData(description: "missing"),
            APIError.bothDecodingStrategiesFailed,
        ]
        for error in errors {
            XCTAssertNil(AnthropicTransientRetryPolicy.transientLabel(for: error))
        }
    }

    func testCancellationIsTerminal() {
        XCTAssertNil(AnthropicTransientRetryPolicy.transientLabel(for: CancellationError()))
        XCTAssertNil(AnthropicTransientRetryPolicy.transientLabel(for: URLError(.cancelled)))
    }

    func testDomainErrorsAreTerminal() {
        XCTAssertNil(AnthropicTransientRetryPolicy.transientLabel(for: LLMError.clientError("not configured")))
    }

    // MARK: - Backoff shape

    func testBackoffDoublesWithBoundedJitter() {
        let policy = AnthropicTransientRetryPolicy(maxAttempts: 3, baseDelay: 1.0)
        for _ in 0..<50 {
            let beforeSecond = policy.delay(beforeAttempt: 2)
            XCTAssertGreaterThanOrEqual(beforeSecond, 0.8)
            XCTAssertLessThanOrEqual(beforeSecond, 1.2)

            let beforeThird = policy.delay(beforeAttempt: 3)
            XCTAssertGreaterThanOrEqual(beforeThird, 1.6)
            XCTAssertLessThanOrEqual(beforeThird, 2.4)

            let beforeFourth = policy.delay(beforeAttempt: 4)
            XCTAssertGreaterThanOrEqual(beforeFourth, 3.2)
            XCTAssertLessThanOrEqual(beforeFourth, 4.8)
        }
    }

    func testZeroBaseDelayYieldsZeroDelays() {
        let policy = AnthropicTransientRetryPolicy(maxAttempts: 3, baseDelay: 0)
        XCTAssertEqual(policy.delay(beforeAttempt: 2), 0)
        XCTAssertEqual(policy.delay(beforeAttempt: 3), 0)
    }

    func testInitClampsDegenerateValues() {
        let policy = AnthropicTransientRetryPolicy(maxAttempts: 0, baseDelay: -1)
        XCTAssertEqual(policy.maxAttempts, 1, "at least one attempt always runs")
        XCTAssertEqual(policy.baseDelay, 0)
        XCTAssertEqual(policy.delay(beforeAttempt: 2), 0)
    }
}
