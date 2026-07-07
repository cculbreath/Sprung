//
//  CoverLetterChosenDraftTests.swift
//  SprungTests
//
//  Pins the chosen-submission-draft unmark contract (app-audit 2026-07-06,
//  coverletters-sgm #1): unmarking clears ONLY that letter's
//  `isChosenSubmissionDraft` flag — it must not touch sibling letters or the
//  job app's editor selection (`selectedCover`). Before the fix, the
//  inspector's unmark branch nil'ed `selectedCover` (blanking the editor)
//  and left the chosen flag set.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class CoverLetterChosenDraftTests: InMemoryStoreCase {

    func testUnmarkClearsChosenFlagWithoutBlankingSelection() throws {
        let job = JobApp(jobPosition: "P")
        insert(job)
        let a = CoverLetter(enabledRefs: [], jobApp: job)
        let b = CoverLetter(enabledRefs: [], jobApp: job)
        insert(a)
        insert(b)
        job.coverLetters.append(contentsOf: [a, b])
        saveContext()

        b.markAsChosenSubmissionDraft()
        job.selectedCover = b
        XCTAssertTrue(b.isChosenSubmissionDraft)

        b.unmarkAsChosenSubmissionDraft()

        XCTAssertFalse(b.isChosenSubmissionDraft, "unmark must clear the chosen flag")
        XCTAssertEqual(job.selectedCoverId, b.id, "unmark must not blank the editor selection")
    }

    func testUnmarkTouchesOnlyThatLetter() throws {
        let job = JobApp(jobPosition: "P")
        insert(job)
        let chosen = CoverLetter(enabledRefs: [], jobApp: job)
        let other = CoverLetter(enabledRefs: [], jobApp: job)
        insert(chosen)
        insert(other)
        job.coverLetters.append(contentsOf: [chosen, other])
        saveContext()

        chosen.markAsChosenSubmissionDraft()
        other.unmarkAsChosenSubmissionDraft()

        XCTAssertTrue(chosen.isChosenSubmissionDraft, "unmarking another letter must not clear the chosen one")
        XCTAssertFalse(other.isChosenSubmissionDraft)
    }
}
