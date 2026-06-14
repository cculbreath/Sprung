//
//  KnowledgeCardStoreTests.swift
//  SprungTests
//
//  Phase 3: SwiftData persistence — CRUD round-trips for KnowledgeCardStore and
//  SkillStore. Both take `init(context:)` and are the simplest store family.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class KnowledgeCardStoreTests: InMemoryStoreCase {

    // MARK: - Helpers

    private func makeCard(
        title: String = "Lead Engineer",
        type: CardType = .employment,
        fromOnboarding: Bool = false,
        pending: Bool = false,
        enabledByDefault: Bool = false
    ) -> KnowledgeCard {
        KnowledgeCard(
            title: title,
            narrative: "Drove the platform rewrite end to end.",
            cardType: type,
            isFromOnboarding: fromOnboarding,
            isPending: pending
        ).withDefaultFlag(enabledByDefault)
    }

    // MARK: - KnowledgeCardStore CRUD

    func testAddAndFetchKnowledgeCardRoundTrips() throws {
        let store = KnowledgeCardStore(context: context)
        let card = makeCard(title: "Founding Engineer")
        store.add(card)

        let fetched = try fetchAll(KnowledgeCard.self)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Founding Engineer")
        XCTAssertEqual(store.knowledgeCards.count, 1)
        XCTAssertEqual(store.card(withId: card.id)?.persistentModelID, card.persistentModelID)
    }

    func testAddAllInsertsMultipleCards() throws {
        let store = KnowledgeCardStore(context: context)
        store.addAll([makeCard(title: "A"), makeCard(title: "B"), makeCard(title: "C")])

        XCTAssertEqual(store.knowledgeCards.count, 3)
        XCTAssertEqual(try fetchAll(KnowledgeCard.self).count, 3)
    }

    func testUpdatePersistsMutation() throws {
        let store = KnowledgeCardStore(context: context)
        let card = makeCard(title: "Original")
        store.add(card)

        card.title = "Renamed"
        store.update(card)

        XCTAssertEqual(store.card(withId: card.id)?.title, "Renamed")
        XCTAssertEqual(try fetchAll(KnowledgeCard.self).first?.title, "Renamed")
    }

    func testDeleteRemovesCard() throws {
        let store = KnowledgeCardStore(context: context)
        let card = makeCard()
        store.add(card)
        XCTAssertEqual(store.knowledgeCards.count, 1)

        store.delete(card)
        XCTAssertEqual(store.knowledgeCards.count, 0)
        XCTAssertEqual(try fetchAll(KnowledgeCard.self).count, 0)
    }

    func testPendingAndApprovedCollectionsPartition() throws {
        let store = KnowledgeCardStore(context: context)
        store.addAll([
            makeCard(title: "Pending1", fromOnboarding: true, pending: true),
            makeCard(title: "Pending2", fromOnboarding: true, pending: true),
            makeCard(title: "Approved", fromOnboarding: false, pending: false)
        ])

        XCTAssertEqual(store.pendingCards.count, 2)
        XCTAssertEqual(store.approvedCards.count, 1)
        XCTAssertEqual(store.onboardingCards.count, 2)
    }

    func testApproveCardsClearsPendingFlag() throws {
        let store = KnowledgeCardStore(context: context)
        store.addAll([
            makeCard(title: "P1", fromOnboarding: true, pending: true),
            makeCard(title: "P2", fromOnboarding: true, pending: true)
        ])
        XCTAssertEqual(store.pendingCards.count, 2)

        store.approveCards() // approve all
        XCTAssertEqual(store.pendingCards.count, 0)
        XCTAssertEqual(store.approvedCards.count, 2)
    }

    func testDeletePendingCardsLeavesApproved() throws {
        let store = KnowledgeCardStore(context: context)
        store.addAll([
            makeCard(title: "P", fromOnboarding: true, pending: true),
            makeCard(title: "Keep", fromOnboarding: false, pending: false)
        ])

        store.deletePendingCards()
        XCTAssertEqual(store.knowledgeCards.count, 1)
        XCTAssertEqual(store.knowledgeCards.first?.title, "Keep")
    }

    func testDefaultCardsFilter() throws {
        let store = KnowledgeCardStore(context: context)
        store.addAll([
            makeCard(title: "Default", enabledByDefault: true),
            makeCard(title: "NonDefault", enabledByDefault: false)
        ])
        XCTAssertEqual(store.defaultCards.count, 1)
        XCTAssertEqual(store.defaultCards.first?.title, "Default")
    }

    func testCardsOfTypeFilter() throws {
        let store = KnowledgeCardStore(context: context)
        store.addAll([
            makeCard(title: "Job", type: .employment),
            makeCard(title: "Proj", type: .project),
            makeCard(title: "Job2", type: .employment)
        ])
        XCTAssertEqual(store.cards(ofType: .employment).count, 2)
        XCTAssertEqual(store.cards(ofType: .project).count, 1)
    }

    func testDeleteCardsFromArtifactByEvidenceAnchor() throws {
        let store = KnowledgeCardStore(context: context)
        let withEvidence = makeCard(title: "HasEvidence")
        withEvidence.evidenceAnchors = [
            EvidenceAnchor(documentId: "artifact-123", location: "Page 1", verbatimExcerpt: nil)
        ]
        store.addAll([withEvidence, makeCard(title: "NoEvidence")])

        store.deleteCardsFromArtifact("artifact-123")
        XCTAssertEqual(store.knowledgeCards.count, 1)
        XCTAssertEqual(store.knowledgeCards.first?.title, "NoEvidence")
    }
}

