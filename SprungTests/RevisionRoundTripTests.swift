//
//  RevisionRoundTripTests.swift
//  SprungTests
//
//  Workspace round-trip fidelity for the resume revision agent (WS2):
//  export → agent writes → import/build must never destroy or duplicate
//  user/agent work, and every anomaly must land in the import report.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class RevisionRoundTripTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    private var tempBases: [URL] = []

    override func setUpWithError() throws {
        let schema = Schema([
            Resume.self,
            ExperienceDefaults.self,
            JobApp.self,
            ResRef.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: config)
        modelContext = modelContainer.mainContext
    }

    override func tearDownWithError() throws {
        for base in tempBases {
            try? FileManager.default.removeItem(at: base)
        }
        tempBases = []
    }

    // MARK: - Helpers

    private func makeTempBase() -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("revision-roundtrip-\(UUID().uuidString)", isDirectory: true)
        tempBases.append(base)
        return base
    }

    @discardableResult
    private func addNode(
        _ name: String,
        value: String = "",
        status: LeafStatus = .saved,
        parent: TreeNode,
        resume: Resume
    ) -> TreeNode {
        parent.addChild(TreeNode(
            name: name, value: value, inEditor: true, status: status, resume: resume
        ))
    }

    /// Builds: root > work > "Tech Corp" entry > position, startDate,
    /// highlights(.aiToReplace) > 2 anonymous items.
    private func makeHighlightsEditableResume() -> (resume: Resume, highlights: TreeNode, entry: TreeNode) {
        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [])
        modelContext.insert(resume)

        let root = TreeNode(name: "root", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        modelContext.insert(root)
        resume.rootNode = root

        let work = addNode("work", status: .isNotLeaf, parent: root, resume: resume)
        let entry = addNode("Tech Corp", status: .isNotLeaf, parent: work, resume: resume)
        addNode("position", value: "Senior Dev", parent: entry, resume: resume)
        addNode("startDate", value: "2020-01", parent: entry, resume: resume)
        let highlights = addNode("highlights", status: .aiToReplace, parent: entry, resume: resume)
        addNode("", value: "Built the thing", parent: highlights, resume: resume)
        addNode("", value: "Shipped the other thing", parent: highlights, resume: resume)
        return (resume, highlights, entry)
    }

    private func loadNodeArray(_ url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        guard let nodes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(domain: "RevisionRoundTripTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Expected a JSON array of node objects at \(url.path)"
            ])
        }
        return nodes
    }

    private func writeNodeArray(_ nodes: [[String: Any]], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func nodeDict(
        id: String, name: String, value: String, myIndex: Int, children: [[String: Any]] = []
    ) -> [String: Any] {
        ["id": id, "name": name, "value": value, "myIndex": myIndex, "isTitleNode": false, "children": children]
    }

    private func findNode(named name: String, in node: TreeNode) -> TreeNode? {
        if node.name == name { return node }
        for child in node.orderedChildren {
            if let found = findNode(named: name, in: child) { return found }
        }
        return nil
    }

    private func collectValues(in node: TreeNode) -> [String] {
        var values: [String] = []
        if !node.value.isEmpty { values.append(node.value) }
        for child in node.orderedChildren {
            values.append(contentsOf: collectValues(in: child))
        }
        return values
    }

    // MARK: - B1 / RA-1: agent-added nodes survive the next session exactly once

    func testAgentAddedNodeSurvivesTwoSessions() throws {
        let (resume, _, _) = makeHighlightsEditableResume()
        let base = makeTempBase()

        // Session 1: agent inserts a new highlight in the MIDDLE of the list.
        let service1 = ResumeRevisionWorkspaceService(baseDirectory: base)
        let ws1 = try service1.createWorkspace()
        _ = try service1.exportModifiableTreeNodes(from: resume)

        let workFile = ws1.appendingPathComponent("treenodes/work.json")
        var roots = try loadNodeArray(workFile)
        XCTAssertEqual(roots.count, 1, "Expected exactly the highlights container as editable root")
        var children = roots[0]["children"] as? [[String: Any]] ?? []
        XCTAssertEqual(children.count, 2)
        children.insert(nodeDict(id: "new-1", name: "", value: "Agent added highlight", myIndex: 99), at: 1)
        roots[0]["children"] = children
        try writeNodeArray(roots, to: workFile)

        let revised1 = try service1.importRevisedTreeNodes()
        let resume2 = try service1.buildNewResume(from: resume, revisedNodes: revised1, context: modelContext)
        XCTAssertTrue(service1.lastImportReport?.isEmpty ?? true,
                      "Clean apply must produce an empty report, got: \(service1.lastImportReport?.summaryText ?? "")")

        guard let root2 = resume2.rootNode, let highlights2 = findNode(named: "highlights", in: root2) else {
            return XCTFail("Cloned resume lost its highlights container")
        }
        let values2 = highlights2.orderedChildren.map(\.value)
        XCTAssertEqual(values2, ["Built the thing", "Agent added highlight", "Shipped the other thing"],
                       "Agent-specified ordering must win")
        for child in highlights2.orderedChildren {
            XCTAssertFalse(child.id.hasPrefix("new-"),
                           "The new- sentinel namespace must never be persisted")
        }

        // Session 2: per-session dirs — creation sweeps the stale sibling.
        let service2 = ResumeRevisionWorkspaceService(baseDirectory: base)
        let ws2 = try service2.createWorkspace()
        XCTAssertNotEqual(ws1.path, ws2.path, "Each session must get its own directory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ws1.path),
                       "Stale sibling session directories must be swept at creation")

        _ = try service2.exportModifiableTreeNodes(from: resume2)
        // Accept without further edits.
        let revised2 = try service2.importRevisedTreeNodes()
        let resume3 = try service2.buildNewResume(from: resume2, revisedNodes: revised2, context: modelContext)
        XCTAssertTrue(service2.lastImportReport?.isEmpty ?? true,
                      "No-op session 2 must report nothing, got: \(service2.lastImportReport?.summaryText ?? "")")

        guard let root3 = resume3.rootNode, let highlights3 = findNode(named: "highlights", in: root3) else {
            return XCTFail("Session 2 lost the highlights container")
        }
        let values3 = highlights3.orderedChildren.map(\.value)
        XCTAssertEqual(values3, values2, "Accepted content must round-trip byte-for-byte")
        XCTAssertEqual(values3.filter { $0 == "Agent added highlight" }.count, 1,
                       "Agent-added node must survive exactly once — neither duplicated nor pruned")

        // Clones mint fresh ids — node ids are never duplicated across resumes.
        XCTAssertNotEqual(highlights2.id, highlights3.id)

        // Self-only deletion tolerates an already-missing directory.
        try service2.deleteWorkspace()
        XCTAssertFalse(FileManager.default.fileExists(atPath: ws2.path))
        do {
            try service2.deleteWorkspace()
        } catch {
            XCTFail("deleteWorkspace must tolerate an already-missing directory: \(error)")
        }
    }

    // MARK: - B2 / TB-2: omission semantics

    func testOmittedScalarUnchangedOmittedListChildAndEntryPruned() throws {
        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [])
        modelContext.insert(resume)
        let root = TreeNode(name: "root", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        modelContext.insert(root)
        resume.rootNode = root

        // Whole work section editable: agent (and pruner) get the full section.
        let work = addNode("work", status: .aiToReplace, parent: root, resume: resume)
        let entry1 = addNode("Tech Corp", status: .isNotLeaf, parent: work, resume: resume)
        addNode("position", value: "Senior Dev", parent: entry1, resume: resume)
        addNode("startDate", value: "2020-01", parent: entry1, resume: resume)
        let highlights = addNode("highlights", status: .isNotLeaf, parent: entry1, resume: resume)
        addNode("", value: "Kept highlight", parent: highlights, resume: resume)
        addNode("", value: "Dropped highlight", parent: highlights, resume: resume)
        let entry2 = addNode("Old Job", status: .isNotLeaf, parent: work, resume: resume)
        addNode("position", value: "Intern", parent: entry2, resume: resume)

        let service = ResumeRevisionWorkspaceService(baseDirectory: makeTempBase())
        let ws = try service.createWorkspace()
        _ = try service.exportModifiableTreeNodes(from: resume)

        let workFile = ws.appendingPathComponent("treenodes/work.json")
        var roots = try loadNodeArray(workFile)
        XCTAssertEqual(roots.count, 1, "Editable root should be the work section")
        var sectionChildren = roots[0]["children"] as? [[String: Any]] ?? []
        XCTAssertEqual(sectionChildren.count, 2)

        // Agent regenerates the section: drops entry 2 entirely (= delete),
        // drops startDate (scalar omission = UNCHANGED), drops one highlight
        // (list-child omission = delete), and rewrites position.
        sectionChildren.removeAll { ($0["name"] as? String) == "Old Job" }
        var entryDict = sectionChildren[0]
        var entryChildren = entryDict["children"] as? [[String: Any]] ?? []
        entryChildren.removeAll { ($0["name"] as? String) == "startDate" }
        for index in entryChildren.indices {
            if (entryChildren[index]["name"] as? String) == "position" {
                entryChildren[index]["value"] = "Principal Dev"
            }
            if (entryChildren[index]["name"] as? String) == "highlights" {
                var items = entryChildren[index]["children"] as? [[String: Any]] ?? []
                items.removeAll { ($0["value"] as? String) == "Dropped highlight" }
                entryChildren[index]["children"] = items
            }
        }
        entryDict["children"] = entryChildren
        sectionChildren[0] = entryDict
        roots[0]["children"] = sectionChildren
        try writeNodeArray(roots, to: workFile)

        let revised = try service.importRevisedTreeNodes()
        let newResume = try service.buildNewResume(from: resume, revisedNodes: revised, context: modelContext)

        guard let newRoot = newResume.rootNode,
              let newWork = findNode(named: "work", in: newRoot),
              let newEntry = findNode(named: "Tech Corp", in: newWork) else {
            return XCTFail("Rebuilt tree lost the work entry")
        }

        // Scalar omission means UNCHANGED — never deleted.
        guard let newStartDate = findNode(named: "startDate", in: newEntry) else {
            return XCTFail("Omitted scalar field was deleted — omission must mean unchanged")
        }
        XCTAssertEqual(newStartDate.value, "2020-01")

        // Edited scalar applied.
        XCTAssertEqual(findNode(named: "position", in: newEntry)?.value, "Principal Dev")

        // List-child omission deletes.
        guard let newHighlights = findNode(named: "highlights", in: newEntry) else {
            return XCTFail("Highlights container missing")
        }
        XCTAssertEqual(newHighlights.orderedChildren.map(\.value), ["Kept highlight"])

        // Entry omission deletes the collection entry.
        XCTAssertNil(findNode(named: "Old Job", in: newWork))

        guard let report = service.lastImportReport else {
            return XCTFail("Import report must be populated after build")
        }
        XCTAssertEqual(report.prunedNodes.count, 2,
                       "Exactly the omitted highlight and the omitted entry prune: \(report.prunedNodes)")
        XCTAssertTrue(report.prunedNodes.contains("Old Job"))
    }

    // MARK: - B3/B6 / RA-9, GR-3: blocked edits, blocked creations, unmatched ids

    func testBlockedEditUnmatchedIdAndBlockedCreationAreReported() throws {
        let (resume, _, entry) = makeHighlightsEditableResume()
        guard let startDate = entry.orderedChildren.first(where: { $0.name == "startDate" }) else {
            return XCTFail("Fixture missing startDate")
        }

        let service = ResumeRevisionWorkspaceService(baseDirectory: makeTempBase())
        let ws = try service.createWorkspace()
        _ = try service.exportModifiableTreeNodes(from: resume)

        let workFile = ws.appendingPathComponent("treenodes/work.json")
        var roots = try loadNodeArray(workFile)
        // Agent oversteps: edits a non-editable node, references a bogus id,
        // and creates a node under the non-editable section root.
        roots.append(nodeDict(id: startDate.id, name: "startDate", value: "1999-12", myIndex: 1))
        roots.append(nodeDict(id: "bogus-id", name: "ghost", value: "boo", myIndex: 9))
        roots.append(nodeDict(id: "new-2", name: "fabricated", value: "Sneaky new entry", myIndex: 10))
        try writeNodeArray(roots, to: workFile)

        let revised = try service.importRevisedTreeNodes()
        let newResume = try service.buildNewResume(from: resume, revisedNodes: revised, context: modelContext)

        guard let newRoot = newResume.rootNode else { return XCTFail("No root") }
        XCTAssertEqual(findNode(named: "startDate", in: newRoot)?.value, "2020-01",
                       "Non-editable nodes must never receive agent edits")
        XCTAssertNil(findNode(named: "fabricated", in: newRoot),
                     "Creation under a non-editable parent must be blocked")

        guard let report = service.lastImportReport else {
            return XCTFail("Import report must be populated")
        }
        XCTAssertEqual(report.blockedEdits, ["startDate"])
        XCTAssertTrue(report.unmatchedIds.contains("bogus-id"))
        XCTAssertEqual(report.blockedCreations.count, 1)
        XCTAssertFalse(report.isEmpty)
        XCTAssertFalse(report.summaryText.isEmpty)
    }

    // MARK: - B10 / CU-17: mid-session manual edits are conflicts, not clobbers

    func testMidSessionManualEditConflicts() throws {
        let (resume, highlights, _) = makeHighlightsEditableResume()
        let items = highlights.orderedChildren
        XCTAssertEqual(items.count, 2)

        let service = ResumeRevisionWorkspaceService(baseDirectory: makeTempBase())
        let ws = try service.createWorkspace()
        _ = try service.exportModifiableTreeNodes(from: resume)

        // After export, the user edits BOTH highlights in the main window.
        items[0].value = "User polished phrasing"
        items[1].value = "User tweaked too"

        // The agent rewrites only the first; the second stays as exported.
        let workFile = ws.appendingPathComponent("treenodes/work.json")
        var roots = try loadNodeArray(workFile)
        var children = roots[0]["children"] as? [[String: Any]] ?? []
        children[0]["value"] = "Agent rewrite"
        roots[0]["children"] = children
        try writeNodeArray(roots, to: workFile)

        let revised = try service.importRevisedTreeNodes()
        let newResume = try service.buildNewResume(from: resume, revisedNodes: revised, context: modelContext)

        guard let newRoot = newResume.rootNode,
              let newHighlights = findNode(named: "highlights", in: newRoot) else {
            return XCTFail("Highlights container missing")
        }
        let newValues = newHighlights.orderedChildren.map(\.value)
        XCTAssertEqual(newValues, ["Agent rewrite", "User tweaked too"],
                       "Workspace wins only where the agent actually rewrote; otherwise the manual edit survives")

        guard let report = service.lastImportReport else {
            return XCTFail("Import report must be populated")
        }
        XCTAssertEqual(report.manualEditConflicts.count, 2,
                       "Both mid-session edits must be reported: \(report.manualEditConflicts)")
    }

    // MARK: - B7 / RA-8: write tool authorizes the RESOLVED path

    func testWriteToolRejectsTraversalOutsideAllowlist() throws {
        let service = ResumeRevisionWorkspaceService(baseDirectory: makeTempBase())
        let ws = try service.createWorkspace()

        let emptyArray = "[]"
        let fontContent = "[{\"key\": \"body\", \"fontString\": \"12pt\"}]"

        // Allowed targets.
        XCTAssertNoThrow(try WriteJsonFileTool.execute(
            parameters: .init(path: "treenodes/work.json", content: emptyArray), repoRoot: ws
        ))
        XCTAssertNoThrow(try WriteJsonFileTool.execute(
            parameters: .init(path: "fontsizenodes.json", content: fontContent), repoRoot: ws
        ))

        // Traversal into the protected snapshot area must be rejected.
        XCTAssertThrowsError(try WriteJsonFileTool.execute(
            parameters: .init(path: "treenodes/../snapshots/work.json", content: emptyArray), repoRoot: ws
        ))
        // Escape from the workspace entirely.
        XCTAssertThrowsError(try WriteJsonFileTool.execute(
            parameters: .init(path: "treenodes/../../escape.json", content: emptyArray), repoRoot: ws
        ))
        // Absolute paths.
        XCTAssertThrowsError(try WriteJsonFileTool.execute(
            parameters: .init(path: "/tmp/outside.json", content: emptyArray), repoRoot: ws
        ))
        // Unlisted locations inside the workspace.
        XCTAssertThrowsError(try WriteJsonFileTool.execute(
            parameters: .init(path: "snapshots/work.json", content: emptyArray), repoRoot: ws
        ))
        XCTAssertThrowsError(try WriteJsonFileTool.execute(
            parameters: .init(path: "treenodes/nested/work.json", content: emptyArray), repoRoot: ws
        ))

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ws.appendingPathComponent("snapshots/work.json").path),
            "Blocked writes must leave no file behind"
        )
    }

    // MARK: - B10 / RA-17: slug dedupe keeps colliding sections apart

    func testSlugDeduplicationForCollidingSectionNames() throws {
        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [])
        modelContext.insert(resume)
        let root = TreeNode(name: "root", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        modelContext.insert(root)
        resume.rootNode = root

        // Both names sanitize to "my_skills".
        let sectionA = addNode("My Skills", status: .isNotLeaf, parent: root, resume: resume)
        let leafA = addNode("summaryA", value: "Original A", status: .aiToReplace, parent: sectionA, resume: resume)
        let sectionB = addNode("my_skills", status: .isNotLeaf, parent: root, resume: resume)
        let leafB = addNode("summaryB", value: "Original B", status: .aiToReplace, parent: sectionB, resume: resume)

        let service = ResumeRevisionWorkspaceService(baseDirectory: makeTempBase())
        let ws = try service.createWorkspace()
        let manifest = try service.exportModifiableTreeNodes(from: resume)

        XCTAssertEqual(Set(manifest.sections.map(\.file)),
                       ["treenodes/my_skills.json", "treenodes/my_skills_2.json"],
                       "Two sections must never collide on one file")

        // Edit both files; each edit must land in ITS section.
        for (file, newValue, leafID) in [
            ("treenodes/my_skills.json", "Revised A", leafA.id),
            ("treenodes/my_skills_2.json", "Revised B", leafB.id)
        ] {
            let url = ws.appendingPathComponent(file)
            var roots = try loadNodeArray(url)
            XCTAssertEqual(roots[0]["id"] as? String, leafID, "File \(file) must hold its own section's root")
            roots[0]["value"] = newValue
            try writeNodeArray(roots, to: url)
        }

        let revised = try service.importRevisedTreeNodes()
        let newResume = try service.buildNewResume(from: resume, revisedNodes: revised, context: modelContext)

        guard let newRoot = newResume.rootNode else { return XCTFail("No root") }
        XCTAssertEqual(findNode(named: "summaryA", in: newRoot)?.value, "Revised A")
        XCTAssertEqual(findNode(named: "summaryB", in: newRoot)?.value, "Revised B")
        XCTAssertTrue(service.lastImportReport?.isEmpty ?? true)
    }

    // MARK: - B4 / TB-1: collection patterns resolve to attribute level

    func testCollectionPatternMarksAttributeLevelNotSectionRoot() throws {
        let defaults = ExperienceDefaults()
        defaults.isWorkEnabled = true

        let workA = WorkExperienceDefault(id: UUID())
        workA.name = "Tech Corp"
        workA.position = "Senior Dev"
        workA.highlights = [HighlightDefault(text: "Shipped cool stuff")]
        defaults.workExperiences.append(workA)

        let workB = WorkExperienceDefault(id: UUID())
        workB.name = "Lab Inc"
        workB.position = "Researcher"
        workB.highlights = [HighlightDefault(text: "Discovered things")]
        defaults.workExperiences.append(workB)

        modelContext.insert(defaults)

        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [])
        modelContext.insert(resume)

        let manifest = TemplateManifest(
            slug: "test",
            sectionOrder: ["work"],
            sections: [
                "work": TemplateManifest.Section(
                    type: .arrayOfObjects,
                    defaultValue: nil,
                    fields: [
                        TemplateManifest.Section.FieldDescriptor(
                            key: "*",
                            children: [
                                TemplateManifest.Section.FieldDescriptor(key: "name"),
                                TemplateManifest.Section.FieldDescriptor(key: "position"),
                                TemplateManifest.Section.FieldDescriptor(
                                    key: "highlights",
                                    children: [
                                        TemplateManifest.Section.FieldDescriptor(key: "text")
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ],
            defaultAIFields: ["work[].highlights"]
        )

        let builder = ExperienceDefaultsToTree(resume: resume, experienceDefaults: defaults, manifest: manifest)
        guard let root = builder.buildTree(),
              let workNode = root.orderedChildren.first(where: { $0.name == "work" }) else {
            return XCTFail("Builder produced no work section")
        }

        XCTAssertNotEqual(workNode.status, .aiToReplace,
                          "work[].highlights must NOT hand the agent the whole work section")

        let entries = workNode.orderedChildren
        XCTAssertEqual(entries.count, 2)
        for entryNode in entries {
            XCTAssertNotEqual(entryNode.status, .aiToReplace,
                              "Entries themselves stay out of the editable set")
            guard let highlightsNode = entryNode.orderedChildren.first(where: { $0.name == "highlights" }) else {
                return XCTFail("Entry '\(entryNode.name)' missing highlights container")
            }
            XCTAssertEqual(highlightsNode.status, .aiToReplace,
                           "Each entry's highlights container is exactly what the manifest named")
            XCTAssertNotEqual(entryNode.orderedChildren.first(where: { $0.name == "position" })?.status,
                              .aiToReplace,
                              "Sibling attributes stay untouched")
        }
    }

    // MARK: - B5 / TB-3, TB-4: exclusion blocks inheritance; sweep clears orphans

    func testExclusionBlocksInheritanceAndSweepClearsOrphans() throws {
        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [])
        modelContext.insert(resume)
        let root = TreeNode(name: "root", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        modelContext.insert(root)
        resume.rootNode = root

        let section = addNode("work", status: .aiToReplace, parent: root, resume: resume)
        let included = addNode("Included Entry", status: .isNotLeaf, parent: section, resume: resume)
        let includedLeaf = addNode("position", value: "Dev", parent: included, resume: resume)
        let excluded = addNode("Excluded Entry", status: .excludedFromGroup, parent: section, resume: resume)
        let excludedLeaf = addNode("position", value: "Old Dev", parent: excluded, resume: resume)

        // Inheritance reaches through included entries…
        XCTAssertTrue(includedLeaf.isInheritedAISelection)
        // …but stops at an excluded ancestor: the child must not claim
        // "included in AI revision" when it will never be exported.
        XCTAssertFalse(excludedLeaf.isInheritedAISelection)
        XCTAssertFalse(excludedLeaf.hasAncestorWithAIStatus)

        // Export agrees with the display: the excluded subtree never leaves.
        let service = ResumeRevisionWorkspaceService(baseDirectory: makeTempBase())
        let ws = try service.createWorkspace()
        _ = try service.exportModifiableTreeNodes(from: resume)
        let roots = try loadNodeArray(ws.appendingPathComponent("treenodes/work.json"))
        XCTAssertEqual(roots.count, 1)
        let exportedEntries = roots[0]["children"] as? [[String: Any]] ?? []
        XCTAssertEqual(exportedEntries.compactMap { $0["name"] as? String }, ["Included Entry"])

        // Sweep on leaving the editable state happens in the status setter
        // itself — every UI surface (section dropdown, entry-card container
        // menu, solo toggles) assigns status directly, so no orphaned
        // exclusions linger regardless of which surface unmarked the node.
        section.status = .saved
        XCTAssertEqual(excluded.status, .saved,
                       "Orphaned exclusions must not silently re-apply when the section is re-marked")
        XCTAssertEqual(included.status, .isNotLeaf, "Sweep touches only exclusion marks")
    }

    // MARK: - TB-4: container-level unmark sweeps orphans (entry-card surface)

    func testContainerUnmarkSweepsOrphanedExclusions() throws {
        // Post-B4 manifest seeding marks each entry's attribute container
        // (work[].highlights) editable — the entry-card container toggle, not
        // the section dropdown, is the primary unmark surface. Unmarking the
        // container must sweep exclusions beneath it.
        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [])
        modelContext.insert(resume)
        let root = TreeNode(name: "root", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        modelContext.insert(root)
        resume.rootNode = root

        let work = addNode("work", status: .isNotLeaf, parent: root, resume: resume)
        let entry = addNode("Tech Corp", status: .isNotLeaf, parent: work, resume: resume)
        let highlights = addNode("highlights", status: .aiToReplace, parent: entry, resume: resume)
        let kept = addNode("", value: "Shipped it", parent: highlights, resume: resume)
        let optedOut = addNode("", value: "Skip me", status: .excludedFromGroup, parent: highlights, resume: resume)

        // The entry-card menu toggle is a plain status assignment.
        highlights.status = .saved

        XCTAssertEqual(optedOut.status, .saved,
                       "Container unmark must sweep descendant opt-outs — no orphan may re-apply on re-mark")
        XCTAssertEqual(kept.status, .saved, "Non-excluded children are untouched")
    }

    // MARK: - TB-4: exclusions under a still-live group survive the sweep

    func testSweepPreservesExclusionsBelongingToLiveGroups() throws {
        // Nested marks: section AND an entry's container both editable.
        // An exclusion's group is its nearest editable ancestor chain — the
        // sweep may only clear it once NO editable ancestor remains.
        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [])
        modelContext.insert(resume)
        let root = TreeNode(name: "root", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        modelContext.insert(root)
        resume.rootNode = root

        let work = addNode("work", status: .aiToReplace, parent: root, resume: resume)
        let entry = addNode("Tech Corp", status: .isNotLeaf, parent: work, resume: resume)
        let highlights = addNode("highlights", status: .aiToReplace, parent: entry, resume: resume)
        let optedOut = addNode("", value: "Skip me", status: .excludedFromGroup, parent: highlights, resume: resume)
        let entryField = addNode("position", value: "Dev", status: .excludedFromGroup, parent: entry, resume: resume)

        // Unmarking the section dissolves ITS group (entryField's opt-out),
        // but must not reach into the still-editable highlights container.
        work.status = .saved
        XCTAssertEqual(entryField.status, .saved,
                       "Opt-out whose only group dissolved is swept")
        XCTAssertEqual(optedOut.status, .excludedFromGroup,
                       "Opt-out under a still-editable container keeps its meaning")

        // Re-mark the section, then unmark the container while the section is
        // still editable: the opt-out still blocks the section's group.
        work.status = .aiToReplace
        highlights.status = .saved
        XCTAssertEqual(optedOut.status, .excludedFromGroup,
                       "Opt-out stays while any editable ancestor remains")

        // Once the last editable ancestor goes, the orphan is swept.
        work.status = .saved
        XCTAssertEqual(optedOut.status, .saved,
                       "Sweep clears the opt-out when its last group dissolves")
    }

    // MARK: - B9 / RA-12, TB-5: addChild never reuses a surviving sibling's index

    func testAddChildAssignsMaxIndexPlusOne() throws {
        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [])
        modelContext.insert(resume)
        let parent = TreeNode(name: "list", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        modelContext.insert(parent)

        let a = addNode("", value: "A", parent: parent, resume: resume)
        let b = addNode("", value: "B", parent: parent, resume: resume)
        let c = addNode("", value: "C", parent: parent, resume: resume)
        XCTAssertEqual([a.myIndex, b.myIndex, c.myIndex], [0, 1, 2])

        // Delete the middle child, then append: the new child must NOT collide
        // with C's index (the old `count`-based assignment gave it 2).
        parent.children?.removeAll { $0.id == b.id }
        let d = addNode("", value: "D", parent: parent, resume: resume)
        XCTAssertEqual(d.myIndex, 3)
        XCTAssertEqual(parent.orderedChildren.map(\.value), ["A", "C", "D"])
    }
}
