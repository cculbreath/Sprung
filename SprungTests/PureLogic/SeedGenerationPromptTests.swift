//
//  SeedGenerationPromptTests.swift
//  SprungTests
//
//  Pure-logic coverage for GenerationOptions (defaults, bulletConstraintText,
//  Equatable) and PromptCacheService prompt assembly + caching. KnowledgeCard
//  and Skill @Model instances are constructed standalone (never inserted into
//  a container) — only the string-composition and caching logic is exercised.
//
//  Preamble contract (pinned below): the cached role preamble includes EVERY
//  knowledge card and EVERY skill (no silent truncation), its bytes are
//  deterministic for a given input set regardless of store fetch order (it is
//  a prompt-cache prefix), and the memoization key covers content — not just
//  counts — so editing a card mid-session can never reuse a stale digest.
//
//  NOTE: GenerationOptions.load()/save() hit UserDefaults.standard directly,
//  so they are NOT exercised here (would mutate the shared domain).
//

import XCTest
import SwiftyJSON
@testable import Sprung

@MainActor
final class SeedGenerationPromptTests: XCTestCase {

    // MARK: - GenerationOptions

    func testDefaultOptions() {
        let options = GenerationOptions()
        XCTAssertEqual(options.maxHighlightsPerEntry, 4)
        XCTAssertEqual(options.targetBulletLines, 2)
        XCTAssertEqual(options.skillCategoryCount, 5)
        XCTAssertEqual(options.maxSkillsPerCategory, 8)
    }

    func testOptionsEquatable() {
        XCTAssertEqual(GenerationOptions(), GenerationOptions())
        XCTAssertNotEqual(GenerationOptions(maxHighlightsPerEntry: 3), GenerationOptions())
    }

    func testBulletConstraintTextReflectsCounts() {
        // Since 25ce63a1 (2026-06-29) the fragment states both a bullet-count
        // cap ("at most N bullets total") and a derived hard word ceiling
        // (targetBulletLines * 16), replacing the older soft rendered-line
        // guideline wording.
        let options = GenerationOptions(maxHighlightsPerEntry: 6, targetBulletLines: 3)
        let text = options.bulletConstraintText
        XCTAssertTrue(text.contains("at most 6 bullets total"),
                      "constraint text must reflect maxHighlightsPerEntry: \(text)")
        XCTAssertTrue(text.contains("3 lines"), "plural line count expected: \(text)")
        XCTAssertTrue(text.contains("at most 48 words per bullet"),
                      "word ceiling must be targetBulletLines * 16: \(text)")
    }

    func testBulletConstraintTextSingularLineLabel() {
        // Since 25ce63a1, targetBulletLines == 1 renders the word "ONE"
        // rather than the digit "1" specifically to sidestep the "1 lines"
        // pluralization mistake this test originally guarded against.
        let options = GenerationOptions(targetBulletLines: 1)
        XCTAssertTrue(options.bulletConstraintText.contains("ONE line"),
                      "targetBulletLines == 1 must render 'ONE line'")
        XCTAssertFalse(options.bulletConstraintText.contains("1 lines"))
    }

    // MARK: - buildPreamble structure + empty-section skipping

    private func makeContext(
        profile: ApplicantProfileDraft = ApplicantProfileDraft(),
        cards: [KnowledgeCard] = [],
        skills: [Skill] = [],
        writersVoice: String = "",
        dossier: JSON? = nil
    ) -> SeedGenerationContext {
        SeedGenerationContext(
            applicantProfile: profile,
            skeletonTimeline: JSON(["experiences": []]),
            sectionConfig: SectionConfig(),
            knowledgeCards: cards,
            skills: skills,
            writersVoice: writersVoice,
            voiceSummary: "",
            dossier: dossier,
            titleSets: []
        )
    }

    func testPreambleAlwaysIncludesRoleAndProfileHeaders() {
        let service = PromptCacheService(backend: .openRouter)
        let preamble = service.buildPreamble(context: makeContext())
        XCTAssertTrue(preamble.contains("# Role: Resume Content Generator"))
        XCTAssertTrue(preamble.contains("## Applicant Profile"))
        XCTAssertTrue(preamble.contains("NO FABRICATED METRICS"))
    }

    func testPreambleSkipsEmptyOptionalSections() {
        let service = PromptCacheService(backend: .openRouter)
        let preamble = service.buildPreamble(context: makeContext())
        // No cards/skills/dossier/voice -> those section headers must be absent.
        XCTAssertFalse(preamble.contains("## Knowledge Cards"),
                       "empty knowledge cards must be skipped")
        XCTAssertFalse(preamble.contains("## Skill Bank"),
                       "empty skill bank must be skipped")
        XCTAssertFalse(preamble.contains("## Strategic Insights"),
                       "absent dossier must be skipped")
    }

    func testPreambleIncludesWritersVoiceWhenPresent() {
        let service = PromptCacheService(backend: .openRouter)
        let preamble = service.buildPreamble(context: makeContext(writersVoice: "VOICE-MARKER-XYZ"))
        XCTAssertTrue(preamble.contains("VOICE-MARKER-XYZ"),
                      "non-empty writersVoice must be injected into the preamble")
    }

    func testPreambleIncludesProfileFieldsWhenPresent() {
        let service = PromptCacheService(backend: .openRouter)
        var profile = ApplicantProfileDraft()
        profile.name = "Jane Doe"
        profile.email = "jane@example.com"
        profile.city = "Austin"
        profile.state = "TX"
        let preamble = service.buildPreamble(context: makeContext(profile: profile))
        XCTAssertTrue(preamble.contains("Jane Doe"))
        XCTAssertTrue(preamble.contains("jane@example.com"))
        XCTAssertTrue(preamble.contains("Austin, TX"), "city/state should join with a comma")
    }

