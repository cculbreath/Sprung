//
//  TreeNodeInvariantsTests.swift
//  SprungTests
//
//  Phase 2 — TreeNode model invariants. These pin the single AI-selection axis
//  (isEditable == .aiToReplace), the recursive aiStatusChildren count, the
//  .excludedFromGroup inheritance barrier, the status-setter orphan cleanup,
//  computedTitle template substitution, and orderedChildren ordering.
//
//  TreeNode and Resume are SwiftData @Model types, so every node is constructed in
//  a live in-memory context (InMemoryStoreCase).
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class TreeNodeInvariantsTests: InMemoryStoreCase {

    // MARK: - Helpers

    private func makeRoot() -> (Resume, TreeNode) {
        let resume = RenderFixtures.makeResume(in: context)
        let root = RenderFixtures.makeRoot(for: resume, in: context)
        return (resume, root)
    }

    @discardableResult
    private func add(_ name: String, to parent: TreeNode, status: LeafStatus = .saved, value: String = "") -> TreeNode {
        RenderFixtures.addNode(to: parent, name: name, value: value, status: status, in: context)
    }

    // MARK: - isEditable ≡ .aiToReplace

    func testIsEditableTracksAIToReplace() {
        let (_, root) = makeRoot()
        let node = add("field", to: root, status: .saved)

        XCTAssertFalse(node.isEditable, ".saved node must not be editable")
        node.status = .aiToReplace
        XCTAssertTrue(node.isEditable, ".aiToReplace node must be editable")
        node.status = .disabled
        XCTAssertFalse(node.isEditable)
    }

    func testIsEditableFalseForNonAIStatuses() {
        let (_, root) = makeRoot()
        for status: LeafStatus in [.isEditing, .excludedFromGroup, .disabled, .saved, .isNotLeaf] {
            let node = add("n", to: root, status: status)
            XCTAssertEqual(node.isEditable, status == .aiToReplace,
                           "isEditable must be true only for .aiToReplace (status: \(status))")
        }
    }

    // MARK: - aiStatusChildren (recursive)

    func testAIStatusChildrenCountsSelfAndDescendants() {
        let (_, root) = makeRoot()
        // root is .isNotLeaf (0). Two editable leaves + one nested editable.
        let work = add("work", to: root, status: .isNotLeaf)
        let entry = add("", to: work, status: .isNotLeaf)
        add("position", to: entry, status: .aiToReplace)         // +1
        let highlights = add("highlights", to: entry, status: .aiToReplace) // +1
        add("", to: highlights, status: .aiToReplace)            // +1 (nested under editable)
        add("name", to: root, status: .saved)                    // +0

        XCTAssertEqual(root.aiStatusChildren, 3,
                       "aiStatusChildren must recursively count every .aiToReplace node")
        XCTAssertEqual(highlights.aiStatusChildren, 2, "self + one editable child")
    }

    func testAIStatusChildrenZeroWhenNoneEditable() {
        let (_, root) = makeRoot()
        add("a", to: root, status: .saved)
        let b = add("b", to: root, status: .isNotLeaf)
        add("c", to: b, status: .disabled)
        XCTAssertEqual(root.aiStatusChildren, 0)
    }

    func testResumeHasUpdatableNodesFollowsAIStatusChildren() {
        let (resume, root) = makeRoot()
        XCTAssertFalse(resume.hasUpdatableNodes, "no editable nodes ⇒ not updatable")
        let node = add("objective", to: root, status: .saved)
        XCTAssertFalse(resume.hasUpdatableNodes)
        node.status = .aiToReplace
        XCTAssertTrue(resume.hasUpdatableNodes, "one .aiToReplace node ⇒ updatable")
    }

    // MARK: - hasAncestorWithAIStatus & exclusion barrier

    func testHasAncestorWithAIStatusWalksUp() {
        let (_, root) = makeRoot()
        let section = add("work", to: root, status: .aiToReplace)
        let entry = add("", to: section, status: .saved)
        let leaf = add("position", to: entry, status: .saved)

        XCTAssertTrue(leaf.hasAncestorWithAIStatus, "an editable ancestor must be visible")
        XCTAssertTrue(entry.hasAncestorWithAIStatus)
        XCTAssertFalse(section.hasAncestorWithAIStatus, "the editable node itself has no editable ancestor")
    }

    func testExclusionBlocksInheritanceFromHigherAncestor() {
        let (_, root) = makeRoot()
        let section = add("work", to: root, status: .aiToReplace)
        let excludedEntry = add("", to: section, status: .excludedFromGroup)
        let leaf = add("position", to: excludedEntry, status: .saved)

        // The walk stops at the .excludedFromGroup ancestor: the leaf is NOT in the group.
        XCTAssertFalse(leaf.hasAncestorWithAIStatus,
                       "exclusion must block inheritance from a higher editable ancestor")
    }

    func testIsInheritedAISelection() {
        let (_, root) = makeRoot()
        let section = add("skills", to: root, status: .aiToReplace)
        let leaf = add("name", to: section, status: .saved)

        XCTAssertTrue(leaf.isInheritedAISelection, "non-editable node under an editable ancestor inherits")
        XCTAssertFalse(section.isInheritedAISelection, "a directly-editable node is not 'inherited'")

        leaf.status = .aiToReplace
        XCTAssertFalse(leaf.isInheritedAISelection, "a directly-editable node is never inherited")
    }

    // MARK: - Status-setter orphan cleanup (TB-4 sweep)

    func testLeavingEditableClearsOrphanedExclusions() {
        let (_, root) = makeRoot()
        // section editable; one child opts out via .excludedFromGroup.
        let section = add("work", to: root, status: .aiToReplace)
        let excluded = add("", to: section, status: .excludedFromGroup)
        add("position", to: excluded, status: .saved)

        // Dissolve the group: section leaves .aiToReplace with no editable ancestor.
        section.status = .saved

        XCTAssertNotEqual(excluded.status, .excludedFromGroup,
                          "orphaned exclusion must be cleared when its group dissolves")
        XCTAssertEqual(excluded.status, .saved, "cleared exclusions become .saved")
    }

    func testExclusionUnderStillEditableAncestorIsPreserved() {
        let (_, root) = makeRoot()
        // Outer editable stays editable; inner editable dissolves but is nested under outer.
        let outer = add("work", to: root, status: .aiToReplace)
        let inner = add("", to: outer, status: .aiToReplace)
        let excluded = add("highlights", to: inner, status: .excludedFromGroup)

        // inner leaves .aiToReplace, but it still has an editable ancestor (outer),
        // so the setter's guard returns early and exclusions are NOT swept.
        inner.status = .saved

        XCTAssertEqual(excluded.status, .excludedFromGroup,
                       "exclusion must survive while an editable ancestor remains")
    }

    func testNonEditableExitDoesNotTriggerSweep() {
        let (_, root) = makeRoot()
        let section = add("work", to: root, status: .saved)
        let excluded = add("", to: section, status: .excludedFromGroup)

        // section was never .aiToReplace, so changing its status must not sweep descendants.
        section.status = .disabled
        XCTAssertEqual(excluded.status, .excludedFromGroup,
                       "sweep only fires when leaving .aiToReplace")
    }

    // MARK: - computedTitle

    func testComputedTitleSubstitutesChildValues() {
        let (_, root) = makeRoot()
        let entry = add("", to: root, status: .isNotLeaf)
        entry.schemaTitleTemplate = "{{position}} at {{company}}"
        add("position", to: entry, status: .saved, value: "Engineer")
        add("company", to: entry, status: .saved, value: "Acme")

        XCTAssertEqual(entry.computedTitle, "Engineer at Acme")
    }

    func testComputedTitleFallsBackToDisplayLabelWhenNoTemplate() {
        let (_, root) = makeRoot()
        let node = add("position", to: root, status: .saved)
        node.editorLabel = "Job Title"
        // No schemaTitleTemplate ⇒ displayLabel (editorLabel wins over label).
        XCTAssertEqual(node.computedTitle, "Job Title")
    }

    func testComputedTitleLeavesUnmatchedPlaceholdersInPlace() {
        let (_, root) = makeRoot()
        let entry = add("", to: root, status: .isNotLeaf)
        entry.schemaTitleTemplate = "{{position}} — {{missing}}"
        add("position", to: entry, status: .saved, value: "Engineer")
        // Only matched placeholders are replaced; unmatched ones remain.
        XCTAssertEqual(entry.computedTitle, "Engineer — {{missing}}")
    }

    func testComputedTitleMatchesBySchemaKey() {
        let (_, root) = makeRoot()
        let entry = add("", to: root, status: .isNotLeaf)
        entry.schemaTitleTemplate = "{{role}}"
        let child = add("position", to: entry, status: .saved, value: "Engineer")
        child.schemaKey = "role" // template field matches schemaKey, not name
        XCTAssertEqual(entry.computedTitle, "Engineer")
    }

    // MARK: - orderedChildren & addChild indexing

    func testOrderedChildrenSortsByMyIndex() {
        let (_, root) = makeRoot()
        let a = add("a", to: root)
        let b = add("b", to: root)
        let c = add("c", to: root)

        XCTAssertEqual(a.myIndex, 0)
        XCTAssertEqual(b.myIndex, 1)
        XCTAssertEqual(c.myIndex, 2)
        XCTAssertEqual(root.orderedChildren.map(\.name), ["a", "b", "c"])
    }

    func testAddChildUsesMaxIndexPlusOneAfterDeletion() {
        let (_, root) = makeRoot()
        let a = add("a", to: root) // index 0
        add("b", to: root)         // index 1
        let c = add("c", to: root) // index 2

        // Remove a middle node from the children array (no manifest deletion gate needed here).
        if let idx = root.children?.firstIndex(of: a) {
            root.children?.remove(at: idx)
        }
        // New child must take max(existing)+1 = 3, not count (which would collide with c@2).
        let d = add("d", to: root)
        XCTAssertEqual(d.myIndex, 3, "addChild must use max(myIndex)+1, never count")
        XCTAssertGreaterThan(d.myIndex, c.myIndex)
    }

    func testAddChildSetsParentAndDepth() {
        let (_, root) = makeRoot() // depth 0
        let child = add("child", to: root)
        XCTAssertTrue(child.parent === root)
        XCTAssertEqual(child.depth, 1)
        let grandchild = add("gc", to: child)
        XCTAssertEqual(grandchild.depth, 2)
    }
}
