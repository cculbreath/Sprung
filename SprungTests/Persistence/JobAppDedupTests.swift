//
//  JobAppDedupTests.swift
//  SprungTests
//
//  Pins the contract of `JobAppStore.findDuplicateJobApp(url:title:company:)` —
//  the shared dedup check used by the generic URL importer (NewAppSheetView's
//  LLM/LinkedIn paths) and JobMCPImportService's Dice/ZipRecruiter
//  `importAsLead` paths (see call sites in
//  Sprung/JobApplications/Views/NewAppSheetView.swift and
//  Sprung/JobApplications/MCP/JobMCPImportService.swift).
//
//  Contract (from JobAppStore.swift doc comment + implementation):
//   1. `postingURL` equality is checked first, but ONLY when `url` is
//      non-nil and non-empty (callers like ZipRecruiter's unstable
//      `job_redirect_url` pass `nil` to skip this branch entirely).
//   2. Falls back to an exact `jobPosition == title && companyName == company`
//      match.
//   3. Comparisons are plain Swift `String ==`, i.e. case-sensitive, no
//      trimming/normalization of any kind.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class JobAppDedupTests: InMemoryStoreCase {

    /// Builds the full store dependency chain bound to the test context,
    /// mirroring DependentStoresTests.makeStores() (JobAppStore requires a
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

    // MARK: - 1. URL match wins regardless of title/company

    func testURLMatchFoundRegardlessOfTitleOrCompanyDifferences() throws {
        let store = makeJobAppStore()
        let existing = JobApp(
            jobPosition: "Staff Engineer",
            companyName: "Acme Corp",
            postingURL: "https://boards.example.com/jobs/123"
        )
        _ = store.addJobApp(existing)

        // Title and company passed to the lookup are totally different from
        // what's stored — URL equality alone should still find it.
        let found = store.findDuplicateJobApp(
            url: "https://boards.example.com/jobs/123",
            title: "Completely Different Title",
            company: "Some Other Company"
        )

        XCTAssertEqual(found?.persistentModelID, existing.persistentModelID)
    }

    // MARK: - 2. Title+company fallback

    func testNilURLFallsBackToExactTitleAndCompanyMatch() throws {
        let store = makeJobAppStore()
        let existing = JobApp(
            jobPosition: "Senior Backend Engineer",
            companyName: "Widget LLC",
            postingURL: ""
        )
        _ = store.addJobApp(existing)

        let found = store.findDuplicateJobApp(
            url: nil,
            title: "Senior Backend Engineer",
            company: "Widget LLC"
        )

        XCTAssertEqual(found?.persistentModelID, existing.persistentModelID)
    }

    func testEmptyStringURLAlsoFallsBackToTitleAndCompanyMatch() throws {
        // Empty string url must be treated the same as nil (guard is
        // `!url.isEmpty`), even though the stored record's own postingURL is
        // also "" by default — the empty string must not be used to match on
        // URL at all, only to trigger the title+company fallback.
        let store = makeJobAppStore()
        let existing = JobApp(
            jobPosition: "Data Scientist",
            companyName: "Initech",
            postingURL: ""
        )
        _ = store.addJobApp(existing)

        let found = store.findDuplicateJobApp(
            url: "",
            title: "Data Scientist",
            company: "Initech"
        )

        XCTAssertEqual(found?.persistentModelID, existing.persistentModelID)
    }

    func testTitleCompanyNearMissOnCompanyIsNotFound() throws {
        let store = makeJobAppStore()
        let existing = JobApp(
            jobPosition: "Product Manager",
            companyName: "Globex",
            postingURL: ""
        )
        _ = store.addJobApp(existing)

        let found = store.findDuplicateJobApp(
            url: nil,
            title: "Product Manager",
            company: "Umbrella Corp" // different company
        )

        XCTAssertNil(found)
    }

    func testTitleCompanyNearMissOnTitleIsNotFound() throws {
        let store = makeJobAppStore()
        let existing = JobApp(
            jobPosition: "Product Manager",
            companyName: "Globex",
            postingURL: ""
        )
        _ = store.addJobApp(existing)

        let found = store.findDuplicateJobApp(
            url: nil,
            title: "Associate Product Manager", // different title
            company: "Globex"
        )

        XCTAssertNil(found)
    }

    // MARK: - 3. URL match precedence over a different record's title+company match

    func testURLMatchTakesPrecedenceOverADifferentTitleCompanyMatch() throws {
        let store = makeJobAppStore()

        // Record A only matches by URL.
        let recordA = JobApp(
            jobPosition: "Foo Role",
            companyName: "Foo Co",
            postingURL: "https://boards.example.com/jobs/aaa"
        )
        // Record B only matches by title+company (no URL of its own).
        let recordB = JobApp(
            jobPosition: "Bar Role",
            companyName: "Bar Co",
            postingURL: ""
        )
        _ = store.addJobApp(recordA)
        _ = store.addJobApp(recordB)

        // Look up with A's URL but B's title+company — the implementation
        // checks the URL branch first and returns on that match without ever
        // evaluating the title+company branch, so A wins even though B is
        // also a "matching" record for the title/company given.
        let found = store.findDuplicateJobApp(
            url: "https://boards.example.com/jobs/aaa",
            title: "Bar Role",
            company: "Bar Co"
        )

        XCTAssertEqual(found?.persistentModelID, recordA.persistentModelID)
    }

    // MARK: - 4. Empty store

    func testEmptyStoreReturnsNilForAnyLookup() throws {
        let store = makeJobAppStore()

        XCTAssertNil(store.findDuplicateJobApp(url: "https://example.com/x", title: "T", company: "C"))
        XCTAssertNil(store.findDuplicateJobApp(url: nil, title: "T", company: "C"))
    }

    // MARK: - Case sensitivity (pinned as implemented — plain String ==, no normalization)

    func testURLMatchIsCaseSensitiveAsImplemented() throws {
        let store = makeJobAppStore()
        let existing = JobApp(
            jobPosition: "QA Engineer",
            companyName: "Hooli",
            postingURL: "https://boards.example.com/JOBS/123"
        )
        _ = store.addJobApp(existing)

        // Differently-cased URL (lowercase "jobs" vs stored "JOBS"), paired
        // with title/company that also don't match — isolates that the URL
        // branch itself is a plain, case-sensitive `==` with no
        // normalization, so neither branch fires and the lookup misses.
        let found = store.findDuplicateJobApp(
            url: "https://boards.example.com/jobs/123",
            title: "Some Other Title",
            company: "Some Other Company"
        )

        XCTAssertNil(found)
    }

    func testTitleAndCompanyMatchAreCaseSensitiveAsImplemented() throws {
        let store = makeJobAppStore()
        let existing = JobApp(
            jobPosition: "Site Reliability Engineer",
            companyName: "Massive Dynamic",
            postingURL: ""
        )
        _ = store.addJobApp(existing)

        // Differently-cased title/company, with no URL to fall back on
        // (nil), does NOT match — String equality is case-sensitive and the
        // implementation performs no case-folding or trimming.
        let found = store.findDuplicateJobApp(
            url: nil,
            title: "site reliability engineer",
            company: "massive dynamic"
        )

        XCTAssertNil(found)
    }
}