    func testPreambleIncludesDossierSectionWhenPresent() {
        let service = PromptCacheService(backend: .openRouter)
        let dossier = JSON(["strengthsToEmphasize": "DOSSIER-STRENGTH-MARKER"])
        let preamble = service.buildPreamble(context: makeContext(dossier: dossier))
        XCTAssertTrue(preamble.contains("## Strategic Insights"))
        XCTAssertTrue(preamble.contains("DOSSIER-STRENGTH-MARKER"))
    }

    // MARK: - Preamble caching (hash-based)

    func testPreambleCachedForIdenticalContext() {
        let service = PromptCacheService(backend: .openRouter)
        let ctx = makeContext()
        let first = service.buildPreamble(context: ctx)
        let second = service.buildPreamble(context: ctx)
        XCTAssertEqual(first, second, "identical context must yield identical preamble")
    }

    func testPreambleChangesWhenProfileChanges() {
        let service = PromptCacheService(backend: .openRouter)
        var profileA = ApplicantProfileDraft(); profileA.name = "Alice Aaa"
        var profileB = ApplicantProfileDraft(); profileB.name = "Bob Bbb"
        let a = service.buildPreamble(context: makeContext(profile: profileA))
        let b = service.buildPreamble(context: makeContext(profile: profileB))
        XCTAssertNotEqual(a, b, "a different applicant name must invalidate the cached preamble")
        XCTAssertTrue(b.contains("Bob Bbb"))
    }

    // MARK: - Preamble completeness (no silent truncation)

    func testPreambleIncludesEveryKnowledgeCard() {
        // 25 cards previously silently truncated to prefix(20). The contract
        // is now that EVERY card appears in the evidence base.
        let cards = (1...25).map {
            KnowledgeCard(title: "Card-Title-\($0)", narrative: "narrative \($0)")
        }
        let service = PromptCacheService(backend: .openRouter)
        let preamble = service.buildPreamble(context: makeContext(cards: cards))
        for card in cards {
            XCTAssertTrue(preamble.contains("### \(card.title)"),
                          "every knowledge card must appear in the preamble: missing \(card.title)")
        }
        XCTAssertFalse(preamble.contains("more knowledge cards"),
                       "the silent-truncation trailer must be gone")
    }

    func testPreambleIncludesEverySkill() {
        // 120 skills previously silently truncated to an alphabetical
        // prefix(100) — while the prompt told the model the list was
        // exhaustive. The contract is now that EVERY skill appears.
        let skills = (1...120).map {
            Skill(canonical: String(format: "Skill-%03d", $0), category: "technical")
        }
        let service = PromptCacheService(backend: .openRouter)
        let preamble = service.buildPreamble(context: makeContext(skills: skills))
        XCTAssertTrue(preamble.contains("- Skill-001"))
        XCTAssertTrue(preamble.contains("- Skill-120"),
                      "skills past the old prefix(100) cap must be present")
        XCTAssertFalse(preamble.contains("more skills"),
                       "the silent-truncation trailer must be gone")
    }

    // MARK: - Preamble byte-stability (prompt-cache prefix)

    func testPreambleByteStableAcrossInputOrdering() {
        // Store fetch order is arbitrary; the preamble is a prompt-cache
        // prefix so one input set must always yield identical bytes.
        let cards = (1...5).map {
            KnowledgeCard(title: "Card-\($0)", narrative: "n", organization: "Org-\($0)")
        }
        let skills = (1...5).map {
            Skill(canonical: "Skill-\($0)", category: "technical")
        }
        let a = PromptCacheService(backend: .openRouter)
            .buildPreamble(context: makeContext(cards: cards, skills: skills))
        let b = PromptCacheService(backend: .openRouter)
            .buildPreamble(context: makeContext(cards: cards.reversed(), skills: skills.reversed()))
        XCTAssertEqual(a, b, "preamble bytes must not depend on store fetch order")
    }

    // MARK: - Cache key covers content, not just counts

    func testCachedPreambleInvalidatedByCardContentChange() {
        // Same card COUNT, different content: the old count-based hash reused
        // the stale digest here, so mid-session card edits never surfaced.
        let service = PromptCacheService(backend: .openRouter)
        let card = KnowledgeCard(title: "Original Card Title", narrative: "n")
        let first = service.buildPreamble(context: makeContext(cards: [card]))
        XCTAssertTrue(first.contains("Original Card Title"))

        card.title = "Edited Card Title"
        let second = service.buildPreamble(context: makeContext(cards: [card]))
        XCTAssertTrue(second.contains("Edited Card Title"),
                      "an edited card must invalidate the cached preamble")
        XCTAssertFalse(second.contains("Original Card Title"))
    }

    func testCachedPreambleInvalidatedBySkillRename() {
        let service = PromptCacheService(backend: .openRouter)
        let skill = Skill(canonical: "OldSkillName", category: "technical")
        let first = service.buildPreamble(context: makeContext(skills: [skill]))
        XCTAssertTrue(first.contains("OldSkillName"))

        skill.canonical = "NewSkillName"
        let second = service.buildPreamble(context: makeContext(skills: [skill]))
        XCTAssertTrue(second.contains("NewSkillName"),
                      "a renamed skill must invalidate the cached preamble")
        XCTAssertFalse(second.contains("OldSkillName"))
    }
}
