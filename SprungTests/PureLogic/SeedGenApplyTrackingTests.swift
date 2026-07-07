//
//  SeedGenApplyTrackingTests.swift
//  SprungTests
//
//  Pins the incremental-Apply contract for the Seed Generation Module.
//  Applying a subset of approved items must not re-apply them, and items
//  approved AFTER an Apply must stay actionable. Regression guard for the bug
//  where Apply was one-shot (a `hasApplied` flag): a user who applied a batch,
//  then approved more items from the still-pending queue, saw Apply
//  permanently disabled — those later approvals were stranded until the window
//  was closed and the entire (paid) generation re-ran.
//
//  The load-bearing seam is `ReviewQueue.approvedItems(excluding:)`, the single
//  source of truth used by both the Apply button's enabled state and
//  `SeedGenerationOrchestrator.applyApprovedContent(to:skipping:)`.
//

import XCTest
@testable import Sprung

@MainActor
final class SeedGenApplyTrackingTests: XCTestCase {

    private func makeTask(_ name: String) -> GenerationTask {
        GenerationTask(section: .work, displayName: name, generatorType: "WorkHighlightsGenerator")
    }

    private func makeContent(_ targetId: String) -> GeneratedContent {
        GeneratedContent(type: .workHighlights(targetId: targetId, highlights: ["did a thing"]))
    }

    func testExcludingDropsAlreadyAppliedIDs() {
        let queue = ReviewQueue()
        queue.add(task: makeTask("A"), content: makeContent("a"))
        queue.add(task: makeTask("B"), content: makeContent("b"))
        let ids = queue.items.map(\.id)
        queue.setAction(for: ids[0], action: .approved)
        queue.setAction(for: ids[1], action: .approved)

        XCTAssertEqual(queue.approvedItems(excluding: []).count, 2)

        let remaining = queue.approvedItems(excluding: [ids[0]])
        XCTAssertEqual(remaining.map(\.id), [ids[1]],
                       "an already-applied item must not resurface for Apply")
    }

    func testItemApprovedAfterApplyStaysActionable() {
        let queue = ReviewQueue()
        queue.add(task: makeTask("A"), content: makeContent("a"))
        queue.add(task: makeTask("B"), content: makeContent("b"))
        let ids = queue.items.map(\.id)

        // Approve + "apply" only the first item.
        queue.setAction(for: ids[0], action: .approved)
        let applied = Set(queue.approvedItems(excluding: []).map(\.id))
        XCTAssertEqual(applied, [ids[0]])

        // Approve the second item afterwards — it is the sole un-applied item,
        // so Apply must remain enabled and target exactly it.
        queue.setAction(for: ids[1], action: .approved)
        let remaining = queue.approvedItems(excluding: applied)
        XCTAssertEqual(remaining.map(\.id), [ids[1]],
                       "items approved after an Apply must remain actionable")
    }

    func testEditingKeepsItemIDStableForTracking() {
        let queue = ReviewQueue()
        queue.add(task: makeTask("A"), content: makeContent("a"))
        let id = queue.items[0].id

        // Editing marks the item approved-equivalent while preserving its id,
        // so applied-ID tracking survives a user edit.
        queue.setEditedChildren(for: id, children: ["edited"])
        XCTAssertEqual(queue.items[0].id, id)
        XCTAssertTrue(queue.items[0].isApproved)
        XCTAssertTrue(queue.approvedItems(excluding: [id]).isEmpty,
                      "an edited-then-applied item must not resurface for Apply")
    }
}
