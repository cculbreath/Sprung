//
//  BudgetPauseDetectionTests.swift
//  SprungTests
//
//  Covers the pure halves of the insufficient-balance pause/resume feature:
//  (1) detecting an exhausted-balance error across the shapes onboarding actually
//  sees, and (2) mapping extraction-pass failure labels to the passes to re-run.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

final class BudgetPauseDetectionTests: XCTestCase {

    private let handler = LLMErrorHandler()

    // MARK: - isInsufficientBalanceError

    /// The real onboarding signature: Anthropic returns HTTP 400 with a
    /// credit-balance body (never mapped to LLMError because onboarding calls the
    /// Anthropic service directly).
    func testAnthropic400CreditBalanceBodyIsDetected() {
        let body = #"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."},"request_id":"req_x"}"#
        let error = APIError.responseUnsuccessful(description: "Request failed", statusCode: 400, responseBody: body)
        XCTAssertTrue(handler.isInsufficientBalanceError(error))
    }

    /// OpenRouter-style 402 by status code, even without a descriptive body.
    func test402StatusCodeIsDetected() {
        let error = APIError.responseUnsuccessful(description: "Payment Required", statusCode: 402, responseBody: nil)
        XCTAssertTrue(handler.isInsufficientBalanceError(error))
    }

    /// The mapped domain error (OpenRouter path).
    func testLLMErrorInsufficientCreditsIsDetected() {
        XCTAssertTrue(handler.isInsufficientBalanceError(LLMError.insufficientCredits(requested: 64_000, available: 12_000)))
    }

    /// An unrelated 400 (e.g. a schema validation error) must NOT be treated as a
    /// balance problem — topping up wouldn't fix it.
    func testUnrelatedBadRequestIsNotDetected() {
        let body = #"{"type":"error","error":{"type":"invalid_request_error","message":"tools.0.custom.input_schema: additionalProperties is required"}}"#
        let error = APIError.responseUnsuccessful(description: "Request failed", statusCode: 400, responseBody: body)
        XCTAssertFalse(handler.isInsufficientBalanceError(error))
    }

    func testServerErrorIsNotDetected() {
        let error = APIError.responseUnsuccessful(description: "Overloaded", statusCode: 503, responseBody: "upstream overloaded")
        XCTAssertFalse(handler.isInsufficientBalanceError(error))
    }

    // MARK: - Failure-label → PassSelection

    func testSummaryLabelMapsToSummaryPass() {
        let passes = BudgetFailedExtractionRegistry.passSelection(forFailureLabel: "summary — Resume.pdf: Status 400: Request failed")
        XCTAssertEqual(passes?.summary, true)
        XCTAssertEqual(passes?.skills, false)
        XCTAssertEqual(passes?.narrativeCards, false)
        XCTAssertEqual(passes?.enrichment, false)
    }

    func testSkillLabelMapsToSkillsPass() {
        let passes = BudgetFailedExtractionRegistry.passSelection(forFailureLabel: "skill extraction — CV.pdf: Status 400: Request failed")
        XCTAssertEqual(passes?.skills, true)
        XCTAssertEqual(passes?.summary, false)
        XCTAssertEqual(passes?.narrativeCards, false)
    }

    /// Narrative-card failures also re-select enrichment (it runs off cards).
    func testNarrativeCardsLabelMapsToCardsAndEnrichment() {
        let passes = BudgetFailedExtractionRegistry.passSelection(forFailureLabel: "narrative cards — Website.txt: Status 400")
        XCTAssertEqual(passes?.narrativeCards, true)
        XCTAssertEqual(passes?.enrichment, true)
        XCTAssertEqual(passes?.summary, false)
        XCTAssertEqual(passes?.skills, false)
    }

    func testUnrecognizedLabelMapsToNil() {
        XCTAssertNil(BudgetFailedExtractionRegistry.passSelection(forFailureLabel: "verification — file.pdf: timeout"))
    }

    // MARK: - Aggregation across a document's failures

    /// Only budget failures are collected, and they are OR-merged into one selection.
    func testBudgetFailedPassSelectionMergesOnlyBudgetFailures() {
        let creditMsg = "Status 400: Request failed - Response: {\"error\":{\"message\":\"Your credit balance is too low\"}}"
        let failures = [
            "skill extraction — Doc.pdf: \(creditMsg)",
            "narrative cards — Doc.pdf: \(creditMsg)",
            "summary — Doc.pdf: Decoding strategies failed."   // non-budget — ignored
        ]
        let passes = DocumentArtifactHandler.budgetFailedPassSelection(from: failures)
        XCTAssertNotNil(passes)
        XCTAssertEqual(passes?.skills, true)
        XCTAssertEqual(passes?.narrativeCards, true)
        XCTAssertEqual(passes?.enrichment, true)
        XCTAssertEqual(passes?.summary, false)  // its only failure was non-budget
    }

    func testBudgetFailedPassSelectionReturnsNilWhenNoBudgetFailures() {
        let failures = [
            "summary — Doc.pdf: Decoding strategies failed.",
            "skill extraction — Doc.pdf: Time Out Error."
        ]
        XCTAssertNil(DocumentArtifactHandler.budgetFailedPassSelection(from: failures))
    }
}
