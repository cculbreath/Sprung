//
//  SubmittedPacketStoreTests.swift
//  SprungTests
//
//  Pins the SubmittedPacket persistence contract (app-audit 2026-07-06,
//  resume-editor #2): a submitted packet freezes the rendered PDF bytes + tree
//  snapshot for a job application, and `JobAppStore.submittedPackets(for:)`
//  returns them scoped to that job app, newest first.
//
//  The mint path itself (ExportFileService.renderAndRecordPacket) force-renders
//  through NativePDFGenerator (headless chromium) and so is not unit-testable in
//  memory — this exercises the store accessors that path relies on, plus the
//  model round-trip, directly.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class SubmittedPacketStoreTests: InMemoryStoreCase {

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

    private func makePacket(
        jobAppId: UUID,
        date: Date,
        label: String,
        pdf: Data = Data([0x25, 0x50, 0x44, 0x46]) // "%PDF"
    ) -> SubmittedPacket {
        SubmittedPacket(
            jobAppId: jobAppId,
            submittedDate: date,
            resumePdfData: pdf,
            treeSnapshotData: Data("{}".utf8),
            coverLetterText: "Dear hiring manager",
            templateSlug: "aleo",
            label: label
        )
    }

    func testRecordedPacketRoundTripsWithNonEmptyBytes() throws {
        let store = makeJobAppStore()
        let job = JobApp(jobPosition: "Optical Engineer")
        insert(job)
        saveContext()

        let packet = makePacket(jobAppId: job.id, date: Date(), label: "Aleo — AI revised")
        store.recordSubmittedPacket(packet)

        let fetched = store.submittedPackets(for: job)
        XCTAssertEqual(fetched.count, 1)
        let only = try XCTUnwrap(fetched.first)
        XCTAssertFalse(only.resumePdfData.isEmpty, "packet must retain the rendered PDF bytes")
        XCTAssertEqual(only.label, "Aleo — AI revised")
        XCTAssertEqual(only.templateSlug, "aleo")
        XCTAssertEqual(only.coverLetterText, "Dear hiring manager")
        XCTAssertEqual(only.jobAppId, job.id)
    }

    func testPacketsAreScopedToJobAppAndOrderedNewestFirst() throws {
        let store = makeJobAppStore()
        let jobA = JobApp(jobPosition: "Optical Engineer")
        let jobB = JobApp(jobPosition: "Photonics Lead")
        insert(jobA)
        insert(jobB)
        saveContext()

        let now = Date()
        let older = makePacket(jobAppId: jobA.id, date: now.addingTimeInterval(-3600), label: "Aleo v1")
        let newer = makePacket(jobAppId: jobA.id, date: now, label: "Aleo v2")
        let otherJob = makePacket(jobAppId: jobB.id, date: now, label: "Ethel")
        // Insert out of chronological order to prove the sort, not insertion order.
        store.recordSubmittedPacket(newer)
        store.recordSubmittedPacket(older)
        store.recordSubmittedPacket(otherJob)

        let fetched = store.submittedPackets(for: jobA)
        XCTAssertEqual(fetched.map(\.label), ["Aleo v2", "Aleo v1"],
                       "packets must be scoped to the job app and returned newest first")

        let fetchedB = store.submittedPackets(for: jobB)
        XCTAssertEqual(fetchedB.map(\.label), ["Ethel"])
    }

    func testDeletingJobAppRemovesItsSubmittedPackets() throws {
        let store = makeJobAppStore()
        let jobA = JobApp(jobPosition: "Optical Engineer")
        let jobB = JobApp(jobPosition: "Photonics Lead")
        insert(jobA)
        insert(jobB)
        saveContext()

        store.recordSubmittedPacket(makePacket(jobAppId: jobA.id, date: Date(), label: "Aleo"))
        store.recordSubmittedPacket(makePacket(jobAppId: jobB.id, date: Date(), label: "Ethel"))

        store.deleteJobApp(jobA)

        XCTAssertTrue(store.submittedPackets(for: jobA).isEmpty,
                      "deleting a job app must remove its submitted packets")
        XCTAssertEqual(store.submittedPackets(for: jobB).map(\.label), ["Ethel"],
                       "other job apps' packets must survive")
    }
}
