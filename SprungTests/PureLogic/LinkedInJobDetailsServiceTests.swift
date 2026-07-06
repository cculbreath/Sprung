//
//  LinkedInJobDetailsServiceTests.swift
//  SprungTests
//
//  Pins the pure halves of the LinkedIn MCP detail path
//  (Sprung/JobApplications/LinkedIn/LinkedInJobDetailsService.swift):
//
//   1. `jobId(fromURL:)` — the URL → numeric-id extraction that decides
//      whether a pasted linkedin.com URL takes the MCP details path or routes
//      through the generic URL importer (`/jobs/view/<id>/` forms, slug
//      forms, and `currentJobId=<id>` query forms).
//   2. `postingText(fromResultText:)` — the `get_job_details` result payload
//      decode (a JSON-serialized text content block, shape captured live in
//      plans/linkedin-spike-fixtures/job_details.json).
//
//  The auth-failure classifier, canonical job URL, and hourly call budget are
//  shared with the search board and pinned by LinkedInMCPImportServiceTests —
//  only the seams between the two services are covered here.
//

import XCTest
@testable import Sprung

final class LinkedInJobDetailsServiceTests: XCTestCase {

    // MARK: - jobId(fromURL:) — /jobs/view/ forms

    func testPlainJobViewURLWithTrailingSlash() {
        XCTAssertEqual(
            LinkedInJobDetailsService.jobId(fromURL: "https://www.linkedin.com/jobs/view/4432291764/"),
            "4432291764"
        )
    }

    func testPlainJobViewURLWithoutTrailingSlash() {
        XCTAssertEqual(
            LinkedInJobDetailsService.jobId(fromURL: "https://www.linkedin.com/jobs/view/4261198037"),
            "4261198037"
        )
    }

    func testJobViewURLWithQueryString() {
        XCTAssertEqual(
            LinkedInJobDetailsService.jobId(
                fromURL: "https://www.linkedin.com/jobs/view/4432291764/?alternateChannel=search&refId=abc%3D%3D"
            ),
            "4432291764"
        )
    }

    func testJobViewURLWithTrailingSegments() {
        XCTAssertEqual(
            LinkedInJobDetailsService.jobId(fromURL: "https://www.linkedin.com/jobs/view/4432291764/apply/"),
            "4432291764"
        )
    }

    func testSlugJobViewURLYieldsTrailingId() {
        XCTAssertEqual(
            LinkedInJobDetailsService.jobId(
                fromURL: "https://www.linkedin.com/jobs/view/research-engineer-applied-scientist-at-mathpix-4432291764/"
            ),
            "4432291764"
        )
    }

    func testBareLinkedInHostWithoutWWW() {
        XCTAssertEqual(
            LinkedInJobDetailsService.jobId(fromURL: "https://linkedin.com/jobs/view/12345678/"),
            "12345678"
        )
    }

    // MARK: - jobId(fromURL:) — currentJobId query forms

    func testCurrentJobIdOnSearchPage() {
        XCTAssertEqual(
            LinkedInJobDetailsService.jobId(
                fromURL: "https://www.linkedin.com/jobs/search/?currentJobId=4432291764&keywords=physics&origin=JOB_SEARCH"
            ),
            "4432291764"
        )
    }

    func testCurrentJobIdOnCollectionsPage() {
        XCTAssertEqual(
            LinkedInJobDetailsService.jobId(
                fromURL: "https://www.linkedin.com/jobs/collections/recommended/?currentJobId=4261198037"
            ),
            "4261198037"
        )
    }

    func testNonNumericCurrentJobIdYieldsNil() {
        XCTAssertNil(
            LinkedInJobDetailsService.jobId(fromURL: "https://www.linkedin.com/jobs/search/?currentJobId=abc123")
        )
    }

    // MARK: - jobId(fromURL:) — non-job URLs route generic

    func testCompanyPageYieldsNil() {
        XCTAssertNil(LinkedInJobDetailsService.jobId(fromURL: "https://www.linkedin.com/company/mathpix/"))
    }

