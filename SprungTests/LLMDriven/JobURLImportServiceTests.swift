//
//  JobURLImportServiceTests.swift
//  SprungTests
//
//  Covers the response-parse half of the URL job-import flow, extracted out of
//  NewAppSheetView so it is testable. parseJob(from:sourceURL:) is the pure
//  JSON → JobApp mapping (the live OpenAI streaming half is not unit-testable).
//

import XCTest
@testable import Sprung

@MainActor
final class JobURLImportServiceTests: XCTestCase {

    private let sourceURL = "https://example.com/jobs/123"

    private func validJSON(applyLink: String = "https://apply.example.com",
                           salary: String = "$150k–$180k",
                           workplaceType: String = "Remote",
                           employmentType: String = "Full-time") -> String {
        """
        {
          "job_title": "Staff Engineer",
          "company": "Acme Corp",
          "location": "Austin, TX",
          "workplace_type": "\(workplaceType)",
          "employment_type": "\(employmentType)",
          "seniority_level": "Staff",
          "industries": "Software",
          "posted_date": "2 days ago",
          "salary": "\(salary)",
          "job_description": "Build things.",
          "apply_link": "\(applyLink)"
        }
        """
    }

    func testParsesAllCoreFields() throws {
        let job = try XCTUnwrap(JobURLImportService.parseJob(from: validJSON(), sourceURL: sourceURL))
        XCTAssertEqual(job.jobPosition, "Staff Engineer")
        XCTAssertEqual(job.companyName, "Acme Corp")
        XCTAssertEqual(job.jobLocation, "Austin, TX")
        XCTAssertEqual(job.seniorityLevel, "Staff")
        XCTAssertEqual(job.industries, "Software")
        XCTAssertEqual(job.jobPostingTime, "2 days ago")
        XCTAssertEqual(job.jobDescription, "Build things.")
        XCTAssertEqual(job.postingURL, sourceURL)
        XCTAssertEqual(job.salary, "$150k–$180k")
        XCTAssertEqual(job.jobApplyLink, "https://apply.example.com")
        XCTAssertEqual(job.source, "LLM Import")
        XCTAssertEqual(job.status, .new)
    }

    func testToleratesJSONCodeFence() throws {
        let fenced = "```json\n" + validJSON() + "\n```"
        let job = try XCTUnwrap(JobURLImportService.parseJob(from: fenced, sourceURL: sourceURL))
        XCTAssertEqual(job.companyName, "Acme Corp")
    }

    func testWorkplaceTypeAppendedToEmploymentType() throws {
        let job = try XCTUnwrap(JobURLImportService.parseJob(
            from: validJSON(workplaceType: "Hybrid", employmentType: "Contract"),
            sourceURL: sourceURL))
        XCTAssertEqual(job.employmentType, "Contract (Hybrid)")
    }

    func testEmptyApplyLinkFallsBackToSourceURL() throws {
        let job = try XCTUnwrap(JobURLImportService.parseJob(
            from: validJSON(applyLink: ""), sourceURL: sourceURL))
        XCTAssertEqual(job.jobApplyLink, sourceURL)
    }

    func testSalaryNotSpecifiedIsIgnored() throws {
        let job = try XCTUnwrap(JobURLImportService.parseJob(
            from: validJSON(salary: "Not specified"), sourceURL: sourceURL))
        XCTAssertTrue(job.salary.isEmpty, "the literal 'Not specified' must not populate the salary field")
    }

    func testMissingTitleReturnsNil() {
        let json = """
        { "job_title": "", "company": "Acme Corp", "job_description": "x" }
        """
        XCTAssertNil(JobURLImportService.parseJob(from: json, sourceURL: sourceURL),
                     "a missing job title must fail the essential-data guard")
    }

    func testMissingCompanyReturnsNil() {
        let json = """
        { "job_title": "Engineer", "company": "", "job_description": "x" }
        """
        XCTAssertNil(JobURLImportService.parseJob(from: json, sourceURL: sourceURL),
                     "a missing company must fail the essential-data guard")
    }

    func testMalformedJSONReturnsNil() {
        XCTAssertNil(JobURLImportService.parseJob(from: "{ not json", sourceURL: sourceURL))
    }
}
