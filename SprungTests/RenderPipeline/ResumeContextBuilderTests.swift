//
//  ResumeContextBuilderTests.swift
//  SprungTests
//
//  Phase 2 — ResumeContextBuilder: the single entry point that fuses TreeNode data with
//  the ApplicantProfile into the final Mustache context. Pins:
//    - custom-field nesting under "custom"
//    - ApplicantProfile → basics.* merge and convention-based precedence
//    - summary precedence: custom.objective / tree summary win over profile.summary
//
//  The resume carries no Template, so the data builder uses the no-manifest path (pure
//  tree walk) and addTemplateFields is skipped — no Resources/manifest files required.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class ResumeContextBuilderTests: InMemoryStoreCase {

    private func makeResumeWithRoot() -> (Resume, TreeNode) {
        let resume = RenderFixtures.makeResume(in: context)
        let root = RenderFixtures.makeRoot(for: resume, in: context)
        return (resume, root)
    }

    @discardableResult
    private func add(_ name: String, to parent: TreeNode, value: String = "", status: LeafStatus = .saved) -> TreeNode {
        RenderFixtures.addNode(to: parent, name: name, value: value, status: status, in: context)
    }

    // MARK: - ApplicantProfile merge

    func testProfileMergesIntoBasics() throws {
        let (resume, _) = makeResumeWithRoot()
        let profile = Fixtures.makeApplicantProfile(
            name: "Ada Lovelace", label: "Engineer",
            email: "ada@example.com", phone: "(555) 010-0101"
        )

        let ctx = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        let basics = try XCTUnwrap(ctx["basics"] as? [String: Any])

        XCTAssertEqual(basics["name"] as? String, "Ada Lovelace")
        XCTAssertEqual(basics["label"] as? String, "Engineer")
        XCTAssertEqual(basics["email"] as? String, "ada@example.com")
        XCTAssertEqual(basics["phone"] as? String, "(555) 010-0101")
    }

    func testProfileLocationNested() throws {
        let (resume, _) = makeResumeWithRoot()
        let profile = Fixtures.makeApplicantProfile(city: "London", state: "England", countryCode: "GB")

        let ctx = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        let basics = try XCTUnwrap(ctx["basics"] as? [String: Any])
        let location = try XCTUnwrap(basics["location"] as? [String: Any])

        XCTAssertEqual(location["city"] as? String, "London")
        XCTAssertEqual(location["state"] as? String, "England")
        XCTAssertEqual(location["region"] as? String, "England", "state aliases to region")
        XCTAssertEqual(location["countryCode"] as? String, "GB")
    }

    func testWebsiteMapsToBothKeys() throws {
        let (resume, _) = makeResumeWithRoot()
        let profile = Fixtures.makeApplicantProfile()

        let ctx = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        let basics = try XCTUnwrap(ctx["basics"] as? [String: Any])
        XCTAssertEqual(basics["website"] as? String, "example.com")
        XCTAssertEqual(basics["url"] as? String, "example.com")
    }

    // MARK: - Summary precedence

    func testTreeSummaryWinsOverProfileSummary() throws {
        let (resume, root) = makeResumeWithRoot()
        add("summary", to: root, value: "Job-specific summary from the tree.")
        let profile = Fixtures.makeApplicantProfile() // its summary differs

        let ctx = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        let basics = try XCTUnwrap(ctx["basics"] as? [String: Any])
        XCTAssertEqual(basics["summary"] as? String, "Job-specific summary from the tree.",
                       "tree summary must override profile.summary")
    }

    func testCustomObjectiveSuppressesProfileSummary() throws {
        let (resume, root) = makeResumeWithRoot()
        let custom = add("custom", to: root, status: .isNotLeaf)
        add("objective", to: custom, value: "Targeted objective.")
        let profile = Fixtures.makeApplicantProfile()

        let ctx = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        let basics = try XCTUnwrap(ctx["basics"] as? [String: Any])
        // With a job-specific objective present, profile.summary is excluded and there is
        // no tree `summary` section to fill basics.summary.
        XCTAssertNil(basics["summary"], "custom.objective must suppress profile.summary in basics")
    }

    func testProfileSummaryUsedWhenNoJobSpecificSummary() throws {
        let (resume, _) = makeResumeWithRoot()
        let profile = Fixtures.makeApplicantProfile()

        let ctx = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        let basics = try XCTUnwrap(ctx["basics"] as? [String: Any])
        XCTAssertEqual(basics["summary"] as? String,
                       "Pioneering engineer focused on correctness and clarity.",
                       "profile.summary fills basics.summary when no tree/objective summary exists")
    }

    // MARK: - Custom-field nesting

    func testCustomSectionPreservedUnderCustomKey() throws {
        let (resume, root) = makeResumeWithRoot()
        let custom = add("custom", to: root, status: .isNotLeaf)
        add("objective", to: custom, value: "An objective.")
        add("moreInfo", to: custom, value: "Extra detail.")
        let profile = Fixtures.makeApplicantProfile()

        let ctx = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        let customDict = try XCTUnwrap(ctx["custom"] as? [String: Any])
        XCTAssertEqual(customDict["objective"] as? String, "An objective.")
        XCTAssertEqual(customDict["moreInfo"] as? String, "Extra detail.")
    }

    func testNonStandardTopLevelKeyNestedUnderCustom() throws {
        let (resume, root) = makeResumeWithRoot()
        // A non-standard section name at root level should be folded under "custom".
        add("jobTitles", to: root, value: "Engineer")
        let profile = Fixtures.makeApplicantProfile()

        let ctx = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        XCTAssertNil(ctx["jobTitles"], "non-standard keys must not stay at root")
        let customDict = try XCTUnwrap(ctx["custom"] as? [String: Any])
        XCTAssertEqual(customDict["jobTitles"] as? String, "Engineer")
    }

    func testStandardSectionStaysAtRoot() throws {
        let (resume, root) = makeResumeWithRoot()
        // "skills" is a standard section key — must remain top-level, not nested under custom.
        let skills = add("skills", to: root, status: .isNotLeaf)
        let entry = add("", to: skills, status: .isNotLeaf)
        add("name", to: entry, value: "Swift")
        let profile = Fixtures.makeApplicantProfile()

        let ctx = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        XCTAssertNotNil(ctx["skills"], "standard sections stay at root level")
        if let customDict = ctx["custom"] as? [String: Any] {
            XCTAssertNil(customDict["skills"], "standard section must not be folded under custom")
        }
    }

    // MARK: - Augmentor derived fields flow through

    func testAugmentorDerivedFieldsPresent() throws {
        let (resume, _) = makeResumeWithRoot()
        let profile = Fixtures.makeApplicantProfile(name: "Ada Lovelace")

        let ctx = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        let basics = try XCTUnwrap(ctx["basics"] as? [String: Any])
        // HandlebarsContextAugmentor runs last and derives capitalName + contact flags.
        XCTAssertEqual(basics["capitalName"] as? String, "ADA LOVELACE")
        XCTAssertEqual(ctx["emailBool"] as? Bool, true)
    }
}
