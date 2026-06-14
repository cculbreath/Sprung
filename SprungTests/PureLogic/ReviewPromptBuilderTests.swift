//
//  ReviewPromptBuilderTests.swift
//  SprungTests
//
//  Pure-logic coverage for ReviewPromptBuilder: deterministic prompt assembly,
//  section ordering, optional-field handling, and the assessment/fit/change
//  builders. Every method is a pure string transform.
//

import XCTest
@testable import Sprung

final class ReviewPromptBuilderTests: XCTestCase {

    // MARK: - buildContextHeader

    func testContextHeaderBasic() {
        let header = ReviewPromptBuilder.buildContextHeader(
            jobPosition: "Engineer", companyName: "Acme")
        XCTAssertEqual(header, """
        Context:
        \(ReviewPromptBuilder.separator)
        • Applicant is applying for **Engineer** at **Acme**.
        """)
    }

    func testContextHeaderAppendsAdditionalInfoInOrder() {
        let header = ReviewPromptBuilder.buildContextHeader(
            jobPosition: "Eng", companyName: "Co",
            additionalInfo: ["• line one", "• line two"])
        let lines = header.components(separatedBy: "\n")
        XCTAssertEqual(lines.last, "• line two")
        XCTAssertEqual(lines[lines.count - 2], "• line one")
    }

    func testContextHeaderIncludeImageAppendsPlaceholder() {
        let header = ReviewPromptBuilder.buildContextHeader(
            jobPosition: "Eng", companyName: "Co", includeImage: true)
        XCTAssertTrue(header.hasSuffix("{includeImage}"),
                      "includeImage must append the {includeImage} placeholder last")
    }

    func testContextHeaderImagePlaceholderFollowsAdditionalInfo() {
        let header = ReviewPromptBuilder.buildContextHeader(
            jobPosition: "Eng", companyName: "Co",
            additionalInfo: ["• extra"], includeImage: true)
        let lines = header.components(separatedBy: "\n")
        XCTAssertEqual(lines.last, "{includeImage}")
        XCTAssertEqual(lines[lines.count - 2], "• extra")
    }

    // MARK: - buildSection

    func testSectionUnderlineMatchesTitleLength() {
        let section = ReviewPromptBuilder.buildSection(title: "Resume", placeholder: "resumeText")
        XCTAssertEqual(section, """
        Resume
        ------
        {resumeText}
        """)
        let underline = section.components(separatedBy: "\n")[1]
        XCTAssertEqual(underline.count, "Resume".count)
    }

    // MARK: - buildTask

    func testBuildTaskPrependsHeader() {
        XCTAssertEqual(ReviewPromptBuilder.buildTask(instructions: "Do X"), "Task:\nDo X")
    }

    // MARK: - buildSimplePrompt / emptyCustomPrompt

    func testSimplePromptIsIdentity() {
        XCTAssertEqual(ReviewPromptBuilder.buildSimplePrompt(instruction: "just this"), "just this")
    }

    func testEmptyCustomPromptIsEmpty() {
        XCTAssertEqual(ReviewPromptBuilder.emptyCustomPrompt(), "")
    }

    // MARK: - buildAssessmentPrompt

    func testAssessmentPromptStructureAndOrdering() {
        let prompt = ReviewPromptBuilder.buildAssessmentPrompt(
            contextHeader: "HEADER",
            sections: [(title: "A", placeholder: "a"), (title: "B", placeholder: "b")],
            taskIntro: "Please:",
            ratingLabel: "Score",
            assessmentItems: ["first thing", "second thing"],
            outputHeader: "### Out"
        )
        // Header is first.
        XCTAssertTrue(prompt.hasPrefix("HEADER\n"))
        // Both sections appear, in order, with title underlines.
        let aIdx = try? XCTUnwrap(prompt.range(of: "A\n-\n{a}"))
        let bIdx = try? XCTUnwrap(prompt.range(of: "B\n-\n{b}"))
        XCTAssertNotNil(aIdx)
        XCTAssertNotNil(bIdx)
        XCTAssertLessThan(prompt.range(of: "{a}")!.lowerBound, prompt.range(of: "{b}")!.lowerBound,
                          "sections must appear in supplied order")
        // Assessment items numbered from 1.
        XCTAssertTrue(prompt.contains("1. first thing"))
        XCTAssertTrue(prompt.contains("2. second thing"))
        // Default labels present.
        XCTAssertTrue(prompt.contains("**Strengths**"))
        XCTAssertTrue(prompt.contains("**Areas to Improve**"))
        XCTAssertTrue(prompt.contains("**Score**: [1-10]"))
        XCTAssertTrue(prompt.contains("### Out"))
    }