    func testFeedURLYieldsNil() {
        XCTAssertNil(LinkedInJobDetailsService.jobId(fromURL: "https://www.linkedin.com/feed/"))
    }

    func testViewSegmentOutsideJobsYieldsNil() {
        // "view" must follow "jobs" — a bare /view/<n>/ path is not a job URL.
        XCTAssertNil(LinkedInJobDetailsService.jobId(fromURL: "https://www.linkedin.com/posts/view/12345678/"))
    }

    func testJobsViewWithNoIdSegmentYieldsNil() {
        XCTAssertNil(LinkedInJobDetailsService.jobId(fromURL: "https://www.linkedin.com/jobs/view/"))
    }

    func testJobsViewWithNonNumericSegmentYieldsNil() {
        XCTAssertNil(LinkedInJobDetailsService.jobId(fromURL: "https://www.linkedin.com/jobs/view/apply/"))
    }

    func testUnparseableURLYieldsNil() {
        XCTAssertNil(LinkedInJobDetailsService.jobId(fromURL: "not a url at all"))
    }

    // MARK: - Seam with the search board's canonical URL

    func testCanonicalJobURLRoundTripsThroughJobIdExtraction() {
        // The canonical URL a stored lead carries (built by the search board)
        // must re-extract to the same id — this is what routes enrichment's
        // LinkedIn path and dedups pasted URLs against board-imported leads.
        let canonical = LinkedInMCPImportService.canonicalJobURL(jobID: "987654321")
        XCTAssertEqual(LinkedInJobDetailsService.jobId(fromURL: canonical), "987654321")
    }

    func testNoSessionErrorCarriesTheSingleDoctrineMessage() {
        // One auth state, one string — shared with the search board.
        XCTAssertEqual(
            LinkedInJobDetailsError.noSession.errorDescription,
            LinkedInMCPImportService.noSessionMessage
        )
    }

    // MARK: - postingText(fromResultText:)

    /// Mirrors the live fixture shape (plans/linkedin-spike-fixtures/
    /// job_details.json): url + sections map + job_ids + references, with the
    /// posting's raw innerText under sections.job_posting.
    private let fixtureShapedResult = """
    {"url":"https://www.linkedin.com/jobs/view/4432291764/","sections":{"job_posting":"Mathpix\\n\\nResearch Engineer / Applied Scientist\\n\\nAbout the job\\n\\nDesign and run large-scale computational experiments."},"job_ids":["4432291764"],"references":{"job_posting":[{"kind":"job","url":"https://www.linkedin.com/jobs/view/4432291764/","text":"Research Engineer"}]}}
    """

    func testExtractsJobPostingSectionFromFixtureShapedPayload() throws {
        let posting = try LinkedInJobDetailsService.postingText(fromResultText: fixtureShapedResult)
        XCTAssertTrue(posting.hasPrefix("Mathpix"))
        XCTAssertTrue(posting.contains("Design and run large-scale computational experiments."))
    }

    func testMissingJobPostingSectionThrows() {
        let payload = #"{"url":"https://www.linkedin.com/jobs/view/1/","sections":{"other":"text"},"job_ids":[]}"#
        XCTAssertThrowsError(try LinkedInJobDetailsService.postingText(fromResultText: payload)) { error in
            guard case LinkedInJobDetailsError.missingPostingSection = error else {
                return XCTFail("Expected .missingPostingSection, got \(error)")
            }
        }
    }

    func testWhitespaceOnlyJobPostingSectionThrows() {
        let payload = #"{"sections":{"job_posting":"  \n  "}}"#
        XCTAssertThrowsError(try LinkedInJobDetailsService.postingText(fromResultText: payload)) { error in
            guard case LinkedInJobDetailsError.missingPostingSection = error else {
                return XCTFail("Expected .missingPostingSection, got \(error)")
            }
        }
    }

    func testMalformedJSONThrowsMalformedPayload() {
        XCTAssertThrowsError(try LinkedInJobDetailsService.postingText(fromResultText: "{ not json")) { error in
            guard case LinkedInJobDetailsError.malformedPayload = error else {
                return XCTFail("Expected .malformedPayload, got \(error)")
            }
        }
    }
}
