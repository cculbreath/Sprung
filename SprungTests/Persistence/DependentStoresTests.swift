//
//  DependentStoresTests.swift
//  SprungTests
//
//  Phase 3: SwiftData persistence — dependent stores that require sibling stores.
//  JobAppStore and CoverLetterStore are built on top of ResStore / CoverRefStore /
//  ApplicantProfileStore. We only exercise paths that do NOT require the optional
//  preprocessor or PDF-export Tasks (those are integration concerns, not persistence).
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class DependentStoresTests: InMemoryStoreCase {

    /// Builds the full store dependency chain bound to the test context.
    private func makeStores() -> (
        jobAppStore: JobAppStore,
        coverLetterStore: CoverLetterStore,
        resStore: ResStore
    ) {
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
        let jobAppStore = JobAppStore(
            context: context,
            resStore: resStore,
            coverLetterStore: coverLetterStore
        )
        return (jobAppStore, coverLetterStore, resStore)
    }

    // MARK: - JobAppStore

    func testAddJobAppPersists() throws {
        let stores = makeStores()
        let job = JobApp(jobPosition: "Staff Engineer", companyName: "Acme")
        let added = stores.jobAppStore.addJobApp(job)

        XCTAssertNotNil(added)
        XCTAssertEqual(stores.jobAppStore.jobApps.count, 1)
        XCTAssertEqual(try fetchAll(JobApp.self).count, 1)
        XCTAssertEqual(stores.jobAppStore.selectedApp?.persistentModelID, job.persistentModelID)
    }

    func testCreateManualEntryInsertsBlankJob() throws {
        let stores = makeStores()
        let job = stores.jobAppStore.createManualEntry()
        XCTAssertEqual(job.status, .new)
        XCTAssertEqual(job.jobPosition, "New Position")
        XCTAssertEqual(stores.jobAppStore.jobApps.count, 1)
    }

    func testJobAppsForStatusFilter() throws {
        let stores = makeStores()
        let a = JobApp(jobPosition: "A")
        let b = JobApp(jobPosition: "B")
        _ = stores.jobAppStore.addJobApp(a)
        _ = stores.jobAppStore.addJobApp(b)
        stores.jobAppStore.setStatus(b, to: .submitted)

        XCTAssertEqual(stores.jobAppStore.jobApps(forStatus: .new).count, 1)
        XCTAssertEqual(stores.jobAppStore.jobApps(forStatus: .submitted).count, 1)
    }

    func testAdvanceStatusProgressesPipeline() throws {
        let stores = makeStores()
        let job = JobApp(jobPosition: "P")
        _ = stores.jobAppStore.addJobApp(job)
        XCTAssertEqual(job.status, .new)

        stores.jobAppStore.advanceStatus(job)
        XCTAssertEqual(job.status, .queued)
        stores.jobAppStore.advanceStatus(job)
        XCTAssertEqual(job.status, .inProgress)
    }

    func testSetStatusRejectedStampsClosedDate() throws {
        let stores = makeStores()
        let job = JobApp(jobPosition: "P")
        _ = stores.jobAppStore.addJobApp(job)

        stores.jobAppStore.setStatus(job, to: .rejected)
        XCTAssertEqual(job.status, .rejected)
        XCTAssertNotNil(job.closedDate)
    }

    func testDeleteJobAppRemovesIt() throws {
        let stores = makeStores()
        let job = JobApp(jobPosition: "ToDelete")
        _ = stores.jobAppStore.addJobApp(job)
        XCTAssertEqual(stores.jobAppStore.jobApps.count, 1)

        stores.jobAppStore.deleteJobApp(job)
        XCTAssertEqual(stores.jobAppStore.jobApps.count, 0)
        XCTAssertEqual(try fetchAll(JobApp.self).count, 0)
    }

    func testJobAppByIdLookup() throws {
        let stores = makeStores()
        let job = JobApp(jobPosition: "Find Me")
        _ = stores.jobAppStore.addJobApp(job)
        XCTAssertEqual(stores.jobAppStore.jobApp(byId: job.id)?.persistentModelID, job.persistentModelID)
        XCTAssertNil(stores.jobAppStore.jobApp(byId: UUID()))
    }

    // MARK: - CoverLetterStore

    func testCreateLetterPersistsAttachedToJob() throws {
        let stores = makeStores()
        let job = JobApp(jobPosition: "P")
        _ = stores.jobAppStore.addJobApp(job)

        let letter = stores.coverLetterStore.create(jobApp: job)
        XCTAssertEqual(try fetchAll(CoverLetter.self).count, 1)
        XCTAssertEqual(letter.jobApp?.persistentModelID, job.persistentModelID)
    }

    func testAddLetterSetsSelectedCover() throws {
        let stores = makeStores()
        let job = JobApp(jobPosition: "P")
        _ = stores.jobAppStore.addJobApp(job)

        let letter = CoverLetter(enabledRefs: [], jobApp: job)
        let added = stores.coverLetterStore.addLetter(letter: letter, to: job)
        XCTAssertEqual(job.coverLetters.count, 1)
        XCTAssertEqual(job.selectedCover?.persistentModelID, added.persistentModelID)
    }

    func testDeleteLetterRemovesFromJob() throws {
        let stores = makeStores()
        let job = JobApp(jobPosition: "P")
        _ = stores.jobAppStore.addJobApp(job)
        let letter = stores.coverLetterStore.create(jobApp: job)
        job.coverLetters.append(letter)

        stores.coverLetterStore.deleteLetter(letter)
        XCTAssertEqual(try fetchAll(CoverLetter.self).count, 0)
    }
}