// MARK: - SkillStore CRUD

@MainActor
final class SkillStoreTests: InMemoryStoreCase {

    private func makeSkill(
        canonical: String = "Swift",
        category: String = "Programming Languages",
        fromOnboarding: Bool = false,
        pending: Bool = false
    ) -> Skill {
        Skill(
            canonical: canonical,
            atsVariants: [],
            category: category,
            isFromOnboarding: fromOnboarding,
            isPending: pending
        )
    }

    func testAddAndFetchSkillRoundTrips() throws {
        let store = SkillStore(context: context)
        let skill = makeSkill(canonical: "Python")
        store.add(skill)

        XCTAssertEqual(store.skills.count, 1)
        XCTAssertEqual(try fetchAll(Skill.self).first?.canonical, "Python")
        XCTAssertEqual(store.skill(withId: skill.id)?.persistentModelID, skill.persistentModelID)
    }

    func testChangeVersionIncrementsOnMutation() throws {
        let store = SkillStore(context: context)
        let before = store.changeVersion
        store.add(makeSkill())
        XCTAssertGreaterThan(store.changeVersion, before)
    }

    func testDeleteRemovesSkill() throws {
        let store = SkillStore(context: context)
        let skill = makeSkill()
        store.add(skill)
        store.delete(skill)
        XCTAssertEqual(store.skills.count, 0)
    }

    func testSkillsByCategoryGroups() throws {
        let store = SkillStore(context: context)
        store.addAll([
            makeSkill(canonical: "Swift", category: "Programming Languages"),
            makeSkill(canonical: "Python", category: "Programming Languages"),
            makeSkill(canonical: "Figma", category: "Design & Creative")
        ])
        let grouped = store.skillsByCategory
        XCTAssertEqual(grouped["Programming Languages"]?.count, 2)
        XCTAssertEqual(grouped["Design & Creative"]?.count, 1)
    }

    func testApprovePendingSkills() throws {
        let store = SkillStore(context: context)
        store.addAll([
            makeSkill(canonical: "A", fromOnboarding: true, pending: true),
            makeSkill(canonical: "B", fromOnboarding: true, pending: true)
        ])
        XCTAssertEqual(store.pendingSkills.count, 2)
        store.approveSkills()
        XCTAssertEqual(store.pendingSkills.count, 0)
        XCTAssertEqual(store.approvedSkills.count, 2)
    }

    func testSkillsMatchingSearchesVariants() throws {
        let store = SkillStore(context: context)
        let skill = Skill(canonical: "Python", atsVariants: ["python3", "Py"], category: "Programming Languages")
        store.add(skill)
        XCTAssertEqual(store.skills(matching: "py").count, 1)
        XCTAssertEqual(store.skills(matching: "nonexistent").count, 0)
    }

    func testSkillsInCategoryFilter() throws {
        let store = SkillStore(context: context)
        store.addAll([
            makeSkill(canonical: "Swift", category: "Programming Languages"),
            makeSkill(canonical: "Figma", category: "Design & Creative")
        ])
        XCTAssertEqual(store.skills(inCategory: "Programming Languages").count, 1)
    }
}

// MARK: - Fixture sugar

private extension KnowledgeCard {
    func withDefaultFlag(_ value: Bool) -> KnowledgeCard {
        enabledByDefault = value
        return self
    }
}
