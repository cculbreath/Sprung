//
//  ResumeLastReviewPersistenceTests.swift
//  SprungTests
//
//  Pins the last-AI-review persistence contract (app-audit 2026-07-06,
//  resume-editor #8): the Optimize sheet's advisory review output used to be
//  view-model state only and evaporated on dismiss. It now round-trips on the
//  Resume model (lastReviewMarkdown / lastReviewDate / lastReviewType) so
//  reopening the sheet shows the previous analysis with its timestamp.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class ResumeLastReviewPersistenceTests: InMemoryStoreCase {

    func testLastReviewFieldsRoundTrip() throws {
        let job = JobApp(jobPosition: "Optical Engineer")
        insert(job)
        let resume = Resume(jobApp: job)
        insert(resume)

        let markdown = "### Overall Assessment (Score: 8)\n- Strong optics background\n- Tighten the summary"
        let stamp = Date(timeIntervalSince1970: 1_720_000_000)
        resume.lastReviewMarkdown = markdown
        resume.lastReviewDate = stamp
        resume.lastReviewType = "Assess Overall Resume Quality"
        saveContext()

        let resumeID = resume.id
        let fetched = try XCTUnwrap(
            fetchAll(Resume.self).first { $0.id == resumeID },
            "saved resume should be fetchable"
        )
        XCTAssertEqual(fetched.lastReviewMarkdown, markdown)
        XCTAssertEqual(fetched.lastReviewDate, stamp)
        XCTAssertEqual(fetched.lastReviewType, "Assess Overall Resume Quality")
    }

    func testLastReviewDefaultsNilForFreshResume() throws {
        let job = JobApp(jobPosition: "Photonics Lead")
        insert(job)
        let resume = Resume(jobApp: job)
        insert(resume)
        saveContext()

        XCTAssertNil(resume.lastReviewMarkdown, "a fresh resume has no persisted review")
        XCTAssertNil(resume.lastReviewDate)
        XCTAssertNil(resume.lastReviewType)
    }
}
