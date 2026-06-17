//
//  RevisionStreamFailureClassifierTests.swift
//  SprungTests
//
//  Pure-logic coverage for RevisionStreamFailureClassifier, the dependency-free
//  classifier extracted from ResumeRevisionAgent. Three concerns:
//    1. classifyStreamFailure — which errors are FATAL (retrying can't heal) vs
//       TRANSIENT (worth a back-off retry). Encodes the real transient HTTP code
//       set {408,429,500,502,503,504,529}, the LLMError split, and the catch-all.
//    2. isFatalStreamErrorEvent — Anthropic in-stream `error` event type substrings
//       that are fatal.
//    3. isCompleteJSONObject — truncated-tool-input detection (JSONSerialization).
//
//  These assertions are read off the implementation; they document the contract,
//  not an aspiration. JSONSerialization's top-level-must-be-object/array quirk is
//  intentionally pinned below.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

final class RevisionStreamFailureClassifierTests: XCTestCase {

    // MARK: - classifyStreamFailure: APIError.responseUnsuccessful status codes

    /// The exact transient set the implementation retries on.
    private let transientStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504, 529]

    func testTransientHTTPStatusCodesAreNotFatal() {
        for code in transientStatusCodes {
            let error = APIError.responseUnsuccessful(description: "boom", statusCode: code, responseBody: nil)
            let result = RevisionStreamFailureClassifier.classifyStreamFailure(error)
            XCTAssertFalse(result.isFatal, "HTTP \(code) should be transient (retryable)")
        }
    }

    func testFatalHTTPStatusCodesAreFatal() {
        // A representative sample of codes NOT in the transient set. 400/401/403/404
        // are client/auth/request problems retrying can't fix; 501 is the lone 5xx
        // the impl treats as fatal (not in the set).
        for code in [400, 401, 402, 403, 404, 422, 501] {
            let error = APIError.responseUnsuccessful(description: "boom", statusCode: code, responseBody: nil)
            let result = RevisionStreamFailureClassifier.classifyStreamFailure(error)
            XCTAssertTrue(result.isFatal, "HTTP \(code) should be fatal (not retryable)")
        }
    }

    func testResponseUnsuccessfulMessageIsDisplayDescription() {
        let error = APIError.responseUnsuccessful(description: "rate limited", statusCode: 429, responseBody: nil)
        let result = RevisionStreamFailureClassifier.classifyStreamFailure(error)
        XCTAssertEqual(result.message, error.displayDescription)
        XCTAssertEqual(result.message, "Status 429: rate limited")
    }

    // MARK: - classifyStreamFailure: other APIError cases

    func testNonResponseUnsuccessfulAPIErrorIsTransient() {
        // Any APIError that is NOT .responseUnsuccessful falls through to the
        // (isFatal: false) branch — including request failures and timeouts.
        let cases: [APIError] = [
            .requestFailed(description: "conn reset"),
            .timeOutError,
            .invalidData
        ]
        for error in cases {
            let result = RevisionStreamFailureClassifier.classifyStreamFailure(error)
            XCTAssertFalse(result.isFatal, "non-responseUnsuccessful APIError should be transient: \(error)")
            XCTAssertEqual(result.message, error.displayDescription)
        }
    }

    // MARK: - classifyStreamFailure: LLMError split

    func testFatalLLMErrors() {
        let fatalCases: [LLMError] = [
            .clientError("bad request shape"),
            .unauthorized("some-model"),
            .invalidModelId("dead-model")
        ]
        for error in fatalCases {
            let result = RevisionStreamFailureClassifier.classifyStreamFailure(error)
            XCTAssertTrue(result.isFatal, "LLMError should be fatal: \(error)")
            XCTAssertEqual(result.message, error.localizedDescription)
        }
    }

    func testTransientLLMErrors() {
        let transientCases: [LLMError] = [
            .decodingFailed(NSError(domain: "t", code: 1)),
            .unexpectedResponseFormat,
            .rateLimited(retryAfter: 5),
            .timeout,
            .insufficientCredits(requested: 100, available: 10)
        ]
        for error in transientCases {
            let result = RevisionStreamFailureClassifier.classifyStreamFailure(error)
            XCTAssertFalse(result.isFatal, "LLMError should be transient: \(error)")
            XCTAssertEqual(result.message, error.localizedDescription)
        }
    }

    // MARK: - classifyStreamFailure: catch-all

    func testUnknownErrorIsTransient() {
        let error = NSError(domain: "network", code: -1009, userInfo: [NSLocalizedDescriptionKey: "offline"])
        let result = RevisionStreamFailureClassifier.classifyStreamFailure(error)
        XCTAssertFalse(result.isFatal, "An unrecognized error should be treated as transient")
        XCTAssertEqual(result.message, error.localizedDescription)
    }

    // MARK: - isFatalStreamErrorEvent

    func testFatalAnthropicErrorTypesAreSubstringMatched() {
        // The impl uses String.contains, so the type need only appear somewhere in
        // the message (e.g. embedded in a JSON error payload).
        let fatalSubstrings = [
            "authentication_error",
            "permission_error",
            "invalid_request_error",
            "not_found_error",
            "request_too_large"
        ]
        for substring in fatalSubstrings {
            XCTAssertTrue(
                RevisionStreamFailureClassifier.isFatalStreamErrorEvent(substring),
                "\(substring) alone should be fatal"
            )
            let embedded = "{\"type\":\"error\",\"error\":{\"type\":\"\(substring)\",\"message\":\"nope\"}}"
            XCTAssertTrue(
                RevisionStreamFailureClassifier.isFatalStreamErrorEvent(embedded),
                "\(substring) embedded in a payload should be fatal"
            )
        }
    }

    func testNonFatalAnthropicErrorTypesAreNotFatal() {
        // overloaded_error / api_error / rate_limit_error are server-side/transient
        // and are NOT in the fatal list — they should retry.
        let transientMessages = [
            "overloaded_error",
            "api_error",
            "rate_limit_error",
            "the server hiccuped",
            ""
        ]
        for message in transientMessages {
            XCTAssertFalse(
                RevisionStreamFailureClassifier.isFatalStreamErrorEvent(message),
                "\(message) should NOT be classified fatal"
            )
        }
    }

    // MARK: - isCompleteJSONObject

    func testCompleteJSONObjectIsComplete() {
        XCTAssertTrue(RevisionStreamFailureClassifier.isCompleteJSONObject("{\"a\":1,\"b\":[2,3]}"))
        // A top-level array is also a valid JSON object per JSONSerialization.
        XCTAssertTrue(RevisionStreamFailureClassifier.isCompleteJSONObject("[1,2,3]"))
    }

    func testTruncatedJSONObjectIsNotComplete() {
        // The max_tokens truncation case: input cut off mid-object.
        XCTAssertFalse(RevisionStreamFailureClassifier.isCompleteJSONObject("{\"a\":1,\"b\":"))
        XCTAssertFalse(RevisionStreamFailureClassifier.isCompleteJSONObject("{\"a\":1"))
    }

    func testEmptyStringIsNotComplete() {
        XCTAssertFalse(RevisionStreamFailureClassifier.isCompleteJSONObject(""))
    }

    func testNonJSONIsNotComplete() {
        XCTAssertFalse(RevisionStreamFailureClassifier.isCompleteJSONObject("not json at all"))
        // Bare scalars are NOT valid top-level JSON for JSONSerialization (no
        // .fragmentsAllowed option), so a bare number/string reads as incomplete.
        XCTAssertFalse(RevisionStreamFailureClassifier.isCompleteJSONObject("42"))
        XCTAssertFalse(RevisionStreamFailureClassifier.isCompleteJSONObject("\"hello\""))
    }
}
