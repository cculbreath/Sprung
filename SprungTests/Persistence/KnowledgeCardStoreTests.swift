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
        pending: Bool = false
    ) -> KnowledgeCard {
        KnowledgeCard(
            title: title,
            narrative: "Drove the platform rewrite end to end.",
            cardType: type,
            isFromOnboarding: fromOnboarding,
            isPending: pending
        )
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

    // MARK: - Pending-card ghost contract (app-audit-2026-07-06 §3.1)
    //
    // Cards onboarding persisted with isPending=true survive an abandoned
    // interview. The pinned contract: they stay in `knowledgeCards` (the full
    // collection browsers show, badged as pending), they are EXCLUDED from
    // `approvedCards` (the ONLY collection operational consumers — SGM, cover
    // letters, revision, preprocessing, Discovery, scout — may read), they are
    // approvable individually from the References browser (per-card Approve →
    // approveCards(cardIds:)), and approving one card must not touch the others.

    func testPendingCardsVisibleInBrowsersButExcludedFromOps() throws {
        let store = KnowledgeCardStore(context: context)
        store.addAll([
            makeCard(title: "Ghost", fromOnboarding: true, pending: true),
            makeCard(title: "Approved", fromOnboarding: false, pending: false)
        ])

        // Pending cards stay visible/approvable in browsers…
        XCTAssertEqual(store.knowledgeCards.count, 2)
        XCTAssertEqual(store.pendingCards.map(\.title), ["Ghost"])
        // …but never reach operations until approved.
        XCTAssertEqual(store.approvedCards.map(\.title), ["Approved"])
    }

    func testApproveSingleCardLeavesOthersPending() throws {
        let store = KnowledgeCardStore(context: context)
        let first = makeCard(title: "ApproveMe", fromOnboarding: true, pending: true)
        let second = makeCard(title: "StillPending", fromOnboarding: true, pending: true)
        store.addAll([first, second])

        store.approveCards(cardIds: [first.id])

        XCTAssertFalse(first.isPending)
        XCTAssertTrue(second.isPending)
        XCTAssertEqual(store.pendingCards.map(\.title), ["StillPending"])
        XCTAssertEqual(try fetchAll(KnowledgeCard.self).filter { $0.isPending }.count, 1)
    }

    func testApproveWithUnknownIdIsANoOp() throws {
        let store = KnowledgeCardStore(context: context)
        store.add(makeCard(title: "Pending", fromOnboarding: true, pending: true))

        store.approveCards(cardIds: [UUID()])

        XCTAssertEqual(store.pendingCards.count, 1)
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

    // MARK: - Observation (the EntityStore stale-UI fix)

    /// Reading the fetched collection must register a `changeVersion` dependency
    /// (via EntityStore.fetchAll) that an insert invalidates — otherwise a SwiftUI
    /// view listing cards would not re-render when one is added/deleted.
    /// KnowledgeCardStore previously had no such counter; this guards the fix.
    func testReadingCollectionRegistersObservationDependencyOnInsert() {
        let store = KnowledgeCardStore(context: context)
        var changed = false
        withObservationTracking {
            _ = store.knowledgeCards
        } onChange: {
            changed = true
        }
        store.add(makeCard())
        XCTAssertTrue(changed, "fetchAll() must touch changeVersion so a mutation re-renders the view")
    }

    func testDomainBulkDeleteAlsoTriggersObservation() {
        let store = KnowledgeCardStore(context: context)
        store.addAll([makeCard(title: "P", fromOnboarding: true, pending: true)])
        var changed = false
        withObservationTracking {
            _ = store.knowledgeCards
        } onChange: {
            changed = true
        }
        store.deletePendingCards()  // routes through EntityStore.deleteAll → bumps
        XCTAssertTrue(changed, "domain bulk-deletes must also invalidate the collection dependency")
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

    // Pending-skill ghost contract (app-audit-2026-07-06 §3.1): skills left
    // pending by an abandoned interview stay in `skills` (the full collection)
    // and are cleared wholesale by the browser's Approve Pending action
    // (approveSkills with no ids); a targeted approval must not touch others.

    func testPendingSkillsRemainInFullCollectionUntilApproved() throws {
        let store = SkillStore(context: context)
        store.addAll([
            makeSkill(canonical: "Ghost", fromOnboarding: true, pending: true),
            makeSkill(canonical: "Approved", fromOnboarding: false, pending: false)
        ])
        XCTAssertEqual(store.skills.count, 2)
        XCTAssertEqual(store.pendingSkills.map(\.canonical), ["Ghost"])
    }

    func testApproveSingleSkillLeavesOthersPending() throws {
        let store = SkillStore(context: context)
        let first = makeSkill(canonical: "ApproveMe", fromOnboarding: true, pending: true)
        let second = makeSkill(canonical: "StillPending", fromOnboarding: true, pending: true)
        store.addAll([first, second])

        store.approveSkills(skillIds: [first.id])

        XCTAssertFalse(first.isPending)
        XCTAssertTrue(second.isPending)
        XCTAssertEqual(store.pendingSkills.map(\.canonical), ["StillPending"])
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
