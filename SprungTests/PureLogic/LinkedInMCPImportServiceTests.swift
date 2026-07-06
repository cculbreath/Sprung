//
//  LinkedInMCPImportServiceTests.swift
//  SprungTests
//
//  Pure halves of the LinkedIn MCP search board
//  (Sprung/JobApplications/LinkedIn/LinkedInMCPImportService.swift):
//
//   - `searchArguments` emits the server's EXTERNAL snake_case wire verbatim
//     (keys we don't control), with `max_pages` hard-defaulting to 1 (risk
//     rail) and blank optionals omitted.
//   - `decodeSearchResults` parses the JSON-serialized text content block
//     ({url, sections, job_ids, references}) — titles matched from
//     references of kind "job" by id-in-url (relative OR absolute), ids
//     without a match kept with a placeholder title (logged, never dropped),
//     a missing `job_ids` array loudly malformed, an empty one an honest
//     zero-result search.
//   - the auth-failure classifier maps session/authentication language in
//     tool errors to the single "sign in in your browser" state — and
//     nothing else (rate limits, DOM churn stay ordinary failures).
//   - `LinkedInCallBudget` — the rolling hourly call cap — counts, exhausts,
//     prunes out-of-window timestamps, and persists across instances.
//
//  The decode fixture is SANITIZED from the live spike capture
//  (plans/linkedin-spike-fixtures/search_jobs_austin.json): same shape and
//  key spelling, neutral titles/companies, personalized fragments (viewed
//  markers, premium promos, salary history, real profiles) redacted.
//

import XCTest
@testable import Sprung

final class LinkedInMCPImportServiceTests: XCTestCase {

    // MARK: - Fixture (sanitized; real payload shape)

