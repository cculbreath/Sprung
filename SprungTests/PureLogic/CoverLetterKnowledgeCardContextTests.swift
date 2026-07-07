//
//  CoverLetterKnowledgeCardContextTests.swift
//  SprungTests
//
//  Pins the cover-letter BACKGROUND DOCUMENTS builder (app-audit 2026-07-06,
//  onboarding-knowledge #5, cover-letter half): verbatim excerpts — captured
//  during onboarding expressly to "preserve voice" — must reach the cover-letter
//  prompt as VOICE source material. Before the fix the KC context used only
//  `title + narrative`, so the voice-critical surface never saw the candidate's
//  own words. The builder threads up to two excerpts per card, framed as voice
//  reference (not fabrication license).
//

import XCTest
@testable import Sprung

final class CoverLetterKnowledgeCardContextTests: XCTestCase {

    private func makeCard(
        title: String,
        narrative: String,
        excerptTexts: [String]
    ) -> KnowledgeCard {
        let card = KnowledgeCard(title: title, narrative: narrative)
        card.verbatimExcerpts = excerptTexts.map { text in
            VerbatimExcerpt(
                context: "context",
                location: "Doc p.1",
                text: text,
                preservationReason: "voice"
            )
        }
        return card
    }

    func testEmptyCardsProduceEmptyContext() {
        XCTAssertEqual(CoverLetterQuery.knowledgeCardDocs(from: []), "")
    }

    func testCardWithoutExcerptsMatchesTitleNarrativeShape() {
        let card = makeCard(title: "Role", narrative: "Story.", excerptTexts: [])
        let output = CoverLetterQuery.knowledgeCardDocs(from: [card])
        // No excerpts → byte-compatible with the prior title/narrative shape.
        XCTAssertEqual(output, "Role:\nStory.\n\n")
    }

    func testVerbatimExcerptsReachContextAsVoiceMaterial() {
        let card = makeCard(
            title: "Physics Cloud",
            narrative: "Built distributed simulation.",
            excerptTexts: ["I never trusted the abstraction until I could see the memory layout."]
        )
        let output = CoverLetterQuery.knowledgeCardDocs(from: [card])
        XCTAssertTrue(output.contains("Physics Cloud:"))
        XCTAssertTrue(output.contains("Built distributed simulation."))
        XCTAssertTrue(
            output.contains("I never trusted the abstraction until I could see the memory layout."),
            "the candidate's verbatim words must reach the cover-letter KC context"
        )
        XCTAssertTrue(
            output.contains("verbatim"),
            "excerpts must be framed as voice reference so the model matches, not fabricates"
        )
    }

    func testExcerptsCappedAtTwoPerCard() {
        let card = makeCard(
            title: "Role",
            narrative: "Story.",
            excerptTexts: ["FIRST-EXCERPT", "SECOND-EXCERPT", "THIRD-EXCERPT"]
        )
        let output = CoverLetterQuery.knowledgeCardDocs(from: [card])
        XCTAssertTrue(output.contains("FIRST-EXCERPT"))
        XCTAssertTrue(output.contains("SECOND-EXCERPT"))
        XCTAssertFalse(
            output.contains("THIRD-EXCERPT"),
            "no more than two excerpts per card should reach the prompt"
        )
    }

    func testMultipleCardsAreAllIncluded() {
        let a = makeCard(title: "Alpha", narrative: "A.", excerptTexts: ["ALPHA-VOICE"])
        let b = makeCard(title: "Beta", narrative: "B.", excerptTexts: ["BETA-VOICE"])
        let output = CoverLetterQuery.knowledgeCardDocs(from: [a, b])
        XCTAssertTrue(output.contains("Alpha:"))
        XCTAssertTrue(output.contains("ALPHA-VOICE"))
        XCTAssertTrue(output.contains("Beta:"))
        XCTAssertTrue(output.contains("BETA-VOICE"))
    }
}
