//
//  CardEnrichmentSchemaTests.swift
//  SprungTests
//
//  The fact-extraction schema grades `evidence_quality` so the enrichment pass
//  populates KnowledgeCard.evidenceQuality for every enriched card — the field
//  was previously nil for nearly all cards, so the revision export's
//  "Evidence Quality" line never rendered. Grading it here (as a required,
//  enum-constrained field) is what makes that read live. The conditional write
//  in CardEnrichmentService keeps the document-analysis fabrication-guard
//  downgrade authoritative; this test pins the request-build half.
//

import XCTest
@testable import Sprung

final class CardEnrichmentSchemaTests: XCTestCase {

    private var properties: [String: Any] {
        CardEnrichmentService.factExtractionSchema["properties"] as? [String: Any] ?? [:]
    }

    func testSchemaGradesEvidenceQuality() {
        XCTAssertNotNil(
            properties["evidence_quality"],
            "fact-extraction schema must ask the model to grade evidence_quality"
        )
    }

    func testEvidenceQualityIsRequired() {
        let required = Set(CardEnrichmentService.factExtractionSchema["required"] as? [String] ?? [])
        XCTAssertTrue(
            required.contains("evidence_quality"),
            "evidence_quality must be required so every enriched card gets a baseline grade"
        )
    }

    func testEvidenceQualityEnumIsTheThreeGrades() {
        let field = properties["evidence_quality"] as? [String: Any]
        XCTAssertEqual(field?["type"] as? String, "string")
        let values = Set(field?["enum"] as? [String] ?? [])
        XCTAssertEqual(
            values, ["strong", "moderate", "weak"],
            "grades must match the KnowledgeCard.evidenceQuality vocabulary read by RevisionMaterialExporter"
        )
    }
}
