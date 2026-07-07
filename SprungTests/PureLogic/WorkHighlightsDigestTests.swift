//
//  WorkHighlightsDigestTests.swift
//  SprungTests
//
//  Pure-logic coverage for the WorkHighlights per-entry evidence digest
//  (buildTaskContext) and its shared guardrail block (highlightGuidelines).
//
//  Contract pinned here: KC enrichment threads into the highlights prompt as
//  GROUNDING source material — a card's documented `outcomes` and `technologies`
//  reach the per-entry digest — while the anti-slop FORBIDDEN block that governs
//  the generated bullets stays intact. Threading real captured results is NOT a
//  license to fabricate metric-formula bullets; both must coexist.
//

import XCTest
import SwiftyJSON
@testable import Sprung

@MainActor
final class WorkHighlightsDigestTests: XCTestCase {

    private func workEntry(company: String = "Acme", title: String = "Staff Engineer") -> JSON {
        JSON(["experienceType": "work", "company": company, "title": title])
    }

    private func enrichedCard() -> KnowledgeCard {
        let card = KnowledgeCard(title: "Sensor Platform", narrative: "n", organization: "Acme")
        card.facts = [
            KnowledgeCardFact(category: "role", statement: "Led firmware for the sensor array",
                              confidence: nil, source: nil)
        ]
        card.suggestedBullets = ["Built the telemetry ingestion pipeline"]
        card.outcomes = ["Cut nightly build time from 40 minutes to 6 minutes"]
        card.technologies = ["Rust", "gRPC", "Postgres"]
        return card
    }

    // MARK: - Enrichment reaches the per-entry digest

    func testDigestIncludesDocumentedOutcomes() {
        let digest = WorkHighlightsGenerator().buildTaskContext(
            entry: workEntry(), kcs: [enrichedCard()])
        XCTAssertTrue(digest.contains("**Documented Outcomes:**"),
                      "documented outcomes must reach the per-entry highlights digest")
        XCTAssertTrue(digest.contains("Cut nightly build time from 40 minutes to 6 minutes"),
                      "the captured outcome text must appear verbatim as grounding")
    }

    func testDigestIncludesTechnologies() {
        let digest = WorkHighlightsGenerator().buildTaskContext(
            entry: workEntry(), kcs: [enrichedCard()])
        XCTAssertTrue(digest.contains("**Technologies:**"),
                      "the technologies label must appear when the card has a stack")
        XCTAssertTrue(digest.contains("Rust, gRPC, Postgres"),
                      "technologies must join comma-space to ground stack claims")
    }

    func testDigestStillCarriesFactsAndBullets() {
        // Regression guard: threading the new fields must not displace the
        // facts/suggestedBullets that already reached the digest.
        let digest = WorkHighlightsGenerator().buildTaskContext(
            entry: workEntry(), kcs: [enrichedCard()])
        XCTAssertTrue(digest.contains("Led firmware for the sensor array"))
        XCTAssertTrue(digest.contains("Built the telemetry ingestion pipeline"))
    }

    func testDigestOmitsEnrichmentSectionsWhenAbsent() {
        // A card with no outcomes/technologies must not emit empty headings.
        let bare = KnowledgeCard(title: "Bare", narrative: "n", organization: "Acme")
        let digest = WorkHighlightsGenerator().buildTaskContext(entry: workEntry(), kcs: [bare])
        XCTAssertFalse(digest.contains("**Documented Outcomes:**"),
                       "no outcomes -> no outcomes heading")
        XCTAssertFalse(digest.contains("**Technologies:**"),
                       "no technologies -> no technologies heading")
    }

    // MARK: - Guardrail survives alongside the enrichment

    func testHighlightGuidelinesRetainForbiddenBlock() {
        let guidelines = WorkHighlightsGenerator().highlightGuidelines(
            maxHighlights: 4, bulletConstraint: "")
        XCTAssertTrue(guidelines.contains("## FORBIDDEN"),
                      "the FORBIDDEN block must remain in the highlights prompt")
        XCTAssertTrue(guidelines.contains("Inventing metrics, percentages, or numbers not explicitly stated in KCs"),
                      "the fabricated-metrics ban must remain")
        XCTAssertTrue(guidelines.contains("[Verb] [thing] resulting in [X]% improvement"),
                      "the metric-formula ban must remain intact")
    }

    func testHighlightGuidelinesReflectBulletCap() {
        let guidelines = WorkHighlightsGenerator().highlightGuidelines(
            maxHighlights: 3, bulletConstraint: "CONSTRAINT-MARKER")
        XCTAssertTrue(guidelines.contains("Generate up to 3 bullet points"),
                      "the per-run bullet cap must be threaded through")
        XCTAssertTrue(guidelines.contains("CONSTRAINT-MARKER"),
                      "the bullet-constraint text must be injected")
    }
}
