//
//  GeneratorPromptAndParseTests.swift
//  SprungTests
//
//  Phase 5 (LLM-driven subsystem tests — pure units).
//
//  Seed-generator pure surface. The richest prompt-construction (buildTaskContext)
//  and the response DTOs (ObjectiveResponse / WorkHighlightsResponse) are declared
//  `private` in their generator files, so @testable cannot reach them — those are
//  exercised indirectly through executeStructuredRequest, which hits config.llmFacade
//  and is out of scope for a pure unit (see file note below). What IS reachable and
//  pure on BaseSectionGenerator:
//    - buildRegenerationContext(originalContent:feedback:) — formats rejected
//      content + user feedback into the regeneration prompt block (no LLM)
//    - voiceCueBlock(_:) — injects the analyzed voice summary, or "" when absent
//    - displayName — derived from the section key
//
//  GenerationOptions / PromptCacheService preamble composition are already covered
//  by Phase 1 (SeedGenerationPromptTests) and are not duplicated here.
//

import XCTest
import SwiftyJSON
@testable import Sprung

@MainActor
final class GeneratorPromptAndParseTests: XCTestCase {

    /// A concrete BaseSectionGenerator instance to exercise the shared helpers.
    private func generator(_ key: ExperienceSectionKey = .work) -> BaseSectionGenerator {
        BaseSectionGenerator(sectionKey: key)
    }

    private func context(voiceSummary: String = "") -> SeedGenerationContext {
        SeedGenerationContext(
            applicantProfile: ApplicantProfileDraft(),
            skeletonTimeline: JSON(["experiences": []]),
            sectionConfig: SectionConfig(),
            knowledgeCards: [],
            skills: [],
            writersVoice: "",
            voiceSummary: voiceSummary,
            dossier: nil,
            titleSets: []
        )
    }

    // MARK: - displayName from section key

    func testDefaultDisplayNameCapitalizesSectionKey() {
        XCTAssertEqual(generator(.work).displayName, "Work")
        XCTAssertEqual(generator(.skills).displayName, "Skills")
    }

    // MARK: - voiceCueBlock

    func testVoiceCueBlockEmptyWhenNoVoiceSummary() {
        let block = generator().voiceCueBlock(context(voiceSummary: ""))
        XCTAssertEqual(block, "", "no voice summary -> no voice-cue block")
    }

    func testVoiceCueBlockInjectsSummaryUnderHeader() {
        let block = generator().voiceCueBlock(context(voiceSummary: "Plainspoken; concrete; no jargon."))
        XCTAssertTrue(block.contains("## Voice Cues"), "voice cues get their own header")
        XCTAssertTrue(block.contains("Plainspoken; concrete; no jargon."),
                      "the analyzed voice summary is injected verbatim")
        XCTAssertTrue(block.contains("candidate's voice"))
    }

    // MARK: - buildRegenerationContext: objective (summary text)

    func testRegenerationContextForObjectiveWithFeedback() {
        let content = GeneratedContent(type: .objective(summary: "Old summary text."))
        let block = generator(.custom).buildRegenerationContext(
            originalContent: content, feedback: "Make it more concrete.")

        XCTAssertTrue(block.contains("## Previous Generation (REJECTED)"))
        XCTAssertTrue(block.contains("Summary: Old summary text."),
                      "the rejected objective summary is echoed back")
        XCTAssertTrue(block.contains("## User Feedback"))
        XCTAssertTrue(block.contains("Make it more concrete."), "feedback is included")
        XCTAssertTrue(block.contains("based on the user's feedback"),
                      "the with-feedback instruction branch is used")
    }

    func testRegenerationContextWithoutFeedbackUsesAlternativeInstruction() {
        let content = GeneratedContent(type: .objective(summary: "Old summary."))
        let block = generator(.custom).buildRegenerationContext(originalContent: content, feedback: nil)

        XCTAssertTrue(block.contains("rejected this content without providing specific feedback"))
        XCTAssertTrue(block.contains("significantly different alternative"),
                      "the no-feedback branch asks for a different approach")
        XCTAssertFalse(block.contains("## User Feedback\n\nMake"),
                       "no user-supplied feedback text when feedback is nil")
    }

    func testRegenerationContextWithEmptyFeedbackUsesAlternativeInstruction() {
        // An empty (non-nil) feedback string also routes to the no-feedback branch.
        let content = GeneratedContent(type: .objective(summary: "Old."))
        let block = generator(.custom).buildRegenerationContext(originalContent: content, feedback: "")
        XCTAssertTrue(block.contains("without providing specific feedback"))
    }

    // MARK: - buildRegenerationContext: work highlights (bullet list)

    func testRegenerationContextForWorkHighlightsListsBullets() {
        let content = GeneratedContent(
            type: .workHighlights(targetId: "w1", highlights: ["Built A", "Shipped B"]))
        let block = generator(.work).buildRegenerationContext(
            originalContent: content, feedback: "Quantify impact.")
        XCTAssertTrue(block.contains("following highlights were rejected"))
        XCTAssertTrue(block.contains("- Built A"))
        XCTAssertTrue(block.contains("- Shipped B"))
        XCTAssertTrue(block.contains("Quantify impact."))
    }

    // MARK: - buildRegenerationContext: skill groups

    func testRegenerationContextForSkillGroupsRendersCategories() {
        let content = GeneratedContent(type: .skillGroups([
            SkillGroup(name: "Backend", keywords: ["Swift", "Postgres"]),
            SkillGroup(name: "Infra", keywords: ["Docker"]),
        ]))
        let block = generator(.skills).buildRegenerationContext(originalContent: content, feedback: nil)
        XCTAssertTrue(block.contains("Backend: Swift, Postgres"),
                      "skill group keywords join with comma-space")
        XCTAssertTrue(block.contains("Infra: Docker"))
    }

    // MARK: - buildRegenerationContext: project (description + highlights + keywords)

    func testRegenerationContextForProjectIncludesAllParts() {
        let content = GeneratedContent(type: .projectDescription(
            targetId: "p1",
            description: "A scheduling engine.",
            highlights: ["Cut latency"],
            keywords: ["Rust", "gRPC"]))
        let block = generator(.projects).buildRegenerationContext(originalContent: content, feedback: nil)
        XCTAssertTrue(block.contains("Description: A scheduling engine."))
        XCTAssertTrue(block.contains("- Cut latency"))
        XCTAssertTrue(block.contains("Keywords: Rust, gRPC"))
    }
}
