//
//  TimelineCardEducationFieldsTests.swift
//  SprungTests
//
//  Pure-logic coverage for the education-only `degree`/`gpa` fields on the
//  onboarding timeline card. These fields must survive the full whitelist:
//  the typed struct, JSON (de)serialization, PATCH semantics, and the
//  TimelineEntryDraft adapter round-trip. The end of that pipeline is the
//  skeleton-timeline JSON that OnboardingPersistenceService.createEducationDraft
//  reads (degree -> studyType, gpa -> score), so we assert the serialized
//  payload carries both keys.
//

import XCTest
import SwiftyJSON
@testable import Sprung

final class TimelineCardEducationFieldsTests: XCTestCase {

    private func makeEducationCard() -> TimelineCard {
        TimelineCard(
            id: "edu-1",
            experienceType: .education,
            title: "Physics",
            organization: "MIT",
            start: "2014",
            end: "2019",
            degree: "Ph.D.",
            gpa: "3.9"
        )
    }

    // MARK: - JSON round-trip

    func testJSONSerializationCarriesDegreeAndGpa() {
        let card = makeEducationCard()
        let json = card.json
        XCTAssertEqual(json["degree"].stringValue, "Ph.D.")
        XCTAssertEqual(json["gpa"].stringValue, "3.9")
        // title stays the field of study (maps to EducationExperienceDraft.area)
        XCTAssertEqual(json["title"].stringValue, "Physics")
    }

    func testInitFromJSONRoundTrip() throws {
        let card = makeEducationCard()
        let restored = try XCTUnwrap(TimelineCard(json: card.json))
        XCTAssertEqual(restored, card)
        XCTAssertEqual(restored.degree, "Ph.D.")
        XCTAssertEqual(restored.gpa, "3.9")
    }

    func testInitFromFieldsReadsDegreeAndGpa() {
        var fields = JSON()
        fields["experienceType"].string = "education"
        fields["title"].string = "Computer Science"
        fields["organization"].string = "Stanford"
        fields["degree"].string = "B.S."
        fields["gpa"].string = "3.7"
        let card = TimelineCard(id: "edu-2", fields: fields)
        XCTAssertEqual(card.degree, "B.S.")
        XCTAssertEqual(card.gpa, "3.7")
    }

    func testCodableRoundTrip() throws {
        let card = makeEducationCard()
        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(TimelineCard.self, from: data)
        XCTAssertEqual(decoded, card)
    }

    // MARK: - PATCH semantics

    func testApplyingPatchUpdatesDegreeAndGpa() {
        let card = makeEducationCard()
        var patch = JSON()
        patch["degree"].string = "M.S."
        patch["gpa"].string = "4.0"
        let updated = card.applying(fields: patch)
        XCTAssertEqual(updated.degree, "M.S.")
        XCTAssertEqual(updated.gpa, "4.0")
        // Untouched fields are preserved
        XCTAssertEqual(updated.title, "Physics")
        XCTAssertEqual(updated.organization, "MIT")
    }

    func testApplyingPatchPreservesDegreeAndGpaWhenAbsent() {
        let card = makeEducationCard()
        var patch = JSON()
        patch["title"].string = "Applied Physics"
        let updated = card.applying(fields: patch)
        XCTAssertEqual(updated.title, "Applied Physics")
        // degree/gpa survive a PATCH that omits them
        XCTAssertEqual(updated.degree, "Ph.D.")
        XCTAssertEqual(updated.gpa, "3.9")
    }

    // MARK: - Adapter round-trip

    func testAdapterPreservesDegreeAndGpaBothDirections() {
        let card = makeEducationCard()
        let drafts = TimelineCardAdapter.entryDrafts(from: [card])
        XCTAssertEqual(drafts.first?.degree, "Ph.D.")
        XCTAssertEqual(drafts.first?.gpa, "3.9")

        let roundTripped = TimelineCardAdapter.cards(from: drafts)
        XCTAssertEqual(roundTripped.first, card)
    }

    // MARK: - Skeleton-timeline payload (what createEducationDraft consumes)

    func testSkeletonTimelineJSONExposesDegreeAndGpaForPersistence() {
        let card = makeEducationCard()
        let timeline = TimelineCardAdapter.makeTimelineJSON(cards: [card], meta: nil)
        let entry = timeline["experiences"].arrayValue[0]
        // These are exactly the keys createEducationDraft maps to studyType/score.
        XCTAssertEqual(entry["degree"].stringValue, "Ph.D.")
        XCTAssertEqual(entry["gpa"].stringValue, "3.9")
        XCTAssertEqual(entry["title"].stringValue, "Physics")
    }
}