    /// The text content block of a `search_jobs` result. Notable structure,
    /// mirroring the live capture: reference urls are RELATIVE
    /// ("/jobs/view/<id>/") except one absolute; non-job references
    /// (company/person/external) are interleaved; the last job id has no
    /// matching job reference (count mismatch); the external reference's url
    /// would string-match that id, proving the kind filter is load-bearing.
    private let sanitizedSearchText = #"""
    {"url":"https://www.linkedin.com/jobs/search/?keywords=physicist&location=Example+City","sections":{"search_results":"physicist in Example City\n4 results\nSet alert\nStaff Physicist\nExample Labs\nExample City (Remote)\nActively reviewing applicants\nEasy Apply\nOptics Engineer\nSample Optics\nExample City\n1 week ago\nComputational Scientist\nNeutral Research\nUnited States (Remote)\nBe an early applicant\nAre these results helpful?\n1\n2\nNext"},"job_ids":["4432291764","4304469060","4410464438","9999999999"],"references":{"search_results":[{"kind":"job","url":"/jobs/view/4432291764/","text":"Staff Physicist","context":"job result"},{"kind":"job","url":"https://www.linkedin.com/jobs/view/4304469060/","text":"Optics Engineer","context":"job result"},{"kind":"job","url":"/jobs/view/4410464438/","text":"Computational Scientist","context":"job result"},{"kind":"company","url":"/company/example-labs/","text":"Example Labs logo","context":"search result"},{"kind":"person","url":"/in/redacted-profile/","text":"Redacted profile graphic","context":"search result"},{"kind":"external","url":"https://example.com/jobs/view/9999999999/","text":"Careers at Example Labs","context":"search result"}]}}
    """#

    // MARK: - searchArguments wire shape

    func testSearchArgumentsFullWireShape() {
        let arguments = LinkedInMCPImportService.searchArguments(
            keywords: "staff physicist",
            location: "Austin, TX",
            datePosted: .pastWeek,
            workTypes: [.onSite, .remote],
            maxPages: 2
        )

        XCTAssertEqual(
            Set(arguments.keys),
            ["keywords", "location", "date_posted", "work_type", "max_pages"],
            "snake_case keys verbatim — the server's external wire, never ours"
        )
        XCTAssertEqual(arguments["keywords"] as? String, "staff physicist")
        XCTAssertEqual(arguments["location"] as? String, "Austin, TX")
        XCTAssertEqual(arguments["date_posted"] as? String, "past_week")
        XCTAssertEqual(arguments["work_type"] as? String, "on_site,remote",
                       "work types are comma-separated on the wire")
        XCTAssertEqual(arguments["max_pages"] as? Int, 2)
    }

    func testSearchArgumentsDefaultToOnePageAndOmitBlankOptionals() {
        let arguments = LinkedInMCPImportService.searchArguments(
            keywords: "  swift engineer  ",
            location: "   "
        )

        XCTAssertEqual(Set(arguments.keys), ["keywords", "max_pages"],
                       "blank location, nil date_posted, and empty work types are omitted, not sent empty")
        XCTAssertEqual(arguments["keywords"] as? String, "swift engineer",
                       "keywords are trimmed")
        XCTAssertEqual(arguments["max_pages"] as? Int, 1,
                       "risk rail: max_pages hard-defaults to 1")
    }

    func testDatePostedWireValues() {
        XCTAssertEqual(
            LinkedInDatePosted.allCases.map(\.rawValue),
            ["past_hour", "past_24_hours", "past_week", "past_month"]
        )
    }

    func testWorkTypeWireValues() {
        XCTAssertEqual(
            LinkedInWorkType.allCases.map(\.rawValue),
            ["on_site", "remote", "hybrid"]
        )
    }

    // MARK: - Canonical URL

    func testCanonicalJobURL() {
        XCTAssertEqual(
            LinkedInMCPImportService.canonicalJobURL(jobID: "4432291764"),
            "https://www.linkedin.com/jobs/view/4432291764/"
        )
    }

    // MARK: - decodeSearchResults

    func testDecodeMatchesTitlesFromJobReferencesInJobIdOrder() throws {
        let leads = try LinkedInMCPImportService.decodeSearchResults(from: sanitizedSearchText)

        XCTAssertEqual(leads.count, 4, "every job_ids entry becomes a lead")
        XCTAssertEqual(leads[0].jobID, "4432291764")
        XCTAssertEqual(leads[0].title, "Staff Physicist",
                       "matched from the relative-url job reference")
        XCTAssertEqual(leads[0].canonicalURL, "https://www.linkedin.com/jobs/view/4432291764/")
        XCTAssertEqual(leads[1].title, "Optics Engineer",
                       "an absolute reference url also matches by id-in-url")
        XCTAssertEqual(leads[2].title, "Computational Scientist")
    }

    func testDecodeKeepsUnmatchedIdWithPlaceholderTitleNeverDrops() throws {
        let leads = try LinkedInMCPImportService.decodeSearchResults(from: sanitizedSearchText)

        let unmatched = try XCTUnwrap(leads.last)
        XCTAssertEqual(unmatched.jobID, "9999999999")
        XCTAssertEqual(unmatched.title, "LinkedIn job 9999999999",
                       """
                       an id with no matching job reference keeps a placeholder \
                       title — the external reference whose url contains the id \
                       must NOT be used (kind filter), and the id must not be \
                       silently dropped
                       """)
        XCTAssertEqual(unmatched.canonicalURL, "https://www.linkedin.com/jobs/view/9999999999/")
    }

    func testDecodeThrowsOnMalformedJSON() {
        XCTAssertThrowsError(
            try LinkedInMCPImportService.decodeSearchResults(from: "LinkedIn is down")
        ) { error in
            guard case JobMCPImportError.malformedPayload = error else {
                return XCTFail("expected .malformedPayload, got \(error)")
            }
        }
    }

    func testDecodeThrowsWhenJobIdsArrayMissing() {
        // A payload without job_ids means the server's scrape shape changed —
        // that must surface loudly, never read as an honest empty search.
        let payload = #"{"url":"https://www.linkedin.com/jobs/search/","sections":{"search_results":"nothing"}}"#
        XCTAssertThrowsError(
            try LinkedInMCPImportService.decodeSearchResults(from: payload)
        ) { error in
            guard case JobMCPImportError.malformedPayload = error else {
                return XCTFail("expected .malformedPayload, got \(error)")
            }
        }
    }

    func testDecodeEmptyJobIdsIsHonestZeroResults() throws {
        let payload = #"{"url":"https://www.linkedin.com/jobs/search/","sections":{"search_results":"No matching jobs found"},"job_ids":[],"references":{}}"#
        XCTAssertEqual(try LinkedInMCPImportService.decodeSearchResults(from: payload), [])
    }

    // MARK: - Auth-failure classification

    func testAuthFailureMatchesSessionAndAuthenticationLanguage() {
        XCTAssertTrue(LinkedInMCPImportService.isAuthFailure(
            MCPClientError.toolError("AuthenticationError: Session expired or invalid")
        ))
        XCTAssertTrue(LinkedInMCPImportService.isAuthFailure(
            MCPClientError.toolError("Please sign in to LinkedIn to continue")
        ))
        XCTAssertTrue(LinkedInMCPImportService.isAuthFailure(
            MCPClientError.jsonRPCError(code: -32000, message: "No valid session — log in required")
        ))
    }

    func testAuthFailureIgnoresOrdinaryToolFailures() {
        XCTAssertFalse(LinkedInMCPImportService.isAuthFailure(
            MCPClientError.toolError("RateLimitError: LinkedIn returned a checkpoint page")
        ), "rate limits are ordinary failures, not the missing-session state")
        XCTAssertFalse(LinkedInMCPImportService.isAuthFailure(
            MCPClientError.httpError(statusCode: 500, body: "session backend crashed")
        ), "transport failures are never classified as auth — only tool/JSON-RPC results")
        XCTAssertFalse(LinkedInMCPImportService.isAuthFailure(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        ))
    }

    // MARK: - Rolling hourly call budget

    func testBudgetCountsDownWithinWindow() {
        let defaults = TestDefaults()
        var currentDate = Date(timeIntervalSince1970: 1_000_000)
        let budget = LinkedInCallBudget(limit: 3, defaults: defaults.store, now: { currentDate })

        XCTAssertEqual(budget.remainingCalls(), 3)
        budget.recordCall()
        currentDate += 60
        budget.recordCall()
        XCTAssertEqual(budget.remainingCalls(), 1)
        XCTAssertFalse(budget.isExhausted)
        XCTAssertNil(budget.nextAvailableDate(), "no wait time while calls remain")
    }

    func testBudgetExhaustsAtLimitAndReportsNextAvailable() {
        let defaults = TestDefaults()
        let start = Date(timeIntervalSince1970: 1_000_000)
        var currentDate = start
        let budget = LinkedInCallBudget(limit: 2, defaults: defaults.store, now: { currentDate })

        budget.recordCall()
        currentDate += 120
        budget.recordCall()

        XCTAssertTrue(budget.isExhausted)
        XCTAssertEqual(budget.remainingCalls(), 0)
        XCTAssertEqual(budget.nextAvailableDate(), start.addingTimeInterval(3600),
                       "a call frees up when the OLDEST in-window call ages out")
    }

    func testBudgetPrunesTimestampsOlderThanOneHour() {
        let defaults = TestDefaults()
        let start = Date(timeIntervalSince1970: 1_000_000)
        var currentDate = start
        let budget = LinkedInCallBudget(limit: 2, defaults: defaults.store, now: { currentDate })

        budget.recordCall()
        budget.recordCall()
        XCTAssertTrue(budget.isExhausted)

        currentDate = start.addingTimeInterval(3601)
        XCTAssertEqual(budget.remainingCalls(), 2, "out-of-window calls no longer count")
        XCTAssertFalse(budget.isExhausted)

        budget.recordCall()
        let stored = defaults.store.array(forKey: LinkedInCallBudget.timestampsKey) as? [Double]
        XCTAssertEqual(stored?.count, 1,
                       "recording rewrites the persisted list pruned to the window")
    }

    func testBudgetPersistsAcrossInstances() {
        let defaults = TestDefaults()
        let currentDate = Date(timeIntervalSince1970: 1_000_000)
        let first = LinkedInCallBudget(limit: 5, defaults: defaults.store, now: { currentDate })
        first.recordCall()
        first.recordCall()

        let second = LinkedInCallBudget(limit: 5, defaults: defaults.store, now: { currentDate })
        XCTAssertEqual(second.remainingCalls(), 3,
                       "the cap holds across sheet sessions — timestamps live in defaults, not the instance")
    }

    func testBudgetDefaultsToThirtyPerHour() {
        XCTAssertEqual(LinkedInCallBudget.defaultLimit, 30)
        XCTAssertEqual(LinkedInCallBudget.window, 3600)
    }
}
