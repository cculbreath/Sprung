//
//  JSONBlobRoundTripTests.swift
//  SprungTests
//
//  Phase 3: SwiftData persistence — JSON-blob accessors on @Model types must survive
//  a save/fetch cycle through a real ModelContext (not just in-memory get/set).
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class JSONBlobRoundTripTests: InMemoryStoreCase {

    // MARK: - KnowledgeCard JSON fields

    func testKnowledgeCardComplexFieldsRoundTripThroughContext() throws {
        let card = KnowledgeCard(title: "Engineer", narrative: "Built things.", cardType: .employment)
        card.evidenceAnchors = [
            EvidenceAnchor(documentId: "doc-1", location: "Pages 1-2", verbatimExcerpt: "led the rewrite")
        ]
        card.extractable = ExtractableMetadata(
            domains: ["distributed systems"],
            scale: ["10M req/s"],
            keywords: ["Swift", "Kafka"]
        )
        card.suggestedBullets = ["Shipped X", "Scaled Y"]
        card.technologies = ["Swift", "Postgres"]
        card.outcomes = ["Cut latency 40%"]
        insert(card)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(KnowledgeCard.self).first)
        XCTAssertEqual(fetched.evidenceAnchors.count, 1)
        XCTAssertEqual(fetched.evidenceAnchors.first?.documentId, "doc-1")
        XCTAssertEqual(fetched.extractable.domains, ["distributed systems"])
        XCTAssertEqual(fetched.extractable.keywords, ["Swift", "Kafka"])
        XCTAssertEqual(fetched.suggestedBullets, ["Shipped X", "Scaled Y"])
        XCTAssertEqual(fetched.technologies, ["Swift", "Postgres"])
        XCTAssertEqual(fetched.outcomes, ["Cut latency 40%"])
    }

    func testKnowledgeCardCardTypeComputedAccessor() throws {
        let card = KnowledgeCard(title: "Proj", narrative: "n", cardType: .project)
        insert(card)
        saveContext()
        let fetched = try XCTUnwrap(fetchAll(KnowledgeCard.self).first)
        XCTAssertEqual(fetched.cardType, .project)
        XCTAssertEqual(fetched.cardTypeRaw, CardType.project.rawValue)

        fetched.cardType = .achievement
        saveContext()
        XCTAssertEqual(try fetchAll(KnowledgeCard.self).first?.cardTypeRaw, CardType.achievement.rawValue)
    }

    func testKnowledgeCardFactsRoundTripAndGrouping() throws {
        let card = KnowledgeCard(title: "Facts", narrative: "n")
        card.facts = [
            KnowledgeCardFact(category: "impact", statement: "Reduced cost", confidence: "high", source: nil),
            KnowledgeCardFact(category: "impact", statement: "Improved uptime", confidence: nil, source: nil),
            KnowledgeCardFact(category: "scope", statement: "Team of 5", confidence: nil, source: nil)
        ]
        insert(card)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(KnowledgeCard.self).first)
        XCTAssertEqual(fetched.facts.count, 3)
        XCTAssertEqual(fetched.factsByCategory["impact"]?.count, 2)
        XCTAssertTrue(fetched.isFactBasedCard)
    }

    func testKnowledgeCardEmptyArrayClearsBackingJSON() throws {
        let card = KnowledgeCard(title: "x", narrative: "n")
        card.technologies = ["Swift"]
        XCTAssertNotNil(card.technologiesJSON)
        card.technologies = []
        XCTAssertNil(card.technologiesJSON)
    }

    // MARK: - Skill JSON fields

    func testSkillJSONFieldsRoundTrip() throws {
        let skill = Skill(
            canonical: "Swift",
            atsVariants: ["swift5", "SwiftUI"],
            category: "Programming Languages",
            evidence: [
                SkillEvidence(documentId: "d1", location: "p1", context: "shipped app", strength: .primary)
            ],
            relatedSkills: [UUID()]
        )
        insert(skill)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(Skill.self).first)
        XCTAssertEqual(fetched.atsVariants, ["swift5", "SwiftUI"])
        XCTAssertEqual(fetched.evidence.count, 1)
        XCTAssertEqual(fetched.evidence.first?.strength, .primary)
        XCTAssertEqual(fetched.relatedSkills.count, 1)
        XCTAssertEqual(fetched.allVariants, ["Swift", "swift5", "SwiftUI"])
    }

    func testSkillCategoryNormalizationPersists() throws {
        // Legacy name should normalize on construction.
        let skill = Skill(canonical: "Comms", category: "Leadership & Communication")
        insert(skill)
        saveContext()
        XCTAssertEqual(try fetchAll(Skill.self).first?.category, "Leadership & Management")
    }

    // MARK: - ApplicantProfile.profiles (SocialProfile JSON blob)

    func testApplicantProfileSocialProfilesRoundTrip() throws {
        let profile = Fixtures.makeApplicantProfile()
        profile.profiles = [
            SocialProfile(network: "GitHub", username: "ada", url: "https://github.com/ada"),
            SocialProfile(network: "LinkedIn", username: "ada-l", url: "https://linkedin.com/in/ada-l")
        ]
        insert(profile)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(ApplicantProfile.self).first)
        XCTAssertEqual(fetched.profiles.count, 2)
        XCTAssertEqual(fetched.profiles.first?.network, "GitHub")
        XCTAssertEqual(fetched.profiles.last?.url, "https://linkedin.com/in/ada-l")
    }

    func testApplicantProfileEmptySocialProfilesDefault() throws {
        let profile = Fixtures.makeApplicantProfile()
        insert(profile)
        saveContext()
        XCTAssertTrue(try XCTUnwrap(fetchAll(ApplicantProfile.self).first).profiles.isEmpty)
    }

    // MARK: - CoverLetter encoded blobs

    func testCoverLetterSelectedKnowledgeCardIdsRoundTrip() throws {
        let letter = CoverLetter(enabledRefs: [], jobApp: nil)
        letter.knowledgeCardInclusion = .selected
        letter.selectedKnowledgeCardIds = ["id-1", "id-2"]
        insert(letter)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(CoverLetter.self).first)
        XCTAssertEqual(fetched.knowledgeCardInclusion, .selected)
        XCTAssertEqual(fetched.selectedKnowledgeCardIds, ["id-1", "id-2"])
    }

    func testCoverLetterEnabledRefsRoundTrip() throws {
        let refs = [
            CoverRef(name: "Sample", content: "voice", enabledByDefault: true, type: .writingSample)
        ]
        let letter = CoverLetter(enabledRefs: refs, jobApp: nil)
        insert(letter)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(CoverLetter.self).first)
        XCTAssertEqual(fetched.enabledRefs.count, 1)
        XCTAssertEqual(fetched.enabledRefs.first?.name, "Sample")
    }

    func testCoverLetterAssessmentDataRoundTrip() throws {
        let letter = CoverLetter(enabledRefs: [], jobApp: nil)
        letter.voteCount = 3
        letter.scoreCount = 7
        letter.hasBeenAssessed = true
        insert(letter)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(CoverLetter.self).first)
        XCTAssertEqual(fetched.voteCount, 3)
        XCTAssertEqual(fetched.scoreCount, 7)
        XCTAssertTrue(fetched.hasBeenAssessed)
    }

    // MARK: - JobApp.extractedRequirements blob

    func testJobAppExtractedRequirementsRoundTrip() throws {
        let job = JobApp(jobPosition: "Engineer")
        job.extractedRequirements = ExtractedRequirements(
            mustHave: ["Swift"],
            strongSignal: ["Concurrency"],
            preferred: ["GraphQL"],
            cultural: ["Collaborative"],
            atsKeywords: ["swift", "ios"],
            extractedAt: Date(),
            extractionModel: "test-model",
            matchedSkillIds: ["skill-1"]
        )
        insert(job)
        saveContext()

        let fetched = try XCTUnwrap(fetchAll(JobApp.self).first)
        let reqs = try XCTUnwrap(fetched.extractedRequirements)
        XCTAssertEqual(reqs.mustHave, ["Swift"])
        XCTAssertEqual(reqs.atsKeywords, ["swift", "ios"])
        XCTAssertTrue(reqs.isValid)
        // `hasPreprocessingComplete` now derives from the persisted tri-state,
        // not from `extractedRequirements` presence/validity — setting the
        // blob alone (as this test does) does not itself mark the pass complete.
        XCTAssertFalse(fetched.hasPreprocessingComplete)
    }

    func testJobAppRelevantCardIdsRoundTrip() throws {
        let job = JobApp(jobPosition: "Engineer")
        job.relevantCardIds = ["card-a", "card-b"]
        insert(job)
        saveContext()
        XCTAssertEqual(try fetchAll(JobApp.self).first?.relevantCardIds, ["card-a", "card-b"])
    }

}
