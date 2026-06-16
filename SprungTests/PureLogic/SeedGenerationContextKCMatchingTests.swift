//
//  SeedGenerationContextKCMatchingTests.swift
//  SprungTests
//
//  Pins the contract that relevantKCs(for:) resolves knowledge cards by the
//  org-name key used by EACH timeline-entry type. Regression guard for the bug
//  where work entries (keyed "company"/"title") matched on neither org name nor
//  title because relevantKCs only read "name"/"position" — silently dropping
//  grounding for the highest-value section.
//

import XCTest
import SwiftyJSON
@testable import Sprung

@MainActor
final class SeedGenerationContextKCMatchingTests: XCTestCase {

    private func makeContext(cards: [KnowledgeCard]) -> SeedGenerationContext {
        SeedGenerationContext(
            applicantProfile: ApplicantProfileDraft(),
            skeletonTimeline: JSON(["experiences": []]),
            sectionConfig: SectionConfig(),
            knowledgeCards: cards,
            skills: [],
            writersVoice: "",
            voiceSummary: "",
            dossier: nil,
            titleSets: []
        )
    }

    /// Work entries are keyed "company" (not "name"). The org-name branch must fire.
    func testWorkEntryMatchesKCByOrganizationName() {
        let card = KnowledgeCard(title: "Acme tenure", narrative: "Did things.", organization: "Acme Corporation")
        let context = makeContext(cards: [card])
        let workEntry = JSON([
            "experienceType": "work",
            "company": "Acme Corporation",
            "title": "Staff Engineer"
        ])
        let matched = context.relevantKCs(for: workEntry)
        XCTAssertEqual(matched.count, 1, "work entry must resolve its KC by the 'company' org key")
        XCTAssertEqual(matched.first?.organization, "Acme Corporation")
    }

    /// Volunteer entries are keyed "organization". The org-name branch must fire.
    func testVolunteerEntryMatchesKCByOrganizationName() {
        let card = KnowledgeCard(title: "Red Cross", narrative: "Volunteered.", organization: "Red Cross")
        let context = makeContext(cards: [card])
        let volunteerEntry = JSON([
            "experienceType": "volunteer",
            "organization": "Red Cross",
            "position": "Coordinator"
        ])
        XCTAssertEqual(context.relevantKCs(for: volunteerEntry).count, 1,
                       "volunteer entry must resolve its KC by the 'organization' key")
    }

    /// Education entries are keyed "institution". The org-name branch must fire.
    func testEducationEntryMatchesKCByInstitutionName() {
        let card = KnowledgeCard(title: "MIT", narrative: "Studied.", organization: "MIT")
        let context = makeContext(cards: [card])
        let eduEntry = JSON([
            "experienceType": "education",
            "institution": "MIT"
        ])
        XCTAssertEqual(context.relevantKCs(for: eduEntry).count, 1,
                       "education entry must resolve its KC by the 'institution' key")
    }

    /// A KC whose org does not appear in the entry must NOT match (no over-matching).
    func testUnrelatedKCDoesNotMatchWorkEntry() {
        let card = KnowledgeCard(title: "Other", narrative: "Unrelated.", organization: "Globex")
        let context = makeContext(cards: [card])
        let workEntry = JSON([
            "experienceType": "work",
            "company": "Acme Corporation",
            "title": "Staff Engineer"
        ])
        XCTAssertTrue(context.relevantKCs(for: workEntry).isEmpty,
                      "a KC for an unrelated org must not match a work entry")
    }
}
