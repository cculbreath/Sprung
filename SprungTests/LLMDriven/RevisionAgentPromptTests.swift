//
//  RevisionAgentPromptTests.swift
//  SprungTests
//
//  Phase 5 (LLM-driven subsystem tests — pure units).
//
//  ResumeRevisionAgentPrompts builds the revision agent's static, cacheable
//  prompt prefix from scalar inputs — a pure string transform with no LLM, no
//  deps. The conditional branches are load-bearing for the cache-stability and
//  tool-availability invariants (e.g. every `ask_user` reference must be scrubbed
//  when the tool is unregistered), so we assert the presence/absence of each
//  conditional block for given inputs.
//

import XCTest
@testable import Sprung

final class RevisionAgentPromptTests: XCTestCase {

    private func systemPrompt(
        targetPageCount: Int? = nil,
        hasTitleSets: Bool = false,
        writersVoice: String = "",
        avoidPhrases: [String] = [],
        strategicGuidance: String = "",
        askUserEnabled: Bool = false
    ) -> String {
        ResumeRevisionAgentPrompts.systemPrompt(
            targetPageCount: targetPageCount,
            hasTitleSets: hasTitleSets,
            writersVoice: writersVoice,
            avoidPhrases: avoidPhrases,
            strategicGuidance: strategicGuidance,
            askUserEnabled: askUserEnabled)
    }

    // MARK: - Stable base content

    func testSystemPromptAlwaysHasCoreSections() {
        let prompt = systemPrompt()
        XCTAssertTrue(prompt.contains("expert resume editor"))
        XCTAssertTrue(prompt.contains("## Your Workspace"))
        XCTAssertTrue(prompt.contains("## Proposing Changes — Granularity"))
        XCTAssertTrue(prompt.contains("## Evidence Per Change"))
        XCTAssertTrue(prompt.contains("## Tool Usage"))
    }

    // MARK: - ask_user gating (tool-availability invariant)

    func testAskUserReferencesPresentOnlyWhenEnabled() {
        let enabled = systemPrompt(askUserEnabled: true)
        XCTAssertTrue(enabled.contains("`ask_user`"), "ask_user must be referenced when enabled")
        XCTAssertTrue(enabled.contains("## Clarification First"),
                      "the Clarification First section appears only with ask_user enabled")
    }

    func testAskUserReferencesScrubbedWhenDisabled() {
        let disabled = systemPrompt(askUserEnabled: false)
        XCTAssertFalse(disabled.contains("ask_user"),
                       "every ask_user reference must be scrubbed when the tool is unregistered")
        XCTAssertFalse(disabled.contains("## Clarification First"),
                       "no Clarification First section without ask_user")
        // The locked-content guidance falls back to "mention them in your summary".
        XCTAssertTrue(disabled.contains("mention them in your summary"),
                      "disabled path uses the summary-mention fallback for locked content")
    }

    // MARK: - Page target

    func testPageTargetOmittedWhenNil() {
        XCTAssertFalse(systemPrompt(targetPageCount: nil).contains("## Page Target"))
    }

    func testPageTargetPluralizesPages() {
        let single = systemPrompt(targetPageCount: 1)
        XCTAssertTrue(single.contains("## Page Target"))
        XCTAssertTrue(single.contains("within 1 page."), "page count of 1 is singular")
        XCTAssertFalse(single.contains("within 1 pages"))

        let multi = systemPrompt(targetPageCount: 2)
        XCTAssertTrue(multi.contains("within 2 pages."), "page count > 1 is plural")
    }

    // MARK: - Title sets

    func testJobTitlesSectionGatedOnHasTitleSets() {
        XCTAssertFalse(systemPrompt(hasTitleSets: false).contains("## Job Titles"))
        let withSets = systemPrompt(hasTitleSets: true)
        XCTAssertTrue(withSets.contains("## Job Titles"))
        XCTAssertTrue(withSets.contains("title_sets.txt"))
    }

    // MARK: - Avoid phrases

    func testAvoidPhrasesSectionOmittedWhenEmpty() {
        XCTAssertFalse(systemPrompt(avoidPhrases: []).contains("PHRASES TO NEVER USE"))
    }

    func testAvoidPhrasesRenderedAsQuotedBullets() {
        let prompt = systemPrompt(avoidPhrases: ["synergy", "leverage"])
        XCTAssertTrue(prompt.contains("PHRASES TO NEVER USE"))
        XCTAssertTrue(prompt.contains("- \"synergy\""))
        XCTAssertTrue(prompt.contains("- \"leverage\""))
    }

    // MARK: - Writer's voice

