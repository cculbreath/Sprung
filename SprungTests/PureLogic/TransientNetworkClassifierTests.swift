//
//  TransientNetworkClassifierTests.swift
//  SprungTests
//
//  Pins the retry-gate contract: extraction passes (skills / narrative cards) may
//  retry ONLY transient network conditions. A malformed/schema/decode failure — most
//  importantly the truncated-JSON parse error a mid-stream connection drop produces —
//  must classify as NON-transient so the pass surfaces it instead of blanket-retrying
//  and re-burning tokens.
//

import XCTest
@testable import Sprung

final class TransientNetworkClassifierTests: XCTestCase {
    private let handler = LLMErrorHandler()

    // MARK: - Transient (retry)

    func testNetworkConnectionLostIsTransient() {
        XCTAssertTrue(handler.isTransientNetworkError(URLError(.networkConnectionLost)))
    }

    func testTimedOutIsTransient() {
        XCTAssertTrue(handler.isTransientNetworkError(URLError(.timedOut)))
    }

    func testNotConnectedIsTransient() {
        XCTAssertTrue(handler.isTransientNetworkError(URLError(.notConnectedToInternet)))
    }

    func testCannotConnectToHostIsTransient() {
        XCTAssertTrue(handler.isTransientNetworkError(URLError(.cannotConnectToHost)))
    }

    // MARK: - Non-transient (fail fast)

    func testParseFailureIsNotTransient() {
        // The blip's truncated-JSON decode error must NOT trigger a blanket retry.
        let parseError = NSError(
            domain: "Test", code: 1,
            userInfo: [NSLocalizedDescriptionKey:
                "Failed to parse structured response: The data couldn’t be read because it isn’t in the correct format."]
        )
        XCTAssertFalse(handler.isTransientNetworkError(parseError))
    }

    func testBadURLIsNotTransient() {
        XCTAssertFalse(handler.isTransientNetworkError(URLError(.badURL)))
    }

    func testGenericContentErrorIsNotTransient() {
        let contentError = NSError(
            domain: "Test", code: 400,
            userInfo: [NSLocalizedDescriptionKey: "Status 400: invalid_request_error"]
        )
        XCTAssertFalse(handler.isTransientNetworkError(contentError))
    }

    // MARK: - String predicate

    func testStringPredicateMatchesNetworkDrop() {
        XCTAssertTrue(LLMErrorHandler.descriptionIndicatesTransientNetwork("The network connection was lost."))
    }

    func testStringPredicateRejectsParseFailure() {
        XCTAssertFalse(
            LLMErrorHandler.descriptionIndicatesTransientNetwork(
                "The data couldn’t be read because it isn’t in the correct format."
            )
        )
    }
}
