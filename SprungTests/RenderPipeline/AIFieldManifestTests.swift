//
//  AIFieldManifestTests.swift
//  SprungTests
//
//  Phase 2 — the defaultAIFields pattern resolver (ExperienceDefaultsToTree+AIFields).
//  This is the highest-value seam in the render pipeline: it is the single place that
//  translates manifest `defaultAIFields` patterns into per-node `.aiToReplace` marks,
//  fanning out across collection entries.
//
//  The resolver walks the TreeNode tree directly and never reads the manifest, so we
//  construct an ExperienceDefaultsToTree with an empty manifest and hand-build trees
//  that mirror the editor's section → entry → field shape.
//
//  Documented syntax under test:
//    section.*.attr    each entry's `attr`            (mid-path `*` fan-out)
//    section[].attr    each entry's `attr`            (mid-path `[]` fan-out, == `*`)
//    section.list[]    the `list` container itself    (trailing marker)
//    section.field     the resolved leaf
//    (missing path)    marks nothing
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class AIFieldManifestTests: InMemoryStoreCase {

    private var resume: Resume!
    private var builder: ExperienceDefaultsToTree!

    override func setUp() async throws {
        try await super.setUp()
        resume = RenderFixtures.makeResume(in: context)
        let defaults = Fixtures.makeEmptyExperienceDefaults()
        context.insert(defaults)
        builder = ExperienceDefaultsToTree(
            resume: resume,
            experienceDefaults: defaults,
            manifest: RenderFixtures.emptyManifest()
        )
    }

    // MARK: - Tree builders mirroring editor shape

    /// root → section("name") → N anonymous entries (name: "") → each with the given leaf fields.
    /// Returns (root, [entries]).
    @discardableResult
    private func makeCollection(
        section: String,
        entries: [[String: String]] // each dict = fieldName -> value
    ) -> (root: TreeNode, section: TreeNode, entries: [TreeNode]) {
        let root = RenderFixtures.makeRoot(for: resume, in: context)
        let sectionNode = RenderFixtures.addNode(to: root, name: section, status: .isNotLeaf, in: context)
        var entryNodes: [TreeNode] = []
        for fields in entries {
            let entry = RenderFixtures.addNode(to: sectionNode, name: "", status: .isNotLeaf, in: context)
            for (fieldName, value) in fields {
                RenderFixtures.addNode(to: entry, name: fieldName, value: value, status: .saved, in: context)
            }
            entryNodes.append(entry)
        }
        return (root, sectionNode, entryNodes)
    }

    private func leaf(_ name: String, in entry: TreeNode) -> TreeNode? {
        entry.orderedChildren.first { $0.name == name }
    }

    // MARK: - section.*.attr (mid-path star fan-out)

    func testStarFanOutMarksAttributePerEntry() {
        let (root, _, entries) = makeCollection(
            section: "skills",
            entries: [["name": "Swift", "level": "Expert"],
                      ["name": "Rust", "level": "Proficient"]]
        )
        builder.applyDefaultAIFields(to: root, patterns: ["skills.*.name"])

        for entry in entries {
            XCTAssertEqual(leaf("name", in: entry)?.status, .aiToReplace, "each skill's name must be marked")
            XCTAssertNotEqual(leaf("level", in: entry)?.status, .aiToReplace, "sibling attribute must NOT be marked")
        }
        // The section root is never marked — only the named attribute.
        XCTAssertEqual(root.aiStatusChildren, 2, "exactly one mark per entry")
    }

    // MARK: - section[].attr (mid-path bracket fan-out, equivalent to *)

    func testBracketFanOutEquivalentToStar() {
        let (root, _, entries) = makeCollection(
            section: "skills",
            entries: [["name": "Swift", "keywords": ""],
                      ["name": "Rust", "keywords": ""]]
        )
        // keywords container per entry
        for entry in entries {
            let kw = leaf("keywords", in: entry)
            kw?.status = .isNotLeaf
            if let kw {
                RenderFixtures.addNode(to: kw, name: "", value: "concurrency", status: .saved, in: context)
            }
        }
        builder.applyDefaultAIFields(to: root, patterns: ["skills[].keywords"])

        for entry in entries {
            XCTAssertEqual(leaf("keywords", in: entry)?.status, .aiToReplace,
                           "each skill's keywords container must be marked")
        }
        XCTAssertEqual(root.aiStatusChildren, 2)
    }

    func testWorkHighlightsFanOut() {
        let (root, _, entries) = makeCollection(
            section: "work",
            entries: [["position": "Eng", "highlights": ""],
                      ["position": "Lead", "highlights": ""]]
        )
        builder.applyDefaultAIFields(to: root, patterns: ["work[].highlights"])

        for entry in entries {
            XCTAssertEqual(leaf("highlights", in: entry)?.status, .aiToReplace)
            XCTAssertNotEqual(leaf("position", in: entry)?.status, .aiToReplace)
        }
    }

    // MARK: - Trailing marker: section.list[] marks the container itself

    func testTrailingMarkerMarksContainerNotChildren() {
        let root = RenderFixtures.makeRoot(for: resume, in: context)
        let custom = RenderFixtures.addNode(to: root, name: "custom", status: .isNotLeaf, in: context)
        let jobTitles = RenderFixtures.addNode(to: custom, name: "jobTitles", status: .isNotLeaf, in: context)
        let t1 = RenderFixtures.addNode(to: jobTitles, name: "", value: "Engineer", status: .saved, in: context)
        let t2 = RenderFixtures.addNode(to: jobTitles, name: "", value: "Developer", status: .saved, in: context)

        builder.applyDefaultAIFields(to: root, patterns: ["custom.jobTitles[]"])

        XCTAssertEqual(jobTitles.status, .aiToReplace, "trailing [] marks the container itself")
        XCTAssertNotEqual(t1.status, .aiToReplace, "children of the container are NOT individually marked")
        XCTAssertNotEqual(t2.status, .aiToReplace)
        XCTAssertEqual(root.aiStatusChildren, 1, "only the container counts")
    }

    // MARK: - Plain dotted path marks the resolved leaf

    func testPlainPathMarksLeaf() {
        let root = RenderFixtures.makeRoot(for: resume, in: context)
        let custom = RenderFixtures.addNode(to: root, name: "custom", status: .isNotLeaf, in: context)
        let objective = RenderFixtures.addNode(to: custom, name: "objective", value: "Build great software.", status: .saved, in: context)
        let other = RenderFixtures.addNode(to: custom, name: "moreInfo", value: "x", status: .saved, in: context)

        builder.applyDefaultAIFields(to: root, patterns: ["custom.objective"])

        XCTAssertEqual(objective.status, .aiToReplace)
        XCTAssertNotEqual(other.status, .aiToReplace, "sibling leaf untouched")
        XCTAssertEqual(root.aiStatusChildren, 1)
    }

    // MARK: - Missing paths mark nothing (and don't crash)

    func testMissingSectionMarksNothing() {
        let (root, _, _) = makeCollection(section: "skills", entries: [["name": "Swift"]])
        builder.applyDefaultAIFields(to: root, patterns: ["nonexistent.field"])
        XCTAssertEqual(root.aiStatusChildren, 0)
    }

    func testMissingAttributeInEntryContributesZero() {
        // Some entries have the attribute, some don't — only present ones get marked.
        let (root, _, entries) = makeCollection(
            section: "work",
            entries: [["position": "Eng", "highlights": ""],
                      ["position": "Lead"]] // no highlights
        )
        builder.applyDefaultAIFields(to: root, patterns: ["work[].highlights"])

        XCTAssertEqual(leaf("highlights", in: entries[0])?.status, .aiToReplace)
        XCTAssertNil(leaf("highlights", in: entries[1]), "second entry has no highlights node")
        XCTAssertEqual(root.aiStatusChildren, 1, "only the present attribute is marked")
    }

    // MARK: - Name matching is normalized (case/punctuation-insensitive)

    func testNameMatchingIsNormalized() {
        let root = RenderFixtures.makeRoot(for: resume, in: context)
        let custom = RenderFixtures.addNode(to: root, name: "Custom", status: .isNotLeaf, in: context)
        let objective = RenderFixtures.addNode(to: custom, name: "Objective", value: "x", status: .saved, in: context)

        // Pattern is lowercase; node names are capitalized. findChildByName normalizes.
        builder.applyDefaultAIFields(to: root, patterns: ["custom.objective"])
        XCTAssertEqual(objective.status, .aiToReplace, "matching must be case-insensitive")
    }

    // MARK: - Multiple patterns accumulate

    func testMultiplePatternsAccumulate() {
        let (root, _, entries) = makeCollection(
            section: "skills",
            entries: [["name": "Swift", "level": "Expert"]]
        )
        // Add a custom section with objective alongside skills.
        let custom = RenderFixtures.addNode(to: root, name: "custom", status: .isNotLeaf, in: context)
        let objective = RenderFixtures.addNode(to: custom, name: "objective", value: "x", status: .saved, in: context)

        builder.applyDefaultAIFields(to: root, patterns: ["skills.*.name", "custom.objective"])

        XCTAssertEqual(leaf("name", in: entries[0])?.status, .aiToReplace)
        XCTAssertEqual(objective.status, .aiToReplace)
        XCTAssertEqual(root.aiStatusChildren, 2)
    }
}