    func testAssessmentPromptCustomLabels() {
        let prompt = ReviewPromptBuilder.buildAssessmentPrompt(
            contextHeader: "H",
            sections: [],
            taskIntro: "T",
            strengthsLabel: "Wins",
            improvementsLabel: "Gaps",
            ratingLabel: "Fit",
            assessmentItems: [],
            outputHeader: "OUT"
        )
        XCTAssertTrue(prompt.contains("**Wins**"))
        XCTAssertTrue(prompt.contains("**Gaps**"))
        XCTAssertTrue(prompt.contains("**Fit**: [1-10]"))
        XCTAssertFalse(prompt.contains("**Strengths**"), "custom label should replace default")
    }

    func testAssessmentPromptAdditionalOutputAndClosingNote() {
        let withExtra = ReviewPromptBuilder.buildAssessmentPrompt(
            contextHeader: "H", sections: [], taskIntro: "T", ratingLabel: "R",
            assessmentItems: [], outputHeader: "OUT",
            additionalOutput: "EXTRA-OUTPUT", closingNote: "CLOSING")
        XCTAssertTrue(withExtra.contains("EXTRA-OUTPUT"))
        XCTAssertTrue(withExtra.hasSuffix("CLOSING"), "closing note is appended last")

        let withoutExtra = ReviewPromptBuilder.buildAssessmentPrompt(
            contextHeader: "H", sections: [], taskIntro: "T", ratingLabel: "R",
            assessmentItems: [], outputHeader: "OUT")
        XCTAssertFalse(withoutExtra.contains("EXTRA-OUTPUT"))
        XCTAssertFalse(withoutExtra.contains("CLOSING"))
    }

    // MARK: - buildFitAnalysisPrompt

    func testFitAnalysisPromptContainsKeyElements() {
        let prompt = ReviewPromptBuilder.buildFitAnalysisPrompt(
            jobPosition: "Engineer", companyName: "Acme")
        XCTAssertTrue(prompt.contains("**Engineer**"))
        XCTAssertTrue(prompt.contains("**Acme**"))
        XCTAssertTrue(prompt.contains("Job Description"))
        XCTAssertTrue(prompt.contains("{jobDescription}"))
        XCTAssertTrue(prompt.contains("{resumeText}"))
        XCTAssertTrue(prompt.contains("**Fit Rating**: [1-10]"))
        XCTAssertTrue(prompt.contains("**Recommendation**"))
        // Custom improvements label used by fit builder.
        XCTAssertTrue(prompt.contains("**Gaps / Weaknesses**"))
    }

    // MARK: - buildChangeSuggestionPrompt

    func testChangeSuggestionPromptAssembly() {
        let prompt = ReviewPromptBuilder.buildChangeSuggestionPrompt(
            jobPosition: "Dev", companyName: "Globex",
            sections: [(title: "Resume", placeholder: "resume")],
            additionalInfo: ["• note"],
            instructions: "Suggest changes.")
        XCTAssertTrue(prompt.contains("**Dev**"))
        XCTAssertTrue(prompt.contains("**Globex**"))
        XCTAssertTrue(prompt.contains("• note"))
        XCTAssertTrue(prompt.contains("Resume\n------\n{resume}"))
        XCTAssertTrue(prompt.contains("Task:\nSuggest changes."))
    }
}
