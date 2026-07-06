//
//  JobLeadEnrichmentSeamTests.swift
//  SprungTests
//
//  Pins the MCP lead-import → enrichment → preprocessing seam
//  (Sprung/JobApplications/MCP/JobMCPImportService.swift +
//  JobAppStore.addJobApp(_:deferringPreprocessing:)):
//
//   1. `importAsLead` lands a `.new` lead INSTANTLY with the board's raw
//      description (Dice's truncated `summary`; empty for ZipRecruiter) and
//      preprocessing DEFERRED — nothing runs on the truncated text at import
//      time. Full-posting enrichment is queued to `JobLeadEnrichmentService`,
//      which never fires under XCTest (its `isRunningUnitTests` guard —
//      automatic LLM/network work must not run in the suite), so the stored
//      description here is exactly what the import wrote.
//   2. `acceptedFullDescription(_:current:)` — the pure quality gate for a
//      fetched description — rejects empty/filler text and anything not
//      strictly longer than what's stored (a Dice summary is a truncation of
//      the real posting, so a legitimate fetch is always longer).
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class JobLeadEnrichmentSeamTests: InMemoryStoreCase {

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

    private func makeDiceResult(summary: String?) -> DiceJobResult {
        DiceJobResult(
            id: "dice-1",
            title: "Staff Engineer",
            summary: summary,
            postedDate: nil,
            jobLocation: DiceJobResult.Location(displayName: "Austin, TX"),
            detailsPageUrl: "https://www.dice.com/job-detail/abc-123?utm_source=partner",
            salary: nil,
            companyName: "Acme Corp",
            employmentType: nil,
            employerType: nil,
            workplaceTypes: nil,
            easyApply: nil,
            willingToSponsor: nil
        )
    }

    private func makeZipResult() -> JobMCPImportService.ZipRecruiterJobResult {
        JobMCPImportService.ZipRecruiterJobResult(
            title: "Machinist",
            company: "Widget Works",
            location: "Portland, OR",
            isRemote: false,
            salary: nil,
            companyLogo: nil,
            jobRedirectUrl: "https://www.ziprecruiter.com/jobs/redirect?token=xyz",
            jobType: nil,
            benefits: nil,
            daysAgo: nil
        )
    }

    // MARK: - 1. Import lands instantly, preprocessing deferred

    func testDiceImportLandsInstantlyOnTruncatedSummaryWithPreprocessingDeferred() throws {
        let store = makeJobAppStore()
        let summary = "Truncated ~500-char Dice summary of the real posting."

        let outcome = JobMCPImportService.importAsLead(makeDiceResult(summary: summary), into: store)

        guard case .imported(let lead) = outcome else {
            return XCTFail("Expected .imported, got \(outcome)")
        }
        // The lead is usable immediately — the user never waits on enrichment.
        XCTAssertEqual(lead.status, .new)
        XCTAssertEqual(lead.jobDescription, summary)
        // Preprocessing was deferred: nothing ran on the truncated summary.
        XCTAssertNil(lead.extractedRequirements)
        XCTAssertNil(lead.relevantCardIds)
        XCTAssertFalse(lead.hasPreprocessingComplete)
    }

    func testZipRecruiterImportLandsInstantlyWithEmptyDescription() throws {
        let store = makeJobAppStore()

        let outcome = JobMCPImportService.importAsLead(makeZipResult(), into: store)

        guard case .imported(let lead) = outcome else {
            return XCTFail("Expected .imported, got \(outcome)")
        }
        // ZipRecruiter search results carry no description at all; the lead
        // lands with an empty one until background enrichment fills it in.
        XCTAssertEqual(lead.jobDescription, "")
        XCTAssertFalse(lead.hasPreprocessingComplete)
    }

    func testAddJobAppDefaultStillInsertsAndSelects() throws {
        // The `deferringPreprocessing` parameter defaults to false, so every
        // pre-existing caller (Apple/Indeed scrapes, NewAppSheetView)
        // keeps its behavior: insert, persist, select.
        let store = makeJobAppStore()
        let job = JobApp(jobPosition: "Welder", companyName: "Forge Co")

        let added = store.addJobApp(job)

        XCTAssertNotNil(added)
        XCTAssertEqual(store.selectedApp?.persistentModelID, job.persistentModelID)
        XCTAssertEqual(store.jobApps.count, 1)
    }

    // MARK: - 2. acceptedFullDescription quality gate (pure half)

    func testRejectsEmptyAndWhitespaceOnlyFetch() {
        XCTAssertNil(JobLeadEnrichmentService.acceptedFullDescription("", current: ""))
        XCTAssertNil(JobLeadEnrichmentService.acceptedFullDescription("   \n\t ", current: ""))
    }

    func testRejectsNotSpecifiedFillerCaseInsensitively() {
        // JobURLImportService's system prompt instructs the extractor to emit
        // "Not specified" for missing fields — that's filler, not a posting.
        XCTAssertNil(JobLeadEnrichmentService.acceptedFullDescription("Not specified", current: ""))
        XCTAssertNil(JobLeadEnrichmentService.acceptedFullDescription("  not specified  ", current: ""))
        XCTAssertNil(JobLeadEnrichmentService.acceptedFullDescription("NOT SPECIFIED", current: ""))
    }

    func testRejectsFetchNotStrictlyLongerThanCurrentSummary() {
        let summary = "A truncated summary of the real job posting text."
        // Equal length (the identical text) — no improvement.
        XCTAssertNil(JobLeadEnrichmentService.acceptedFullDescription(summary, current: summary))
        // Shorter — the extractor hit a bot wall or the wrong page; the
        // summary is the higher-quality input, keep it.
        XCTAssertNil(JobLeadEnrichmentService.acceptedFullDescription("Login required.", current: summary))
    }

    func testAcceptsStrictlyLongerFetchAndTrimsIt() {
        let summary = "Short summary."
        let full = "\n  The complete posting with responsibilities, requirements, and benefits.  \n"
        let accepted = JobLeadEnrichmentService.acceptedFullDescription(full, current: summary)
        XCTAssertEqual(
            accepted,
            "The complete posting with responsibilities, requirements, and benefits."
        )
    }

    func testAcceptsAnyRealTextWhenCurrentDescriptionIsEmpty() {
        // The ZipRecruiter case: no summary at all, so any genuine description
        // is an improvement.
        XCTAssertEqual(
            JobLeadEnrichmentService.acceptedFullDescription("Operate CNC mills.", current: ""),
            "Operate CNC mills."
        )
        // Whitespace-only current counts as empty too (trimmed comparison).
        XCTAssertEqual(
            JobLeadEnrichmentService.acceptedFullDescription("Operate CNC mills.", current: "  \n"),
            "Operate CNC mills."
        )
    }

    // MARK: - 3. Enrichment host routing (pure half)

    func testLinkedInHostsRouteToTheMCPDetailsPath() {
        // linkedin.com leads must never take the OpenAI web-fetch path — it
        // dead-ends at LinkedIn's authwall.
        XCTAssertTrue(JobLeadEnrichmentService.isLinkedInPostingHost("www.linkedin.com"))
        XCTAssertTrue(JobLeadEnrichmentService.isLinkedInPostingHost("linkedin.com"))
        // Host matching is case-insensitive.
        XCTAssertTrue(JobLeadEnrichmentService.isLinkedInPostingHost("WWW.LinkedIn.com"))
    }

    func testNonLinkedInHostsRouteToTheWebSearchPath() {
        XCTAssertFalse(JobLeadEnrichmentService.isLinkedInPostingHost(nil))
        XCTAssertFalse(JobLeadEnrichmentService.isLinkedInPostingHost("www.dice.com"))
        XCTAssertFalse(JobLeadEnrichmentService.isLinkedInPostingHost("api.ziprecruiter.com"))
        // Lookalike hosts must not match — the suffix check requires a real
        // subdomain boundary.
        XCTAssertFalse(JobLeadEnrichmentService.isLinkedInPostingHost("notlinkedin.com"))
        XCTAssertFalse(JobLeadEnrichmentService.isLinkedInPostingHost("linkedin.com.evil.example"))
    }
}
