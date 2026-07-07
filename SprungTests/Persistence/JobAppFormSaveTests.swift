//
//  JobAppFormSaveTests.swift
//  SprungTests
//
//  Pins the contract of `JobAppStore.saveForm(_:)`: every field the Listing
//  edit form (`JobAppFormView`) renders as editable must be copied back to the
//  entity on save. Regression guard for the silent-discard bug where `salary`
//  was populated into the form (`populateFormFromObj`) and rendered editable,
//  but `saveForm` never wrote it back — user edits vanished on next render
//  (app-audit-2026-07-06-jobapp-shell.md §1.2).
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class JobAppFormSaveTests: InMemoryStoreCase {

    /// Builds the full store dependency chain bound to the test context,
    /// mirroring JobAppDedupTests.makeJobAppStore().
    private func makeJobAppStore() -> JobAppStore {
        let templateStore = TemplateStore(context: context)
        let applicantProfileStore = ApplicantProfileStore(context: context)
        let experienceDefaultsStore = ExperienceDefaultsStore(context: context)
        let coverRefStore = CoverRefStore(context: context)

        let exportService = ResumeExportService(
            templateStore: templateStore,
            applicantProfileStore: applicantProfileStore
        )
        let exportCoordinator = ResumeExportCoordinator(exportService: exportService)
        let resStore = ResStore(
            context: context,
            exportCoordinator: exportCoordinator,
            experienceDefaultsStore: experienceDefaultsStore
        )
        let coverLetterStore = CoverLetterStore(
            context: context,
            refStore: coverRefStore,
            applicantProfileStore: applicantProfileStore
        )
        return JobAppStore(
            context: context,
            resStore: resStore,
            coverLetterStore: coverLetterStore
        )
    }

    func testSaveFormPersistsSalaryEdit() throws {
        let store = makeJobAppStore()
        let jobApp = JobApp(
            jobPosition: "Staff Engineer",
            companyName: "Acme Corp",
            postingURL: "https://boards.example.com/jobs/123"
        )
        _ = store.addJobApp(jobApp)

        // Mirror the edit flow: populate the form from the entity, edit the
        // salary cell, save. jobDescription is left untouched so the
        // preprocessing re-queue branch stays out of the picture.
        store.editWithForm(jobApp)
        store.form.salary = "$185,000 – $210,000"
        store.saveForm(jobApp)

        XCTAssertEqual(jobApp.salary, "$185,000 – $210,000")
        let fetched = try fetchAll(JobApp.self)
        XCTAssertEqual(fetched.first?.salary, "$185,000 – $210,000")
    }

    func testSaveFormRoundTripsEveryEditableFormField() throws {
        let store = makeJobAppStore()
        let jobApp = JobApp(
            jobPosition: "Original Title",
            companyName: "Original Co",
            postingURL: ""
        )
        _ = store.addJobApp(jobApp)

        store.editWithForm(jobApp)
        store.form.jobPosition = "Edited Title"
        store.form.jobLocation = "Remote (US)"
        store.form.companyName = "Edited Co"
        store.form.companyLinkedinId = "edited-co"
        store.form.jobPostingTime = "2 days ago"
        store.form.seniorityLevel = "Senior"
        store.form.employmentType = "Full-time"
        store.form.jobFunction = "Engineering"
        store.form.industries = "Software"
        store.form.jobApplyLink = "https://apply.example.com"
        store.form.postingURL = "https://boards.example.com/jobs/999"
        store.form.salary = "$150k"
        store.saveForm(jobApp)

        XCTAssertEqual(jobApp.jobPosition, "Edited Title")
        XCTAssertEqual(jobApp.jobLocation, "Remote (US)")
        XCTAssertEqual(jobApp.companyName, "Edited Co")
        XCTAssertEqual(jobApp.companyLinkedinId, "edited-co")
        XCTAssertEqual(jobApp.jobPostingTime, "2 days ago")
        XCTAssertEqual(jobApp.seniorityLevel, "Senior")
        XCTAssertEqual(jobApp.employmentType, "Full-time")
        XCTAssertEqual(jobApp.jobFunction, "Engineering")
        XCTAssertEqual(jobApp.industries, "Software")
        XCTAssertEqual(jobApp.jobApplyLink, "https://apply.example.com")
        XCTAssertEqual(jobApp.postingURL, "https://boards.example.com/jobs/999")
        XCTAssertEqual(jobApp.salary, "$150k")
    }
}