    func testWritersVoiceInjectedWhenPresent() {
        let prompt = systemPrompt(writersVoice: "WRITER-VOICE-MARKER-7")
        XCTAssertTrue(prompt.contains("WRITER-VOICE-MARKER-7"))
    }

    func testWritersVoiceAbsentWhenEmpty() {
        // An empty voice must not inject a dangling marker; the surrounding
        // sections still render.
        let prompt = systemPrompt(writersVoice: "")
        XCTAssertTrue(prompt.contains("## Visual Balance & Layout"),
                      "the section following the optional voice block still renders")
    }

    // MARK: - Strategic positioning (candidate dossier)

    func testStrategicGuidanceOmittedWhenEmpty() {
        let prompt = systemPrompt(strategicGuidance: "")
        XCTAssertFalse(prompt.contains("## Strategic Positioning"),
                       "no strategic positioning section without dossier guidance")
    }

    func testStrategicGuidanceInjectedWhenPresent() {
        let prompt = systemPrompt(strategicGuidance: "STRATEGY-MARKER-42")
        XCTAssertTrue(prompt.contains("## Strategic Positioning"))
        XCTAssertTrue(prompt.contains("STRATEGY-MARKER-42"))
        // Positioning is direction, not new facts — the evidence rule must remain.
        XCTAssertTrue(prompt.contains("must still trace to a knowledge card"),
                      "the strategic block must reassert the evidence-grounding rule")
    }

    // MARK: - Page overflow skill

    func testPageOverflowSectionAlwaysPresent() {
        let prompt = systemPrompt()
        XCTAssertTrue(prompt.contains("## Page Overflow"),
                      "the page-overflow skill guidance is unconditional")
        XCTAssertTrue(prompt.contains("`check_page_count`"),
                      "overflow fixes verify via the check_page_count tool")
        XCTAssertTrue(prompt.contains("weakest-relevance"),
                      "cuts target the weakest-relevance content for the job")
        XCTAssertTrue(prompt.contains("Every cut goes through review"),
                      "cuts flow through propose_changes — never silent")
        XCTAssertTrue(prompt.contains("Formatting is a last resort"),
                      "content cuts are preferred over formatting tricks")
    }

    func testPageOverflowTargetClarificationGatedOnAskUser() {
        let enabled = systemPrompt(askUserEnabled: true)
        XCTAssertTrue(enabled.contains("ask for the desired page count with `ask_user`"),
                      "with ask_user available, the target length is clarified via the tool")

        let disabled = systemPrompt(askUserEnabled: false)
        XCTAssertTrue(disabled.contains("state the page count you are working toward"),
                      "without ask_user, the assumed target surfaces in the proposal summary")
        // testAskUserReferencesScrubbedWhenDisabled already pins that no
        // `ask_user` string survives in the disabled variant.
    }

    func testWorkspaceListingIncludesReadOnlyRenderInfo() {
        let prompt = systemPrompt()
        XCTAssertTrue(prompt.contains("`render_info.json`"),
                      "the seeded render metadata file is listed in the workspace")
        XCTAssertTrue(prompt.contains("The ONLY editable files are `treenodes/*.json` and `fontsizenodes.json`."),
                      "the editability convention matches exactly what the write tool enforces")
    }

    // MARK: - initialUserMessage

    func testInitialUserMessageEmbedsJobDescription() {
        let msg = ResumeRevisionAgentPrompts.initialUserMessage(
            jobDescription: "JOB-DESC-MARKER-ABC",
            jobRequirementsAvailable: false,
            writingSamplesAvailable: false)
        XCTAssertTrue(msg.contains("JOB-DESC-MARKER-ABC"), "the full job description is embedded")
        XCTAssertTrue(msg.contains("## Job Description"))
        XCTAssertTrue(msg.contains("propose_changes"), "the message points the agent at propose_changes")
    }

    func testInitialUserMessageListsOnlyAvailableMaterials() {
        // Only materials the export actually wrote should be mentioned.
        let none = ResumeRevisionAgentPrompts.initialUserMessage(
            jobDescription: "x", jobRequirementsAvailable: false, writingSamplesAvailable: false)
        XCTAssertTrue(none.contains("knowledge cards overview"))
        XCTAssertTrue(none.contains("skill bank"))
        XCTAssertFalse(none.contains("job requirements"),
                       "absent job requirements must not be listed")
        XCTAssertFalse(none.contains("writing samples"),
                       "absent writing samples must not be listed")

        let all = ResumeRevisionAgentPrompts.initialUserMessage(
            jobDescription: "x", jobRequirementsAvailable: true, writingSamplesAvailable: true)
        XCTAssertTrue(all.contains("job requirements"))
        XCTAssertTrue(all.contains("writing samples"))
    }
}
