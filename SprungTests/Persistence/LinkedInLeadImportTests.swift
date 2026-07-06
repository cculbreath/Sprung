//
//  LinkedInLeadImportTests.swift
//  SprungTests
//
//  Import half of the LinkedIn MCP search board
//  (LinkedInMCPImportService.makeJobApp / importAsLead / isImported) against
//  an in-memory JobAppStore. Pins that the flow rides the SAME two-stage
//  lead pipeline as the other boards, with one LinkedIn-specific contract:
//
//   - the CANONICAL URL (https://www.linkedin.com/jobs/view/<id>/) is the
//     ONLY dedup key. Company is unknown until enrichment (search results
//     carry just id + title), so findDuplicateJobApp's title+company
//     fallback — which would false-match unrelated leads sharing a generic
//     title like "Physicist" — must never mark a different posting as a
//     duplicate.
//   - the lead lands `.new` with source "LinkedIn", empty company/description
//     (deterministic-only import: nothing guessed), and preprocessing
//     DEFERRED — enrichment fills the details later (the enrichment queue
//     itself no-ops under XCTest by design, so the stored fields here are
//     exactly what the import wrote).
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class LinkedInLeadImportTests: InMemoryStoreCase {

    /// Builds the full store dependency chain bound to the test context,
    /// mirroring JobAppDedupTests.makeJobAppStore() (JobAppStore requires a
    /// ResStore + CoverLetterStore at construction).
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

    private func makeLead(
        jobID: String = "4432291764",
        title: String = "Staff Physicist"
    ) -> LinkedInJobLead {
        LinkedInJobLead(
            jobID: jobID,
            title: title,
            canonicalURL: LinkedInMCPImportService.canonicalJobURL(jobID: jobID)
        )
    }

    // MARK: - makeJobApp mapping

    func testMakeJobAppMapsTitleAndCanonicalURLOnly() throws {
        let jobApp = try XCTUnwrap(LinkedInMCPImportService.makeJobApp(from: makeLead()))

        XCTAssertEqual(jobApp.jobPosition, "Staff Physicist")
        XCTAssertEqual(jobApp.postingURL, "https://www.linkedin.com/jobs/view/4432291764/")
        XCTAssertEqual(jobApp.jobApplyLink, jobApp.postingURL)
        XCTAssertEqual(jobApp.source, "LinkedIn")
        XCTAssertEqual(jobApp.status, .new)
        XCTAssertEqual(jobApp.companyName, "",
                       "company is unknown at search time — it arrives at enrichment, never guessed")
        XCTAssertEqual(jobApp.jobDescription, "",
                       "search results carry no description — enrichment fetches the posting")
    }

    func testMakeJobAppRejectsBlankEssentials() {
        XCTAssertNil(LinkedInMCPImportService.makeJobApp(
            from: LinkedInJobLead(jobID: "", title: "Physicist", canonicalURL: "")
        ))
        XCTAssertNil(LinkedInMCPImportService.makeJobApp(
            from: LinkedInJobLead(jobID: "123", title: "", canonicalURL: "https://www.linkedin.com/jobs/view/123/")
        ))
    }

    // MARK: - importAsLead (two-stage pipeline + URL-only dedup)

    func testImportAsLeadInsertsNewLeadWithPreprocessingDeferred() throws {
        let store = makeJobAppStore()

        let outcome = LinkedInMCPImportService.importAsLead(makeLead(), into: store)

        guard case .imported(let inserted) = outcome else {
            return XCTFail("expected .imported, got \(outcome)")
        }
        XCTAssertEqual(store.jobApps.count, 1)
        XCTAssertEqual(inserted.status, .new)
        XCTAssertEqual(inserted.source, "LinkedIn")
        // deferringPreprocessing honored: nothing ran on the (empty) imported
        // description — the stored lead is exactly what the import wrote, and
        // enrichment (which no-ops under XCTest) owns preprocessing later.
        XCTAssertEqual(inserted.jobDescription, "")
    }

    func testImportSameCanonicalURLTwiceIsOneJobApp() throws {
        let store = makeJobAppStore()

        _ = LinkedInMCPImportService.importAsLead(makeLead(), into: store)
        let second = LinkedInMCPImportService.importAsLead(makeLead(), into: store)

        guard case .duplicate(let found) = second else {
            return XCTFail("expected .duplicate, got \(second)")
        }
        XCTAssertEqual(found.postingURL, "https://www.linkedin.com/jobs/view/4432291764/")
        XCTAssertEqual(store.jobApps.count, 1, "no copy inserted")
    }

    func testSameTitleDifferentJobsBothImport() throws {
        // The live spike capture listed two DISTINCT "Physicist" postings.
        // With company empty until enrichment, a title+company fallback match
        // would falsely collapse them — the canonical URL must be the only
        // dedup key.
        let store = makeJobAppStore()

        let first = LinkedInMCPImportService.importAsLead(
            makeLead(jobID: "4410464438", title: "Physicist"), into: store
        )
        let second = LinkedInMCPImportService.importAsLead(
            makeLead(jobID: "4417386528", title: "Physicist"), into: store
        )

        guard case .imported = first, case .imported = second else {
            return XCTFail("expected both .imported, got \(first) then \(second)")
        }
        XCTAssertEqual(store.jobApps.count, 2,
                       "two different postings with the same generic title are NOT duplicates")
    }

    // MARK: - Imported badge

    func testIsImportedKeysOffCanonicalURL() throws {
        let store = makeJobAppStore()
        _ = LinkedInMCPImportService.importAsLead(makeLead(), into: store)
        let importedURLs = JobMCPImportService.importedPostingURLs(in: store)

        XCTAssertTrue(LinkedInMCPImportService.isImported(makeLead(), importedURLs: importedURLs))
        XCTAssertFalse(LinkedInMCPImportService.isImported(
            makeLead(jobID: "4304469060", title: "Optics Engineer"),
            importedURLs: importedURLs
        ), "a different job id is a different posting")
    }
}
