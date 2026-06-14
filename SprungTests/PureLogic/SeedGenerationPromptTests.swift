//
//  SeedGenerationPromptTests.swift
//  SprungTests
//
//  Pure-logic coverage for GenerationOptions (defaults, bulletConstraintText,
//  Equatable) and PromptCacheService prompt assembly + caching. Contexts are
//  built with empty knowledge-card / skill arrays so no SwiftData model is
//  instantiated — only the string-composition and caching logic is exercised.
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
        let options = GenerationOptions(maxHighlightsPerEntry: 6, targetBulletLines: 3)
        let text = options.bulletConstraintText
        XCTAssertTrue(text.contains("at most 6 highlight bullets"),
                      "constraint text must reflect maxHighlightsPerEntry: \(text)")
        XCTAssertTrue(text.contains("3 lines"), "plural line count expected: \(text)")
    }

    func testBulletConstraintTextSingularLineLabel() {
        let options = GenerationOptions(targetBulletLines: 1)
        XCTAssertTrue(options.bulletConstraintText.contains("1 line"),
                      "targetBulletLines == 1 must render '1 line', not '1 lines'")
        XCTAssertFalse(options.bulletConstraintText.contains("1 lines"))
    }

    // MARK: - PromptCacheService.buildPrompt (pure composition)

    func testBuildPromptComposesAllParts() {
        let service = PromptCacheService(backend: .openRouter)
        let prompt = service.buildPrompt(
            preamble: "PREAMBLE",
            sectionPrompt: "SECTION",
            taskContext: "TASKCTX")
        XCTAssertTrue(prompt.hasPrefix("PREAMBLE"))
        XCTAssertTrue(prompt.contains("## Current Task"))
        XCTAssertTrue(prompt.contains("SECTION"))
        XCTAssertTrue(prompt.contains("## Context for This Task"))
        XCTAssertTrue(prompt.contains("TASKCTX"))
        // Ordering: preamble -> current task -> context.
        let pre = prompt.range(of: "PREAMBLE")!.lowerBound
        let task = prompt.range(of: "## Current Task")!.lowerBound
        let ctx = prompt.range(of: "## Context for This Task")!.lowerBound
        XCTAssertTrue(pre < task && task < ctx, "prompt sections must appear in order")
    }

    // MARK: - usesCaching

    func testUsesCachingOnlyForAnthropicBackend() {
        XCTAssertTrue(PromptCacheService(backend: .anthropic).usesCaching)
        XCTAssertFalse(PromptCacheService(backend: .openRouter).usesCaching)
        XCTAssertFalse(PromptCacheService(backend: .openAI).usesCaching)
    }

    // MARK: - buildPreamble structure + empty-section skipping

    private func makeContext(
        profile: ApplicantProfileDraft = ApplicantProfileDraft(),
        writersVoice: String = "",
        dossier: JSON? = nil
    ) -> SeedGenerationContext {
        SeedGenerationContext(
            applicantProfile: profile,
            skeletonTimeline: JSON(["experiences": []]),
            sectionConfig: SectionConfig(),
            knowledgeCards: [],
            skills: [],
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

    func testInvalidateCacheForcesRebuild() {
        let service = PromptCacheService(backend: .openRouter)
        let first = service.buildPreamble(context: makeContext())
        service.invalidateCache()
        // Rebuilds without crashing and produces the same deterministic output.
        let rebuilt = service.buildPreamble(context: makeContext())
        XCTAssertEqual(first, rebuilt)
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
}
