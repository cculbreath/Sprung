//
//  SeedGenerationContextBuilderTests.swift
//  SprungTests
//
//  Pins the card-source contract for Experience Defaults generation: the builder must
//  feed ALL knowledge cards into the generation context — both onboarding-derived cards
//  and cards the user added manually in the Knowledge Card browser (`isFromOnboarding ==
//  false`). Reverting to `onboardingCards` would silently drop manual cards and break the
//  "add a card manually" recovery path offered when no cards exist.
//

import XCTest
@testable import Sprung

@MainActor
final class SeedGenerationContextBuilderTests: InMemoryStoreCase {

    func testContextIncludesManualAndOnboardingCards() async {
        let knowledgeCardStore = KnowledgeCardStore(context: context)
        let skillStore = SkillStore(context: context)
        let experienceDefaultsStore = ExperienceDefaultsStore(context: context)

        insert(KnowledgeCard(title: "From Onboarding", isFromOnboarding: true))
        insert(KnowledgeCard(title: "Added Manually", isFromOnboarding: false))
        saveContext()

        let seedContext = await SeedGenerationContextBuilder.build(
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore,
            experienceDefaultsStore: experienceDefaultsStore,
            applicantProfileStore: nil,
            coverRefStore: nil,
            candidateDossierStore: nil,
            titleSetStore: nil
        )

        let titles = Set((seedContext?.knowledgeCards ?? []).map(\.title))
        XCTAssertEqual(
            seedContext?.knowledgeCards.count, 2,
            "Both onboarding and manually-added cards must feed Experience Defaults generation"
        )
        XCTAssertTrue(
            titles.contains("Added Manually"),
            "Manually-added (non-onboarding) cards must not be dropped from the generation context"
        )
    }
}
