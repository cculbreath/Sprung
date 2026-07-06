//
//  SiteJobSearchImportTests.swift
//  SprungTests
//
//  Import half of the agentic Custom Site job search
//  (SiteJobSearchService.makeJobApp / importAsLead / isImported) against an
//  in-memory JobAppStore. Pins that the flow rides the SAME two-stage lead
//  pipeline as the MCP boards:
//   - dedup through the shared JobAppStore.findDuplicateJobApp (URL first,
//     title+company fallback — see JobAppDedupTests for that contract)
//   - the lead lands as `.new` with the agent's page-verified summary as a
//     stand-in description (full-posting enrichment is deferred; the
//     enrichment queue itself no-ops under XCTest by design)
//   - canonical URLs are stored verbatim: no query-stripping normalization,
//     because on small boards the query string IS the posting's identity.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class SiteJobSearchImportTests: InMemoryStoreCase {

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

    private func makeListing(
        title: String = "Firmware Engineer",
        company: String = "Acme Robotics",
        url: String = "https://austinjobs.example.com/jobs/view?id=42",
        location: String? = "Austin, TX",
        salary: String? = "$140k–$165k",
        summary: String = "Ship embedded C++ on ARM Cortex targets for warehouse robots.",
        postedDate: String? = "July 2, 2026"
    ) -> SiteJobListing {
        SiteJobListing(
            title: title,
            company: company,
            url: url,
            location: location,
            salary: salary,
            summary: summary,
            postedDate: postedDate
        )
    }

    // MARK: - makeJobApp mapping

    func testMakeJobAppMapsVerifiedFieldsOntoLead() throws {
        let jobApp = try XCTUnwrap(
            SiteJobSearchService.makeJobApp(from: makeListing(), siteHost: "austinjobs.example.com")
        )
        XCTAssertEqual(jobApp.jobPosition, "Firmware Engineer")
        XCTAssertEqual(jobApp.companyName, "Acme Robotics")
        XCTAssertEqual(jobApp.jobLocation, "Austin, TX")
        XCTAssertEqual(jobApp.jobDescription,
                       "Ship embedded C++ on ARM Cortex targets for warehouse robots.",
                       "the agent's faithful summary is the stand-in description")
        XCTAssertEqual(jobApp.postingURL, "https://austinjobs.example.com/jobs/view?id=42",
                       "canonical URL stored verbatim — the ?id query is the posting's identity")
        XCTAssertEqual(jobApp.jobApplyLink, jobApp.postingURL)
        XCTAssertEqual(jobApp.salary, "$140k–$165k")
        XCTAssertEqual(jobApp.jobPostingTime, "July 2, 2026")
        XCTAssertEqual(jobApp.source, "austinjobs.example.com",
                       "the searched site labels the lead's source")
        XCTAssertEqual(jobApp.status, .new)
    }

    func testMakeJobAppHandlesNullLeaves() throws {
        let jobApp = try XCTUnwrap(SiteJobSearchService.makeJobApp(
            from: makeListing(location: nil, salary: nil, postedDate: nil),
            siteHost: "example.com"
        ))
        XCTAssertEqual(jobApp.jobLocation, "")
    }

    func testMakeJobAppRejectsBlankEssentials() {
        XCTAssertNil(SiteJobSearchService.makeJobApp(
            from: makeListing(title: "   "), siteHost: "example.com"
        ))
        XCTAssertNil(SiteJobSearchService.makeJobApp(
            from: makeListing(company: ""), siteHost: "example.com"
        ))
        XCTAssertNil(SiteJobSearchService.makeJobApp(
            from: makeListing(url: ""), siteHost: "example.com"
        ))
    }

    // MARK: - importAsLead (two-stage pipeline + shared dedup)

    func testImportAsLeadInsertsNewLead() throws {
        let store = makeJobAppStore()

        let outcome = SiteJobSearchService.importAsLead(
            makeListing(), siteHost: "austinjobs.example.com", into: store
        )

        guard case .imported(let inserted) = outcome else {
            return XCTFail("expected .imported, got \(outcome)")
        }
        XCTAssertEqual(store.jobApps.count, 1)
        XCTAssertEqual(inserted.status, .new)
        XCTAssertEqual(inserted.source, "austinjobs.example.com")
    }

    func testImportAsLeadDedupsByCanonicalURL() throws {
        let store = makeJobAppStore()
        let existing = JobApp(
            jobPosition: "Totally Different Title",
            companyName: "Some Other Company",
            postingURL: "https://austinjobs.example.com/jobs/view?id=42"
        )
        _ = store.addJobApp(existing)

        let outcome = SiteJobSearchService.importAsLead(
            makeListing(), siteHost: "austinjobs.example.com", into: store
        )

        guard case .duplicate(let found) = outcome else {
            return XCTFail("expected .duplicate, got \(outcome)")
        }
        XCTAssertEqual(found.persistentModelID, existing.persistentModelID)
        XCTAssertEqual(store.jobApps.count, 1, "no copy inserted")
    }

    func testImportAsLeadFallsBackToTitleCompanyDedup() throws {
        let store = makeJobAppStore()
        let existing = JobApp(
            jobPosition: "Firmware Engineer",
            companyName: "Acme Robotics",
            postingURL: "https://careers.acme.example.com/firmware"
        )
        _ = store.addJobApp(existing)

        // Same posting rediscovered under a different URL (e.g. the board's
        // detail page vs the employer's ATS page): title+company still catches it.
        let outcome = SiteJobSearchService.importAsLead(
            makeListing(url: "https://austinjobs.example.com/jobs/view?id=42"),
            siteHost: "austinjobs.example.com",
            into: store
        )

        guard case .duplicate(let found) = outcome else {
            return XCTFail("expected .duplicate, got \(outcome)")
        }
        XCTAssertEqual(found.persistentModelID, existing.persistentModelID)
    }

    func testImportAsLeadSkipsBlankEssentials() {
        let store = makeJobAppStore()
        let outcome = SiteJobSearchService.importAsLead(
            makeListing(title: " "), siteHost: "example.com", into: store
        )
        guard case .skipped(let reason) = outcome else {
            return XCTFail("expected .skipped, got \(outcome)")
        }
        XCTAssertTrue(reason.contains("missing title, company, or URL"))
        XCTAssertTrue(store.jobApps.isEmpty)
    }

    // MARK: - Imported badge

    func testIsImportedKeysOffRawURLWithoutNormalization() throws {
        let store = makeJobAppStore()
        _ = SiteJobSearchService.importAsLead(
            makeListing(), siteHost: "austinjobs.example.com", into: store
        )
        let importedURLs = JobMCPImportService.importedPostingURLs(in: store)

        XCTAssertTrue(SiteJobSearchService.isImported(makeListing(), importedURLs: importedURLs))
        XCTAssertFalse(SiteJobSearchService.isImported(
            makeListing(url: "https://austinjobs.example.com/jobs/view?id=43"),
            importedURLs: importedURLs
        ), "a different query string is a different posting — no query-stripping on small boards")
    }
}
