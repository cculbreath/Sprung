//
//  RevisionWorkspaceExportTests.swift
//  SprungTests
//
//  Phase 5 (LLM-driven subsystem tests — pure units).
//
//  ResumeRevisionWorkspaceService.exportModifiableTreeNodes is the deterministic
//  front half of the revision agent's data plane: it walks a resume's TreeNode
//  tree, finds `.aiToReplace` subtree roots, and serializes ONLY those subtrees
//  to per-section JSON files (plus a manifest). No LLM is involved — we drive it
//  against an in-memory Resume/TreeNode graph and assert the exported bytes.
//
//  We point the service at a temp `baseDirectory` (init override) so it never
//  touches Application Support, then read the written files back.
//  Also covers the service's pure static helpers (wrapText, normalizedForMatch)
//  and verifyProposedChanges' ground-truth before-preview matching.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class RevisionWorkspaceExportTests: InMemoryStoreCase {

    // MARK: - Temp-rooted service

    /// A service whose workspace lives under a unique temp dir, with the
    /// directory scaffolding (createWorkspace) already done. Caller removes
    /// the temp root in a defer.
    private func makeService() throws -> (service: ResumeRevisionWorkspaceService, tempRoot: URL) {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SprungRevTest-\(UUID().uuidString)", isDirectory: true)
        let service = ResumeRevisionWorkspaceService(baseDirectory: tempRoot)
        _ = try service.createWorkspace()
        return (service, tempRoot)
    }

    /// Read back the JSON array a section was exported to.
    private func readSectionNodes(tempRoot: URL, slug: String) throws -> [[String: Any]] {
        // createWorkspace makes a single <UUID>/ session dir under tempRoot,
        // plus a `snapshots-<UUID>` sibling. The session dir is the one whose
        // name does not start with "snapshots-".
        let items = try FileManager.default.contentsOfDirectory(
            at: tempRoot, includingPropertiesForKeys: [.isDirectoryKey])
        let session = try XCTUnwrap(
            items.first { url in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return isDir && !url.lastPathComponent.hasPrefix("snapshots-")
            },
            "expected a session directory")
        let file = session.appendingPathComponent("treenodes/\(slug).json")
        let data = try Data(contentsOf: file)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    // MARK: - Tree builders

    /// A resume with a root and ONE section ("skills") whose two child leaves are
    /// marked `.aiToReplace`. Returns (resume, section).
    @discardableResult
    private func makeSkillsResume(editableLeaves: Bool = true) -> Resume {
        let resume = RenderFixtures.makeResume(in: context)
        let root = RenderFixtures.makeRoot(for: resume, in: context)
        let skills = RenderFixtures.addNode(to: root, name: "skills", in: context)
        RenderFixtures.addNode(
            to: skills, name: "skill1", value: "Swift",
            status: editableLeaves ? .aiToReplace : .saved, in: context)
        RenderFixtures.addNode(
            to: skills, name: "skill2", value: "Rust",
            status: editableLeaves ? .aiToReplace : .saved, in: context)
        return resume
    }

    // MARK: - Export: editable subtrees only

    func testExportWritesOnlyEditableSubtreesAndManifest() throws {
        let (service, tempRoot) = try makeService()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let resume = makeSkillsResume(editableLeaves: true)
        let manifest = try service.exportModifiableTreeNodes(from: resume)

        // Manifest lists the one section with the editable leaves.
        XCTAssertEqual(manifest.sections.count, 1, "only the skills section has editable nodes")
        let section = try XCTUnwrap(manifest.sections.first)
        XCTAssertEqual(section.name, "skills")
        XCTAssertEqual(section.file, "treenodes/skills.json")
        XCTAssertEqual(section.nodeCount, 2, "two editable leaf roots were exported")
        XCTAssertNil(manifest.targetPageCount, "no template -> no page limit")

        // The exported file contains exactly the two editable leaves (revision dicts).
        let nodes = try readSectionNodes(tempRoot: tempRoot, slug: "skills")
        XCTAssertEqual(nodes.count, 2)
        let names = Set(nodes.compactMap { $0["name"] as? String })
        XCTAssertEqual(names, ["skill1", "skill2"])
        let values = Set(nodes.compactMap { $0["value"] as? String })
        XCTAssertEqual(values, ["Swift", "Rust"])
        // Revision dictionaries carry id/name/value/myIndex/isTitleNode/children.
        for node in nodes {
            XCTAssertNotNil(node["id"])
            XCTAssertNotNil(node["isTitleNode"])
            XCTAssertNotNil(node["children"], "revision dicts always include a children key")
        }
    }

    func testExportSkipsSectionsWithNoEditableNodes() throws {
        let (service, tempRoot) = try makeService()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // All leaves saved (none .aiToReplace) -> nothing editable -> empty manifest.
        let resume = makeSkillsResume(editableLeaves: false)
        let manifest = try service.exportModifiableTreeNodes(from: resume)
        XCTAssertTrue(manifest.sections.isEmpty,
                      "a section with no .aiToReplace nodes is not exported")
    }

    func testEditableSectionRootExportsWholeSubtree() throws {
        let (service, tempRoot) = try makeService()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Mark the SECTION node itself editable: its entire subtree becomes one
        // editable root (findEditableRoots returns the section, not the leaves).
        let resume = RenderFixtures.makeResume(in: context)
        let root = RenderFixtures.makeRoot(for: resume, in: context)
        let work = RenderFixtures.addNode(to: root, name: "work", status: .aiToReplace, in: context)
        RenderFixtures.addNode(to: work, name: "highlight1", value: "Built X", status: .saved, in: context)
        RenderFixtures.addNode(to: work, name: "highlight2", value: "Built Y", status: .saved, in: context)

        let manifest = try service.exportModifiableTreeNodes(from: resume)
        let section = try XCTUnwrap(manifest.sections.first)
        XCTAssertEqual(section.nodeCount, 1, "the section is a single editable root")

        let nodes = try readSectionNodes(tempRoot: tempRoot, slug: "work")
        XCTAssertEqual(nodes.count, 1)
        let workNode = nodes[0]
        XCTAssertEqual(workNode["name"] as? String, "work")
        let children = try XCTUnwrap(workNode["children"] as? [[String: Any]])
        XCTAssertEqual(children.count, 2, "the whole subtree is serialized under the editable root")
    }

    func testExcludedFromGroupChildIsOmittedFromExport() throws {
        let (service, tempRoot) = try makeService()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Section root is editable; one child is opted out via .excludedFromGroup.
        let resume = RenderFixtures.makeResume(in: context)
        let root = RenderFixtures.makeRoot(for: resume, in: context)
        let work = RenderFixtures.addNode(to: root, name: "work", status: .aiToReplace, in: context)
        RenderFixtures.addNode(to: work, name: "keep", value: "kept bullet", status: .saved, in: context)
        RenderFixtures.addNode(to: work, name: "drop", value: "excluded bullet",
                               status: .excludedFromGroup, in: context)

        _ = try service.exportModifiableTreeNodes(from: resume)
        let nodes = try readSectionNodes(tempRoot: tempRoot, slug: "work")
        let children = try XCTUnwrap(nodes[0]["children"] as? [[String: Any]])
        let childNames = Set(children.compactMap { $0["name"] as? String })
        XCTAssertEqual(childNames, ["keep"],
                       ".excludedFromGroup children are filtered out of the revision export")
    }

    func testExportThrowsWhenResumeHasNoRootNode() throws {
        let (service, tempRoot) = try makeService()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let resume = RenderFixtures.makeResume(in: context)  // no rootNode
        XCTAssertThrowsError(try service.exportModifiableTreeNodes(from: resume),
                             "a resume with no root node must throw")
    }

    func testExportThrowsWhenWorkspaceNotCreated() {
        let service = ResumeRevisionWorkspaceService(
            baseDirectory: FileManager.default.temporaryDirectory)
        let resume = makeSkillsResume()
        XCTAssertThrowsError(try service.exportModifiableTreeNodes(from: resume),
                             "exporting before createWorkspace() must throw workspaceNotCreated")
    }

    // MARK: - verifyProposedChanges (ground-truth before-preview matching)

    func testVerifyProposedChangesMatchesExportedContent() throws {
        let (service, tempRoot) = try makeService()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let resume = makeSkillsResume(editableLeaves: true)  // values: Swift, Rust
        _ = try service.exportModifiableTreeNodes(from: resume)

        let changes = [
            // before_preview "Swift" matches the exported node value -> verified.
            ProposeChangesTool.ChangeDetail(
                section: "skills", type: "modify", description: "rename",
                evidence: "existing", beforePreview: "Swift", afterPreview: "Swift 6"),
            // An `add` with no before-preview -> notApplicable.
            ProposeChangesTool.ChangeDetail(
                section: "skills", type: "add", description: "add",
                evidence: "skill-bank", beforePreview: nil, afterPreview: "Go"),
            // A before-preview that is nowhere in the workspace -> mismatch.
            ProposeChangesTool.ChangeDetail(
                section: "skills", type: "modify", description: "rewrite",
                evidence: "existing", beforePreview: "COBOL", afterPreview: "COBOL 2"),
        ]

        let results = service.verifyProposedChanges(changes)
        XCTAssertEqual(results.count, 3)

        guard case .verified = results[0] else {
            return XCTFail("matching before-preview must verify; got \(results[0])")
        }
        guard case .notApplicable = results[1] else {
            return XCTFail("an add with no before-preview is notApplicable; got \(results[1])")
        }
        guard case .mismatch(let actual) = results[2] else {
            return XCTFail("an unfound before-preview must mismatch; got \(results[2])")
        }
        XCTAssertFalse(actual.isEmpty, "mismatch surfaces the actual section content for display")
    }

    // MARK: - Pure static helpers

    func testNormalizedForMatchCollapsesWhitespaceAndCase() {
        XCTAssertEqual(
            ResumeRevisionWorkspaceService.normalizedForMatch("  Hello   WORLD\tfoo "),
            "hello world foo")
        XCTAssertEqual(ResumeRevisionWorkspaceService.normalizedForMatch(""), "")
    }

    func testWrapTextWrapsLongLinesAtWordBoundaries() {
        let words = Array(repeating: "alpha", count: 10).joined(separator: " ") // 10 * 5 + 9 = 59 chars
        // width 20 forces wraps; each output line stays within the width.
        let wrapped = ResumeRevisionWorkspaceService.wrapText(words, width: 20)
        let lines = wrapped.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertGreaterThan(lines.count, 1, "a long line is wrapped onto multiple lines")
        for line in lines {
            XCTAssertLessThanOrEqual(line.count, 20, "no wrapped line exceeds the width: '\(line)'")
        }
        // No words lost: the joined tokens round-trip.
        XCTAssertEqual(wrapped.split(whereSeparator: { $0 == " " || $0 == "\n" }).count, 10)
    }

    func testWrapTextLeavesShortLinesUnchangedAndPreservesNewlines() {
        let input = "short one\nshort two"
        XCTAssertEqual(ResumeRevisionWorkspaceService.wrapText(input, width: 100), input,
                       "lines under the width are untouched and newlines are preserved")
    }
}
