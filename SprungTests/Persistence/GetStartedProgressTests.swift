//
//  GetStartedProgressTests.swift
//  SprungTests
//
//  Pins the first-run "Get Started" checklist derivation to real store state:
//  the interview row is satisfied by EITHER a Knowledge Card OR a Skill, the
//  experience row tracks `isSeedCreated`, and `allComplete` only trips when all
//  four essentials are present.
//

import XCTest
@testable import Sprung

@MainActor
final class GetStartedProgressTests: InMemoryStoreCase {

    private func makeStores() -> (KnowledgeCardStore, SkillStore, ExperienceDefaultsStore) {
        (
            KnowledgeCardStore(context: context),
            SkillStore(context: context),
            ExperienceDefaultsStore(context: context)
        )
    }

    func testFreshInstallHasNothingDone() {
        let (kc, skills, defaults) = makeStores()

        let progress = GetStartedProgress.evaluate(
            knowledgeCardStore: kc,
            skillStore: skills,
            experienceDefaultsStore: defaults,
            templateInstalled: false,
            jobCaptured: false
        )

        XCTAssertFalse(progress.interviewDone)
        XCTAssertFalse(progress.experienceDefaultsDone)
        XCTAssertFalse(progress.templateInstalled)
        XCTAssertFalse(progress.jobCaptured)
        XCTAssertFalse(progress.allComplete)
    }

    func testKnowledgeCardAloneSatisfiesInterviewRow() {
        let (kc, skills, defaults) = makeStores()
        kc.add(KnowledgeCard(title: "Built a compiler"))

        let progress = GetStartedProgress.evaluate(
            knowledgeCardStore: kc,
            skillStore: skills,
            experienceDefaultsStore: defaults,
            templateInstalled: false,
            jobCaptured: false
        )

        XCTAssertTrue(progress.interviewDone)
    }

    func testSkillAloneSatisfiesInterviewRow() {
        let (kc, skills, defaults) = makeStores()
        skills.add(Skill(canonical: "Swift", category: "Programming Languages"))

        let progress = GetStartedProgress.evaluate(
            knowledgeCardStore: kc,
            skillStore: skills,
            experienceDefaultsStore: defaults,
            templateInstalled: false,
            jobCaptured: false
        )

        XCTAssertTrue(progress.interviewDone)
    }

    func testSeedCreatedSatisfiesExperienceRow() {
        let (kc, skills, defaults) = makeStores()
        XCTAssertFalse(defaults.isSeedCreated)
        defaults.markSeedCreated()

        let progress = GetStartedProgress.evaluate(
            knowledgeCardStore: kc,
            skillStore: skills,
            experienceDefaultsStore: defaults,
            templateInstalled: false,
            jobCaptured: false
        )

        XCTAssertTrue(progress.experienceDefaultsDone)
    }

    func testAllCompleteRequiresEveryEssential() {
        let (kc, skills, defaults) = makeStores()
        kc.add(KnowledgeCard(title: "Shipped an app"))
        defaults.markSeedCreated()

        // Template + job still missing → not complete.
        let partial = GetStartedProgress.evaluate(
            knowledgeCardStore: kc,
            skillStore: skills,
            experienceDefaultsStore: defaults,
            templateInstalled: false,
            jobCaptured: true
        )
        XCTAssertFalse(partial.allComplete)

        // Everything present → complete.
        let full = GetStartedProgress.evaluate(
            knowledgeCardStore: kc,
            skillStore: skills,
            experienceDefaultsStore: defaults,
            templateInstalled: true,
            jobCaptured: true
        )
        XCTAssertTrue(full.allComplete)
    }
}
