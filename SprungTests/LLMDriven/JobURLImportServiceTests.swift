//
//  JobURLImportServiceTests.swift
//  SprungTests
//
//  Covers the pure halves of the job-import flow: makeJobApp (the extracted
//  ImportedJobFields → JobApp mapping, including the "Not specified" filler
//  normalization and the essential-data guard), that the submit_job tool input
//  JSON decodes into ImportedJobFields, and the jobImportModelId resolution that
//  throws instead of substituting a default. The live Anthropic tool-loop half
//  (JobImportLoop) is not unit-testable.
//

import XCTest
@testable import Sprung

@MainActor
final class JobURLImportServiceTests: XCTestCase {

    private let sourceURL = "https://example.com/jobs/123"

    private func fields(
        jobTitle: String = "Staff Engineer",
        company: String = "Acme Corp",
        applyLink: String = "https://apply.example.com",
        salary: String = "$150k–$180k",
        workplaceType: String = "Remote",
        employmentType: String = "Full-time"
    ) -> ImportedJobFields {
        ImportedJobFields(
            jobTitle: jobTitle,
            company: company,
            location: "Austin, TX",
            workplaceType: workplaceType,
            employmentType: employmentType,
            seniorityLevel: "Staff",
            industries: "Software",
            postedDate: "2 days ago",
            salary: salary,
            jobDescription: "Build things.",
            applyLink: applyLink
        )
    }

    func testMapsAllCoreFields() throws {
        let job = try XCTUnwrap(JobURLImportService.makeJobApp(from: fields(), sourceURL: sourceURL))
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

    func testSubmitJobToolInputDecodes() throws {
        // The submit_job tool input arrives as camelCase JSON (keys we control);
        // it must decode into ImportedJobFields for makeJobApp.
        let json = """
        {
          "jobTitle": "Staff Engineer", "company": "Acme Corp", "location": "Austin, TX",
          "workplaceType": "Remote", "employmentType": "Full-time", "seniorityLevel": "Staff",
          "industries": "Software", "postedDate": "2 days ago", "salary": "$150k",
          "jobDescription": "Build things.", "applyLink": "https://apply.example.com"
        }
        """
        let decoded = try JSONDecoder().decode(ImportedJobFields.self, from: Data(json.utf8))
        let job = try XCTUnwrap(JobURLImportService.makeJobApp(from: decoded, sourceURL: sourceURL))
        XCTAssertEqual(job.companyName, "Acme Corp")
        XCTAssertEqual(job.salary, "$150k")
    }

    func testWorkplaceTypeAppendedToEmploymentType() throws {
        let job = try XCTUnwrap(JobURLImportService.makeJobApp(
            from: fields(workplaceType: "Hybrid", employmentType: "Contract"), sourceURL: sourceURL))
        XCTAssertEqual(job.employmentType, "Contract (Hybrid)")
    }

    func testEmptyApplyLinkFallsBackToSourceURL() throws {
        let job = try XCTUnwrap(JobURLImportService.makeJobApp(
            from: fields(applyLink: ""), sourceURL: sourceURL))
        XCTAssertEqual(job.jobApplyLink, sourceURL)
    }

    func testNotSpecifiedApplyLinkFallsBackToSourceURL() throws {
        // The extractor emits "Not specified" for an absent field — that filler
        // must not become the apply link.
        let job = try XCTUnwrap(JobURLImportService.makeJobApp(
            from: fields(applyLink: "Not specified"), sourceURL: sourceURL))
        XCTAssertEqual(job.jobApplyLink, sourceURL)
    }

    func testSalaryNotSpecifiedIsIgnored() throws {
        let job = try XCTUnwrap(JobURLImportService.makeJobApp(
            from: fields(salary: "Not specified"), sourceURL: sourceURL))
        XCTAssertTrue(job.salary.isEmpty, "the literal 'Not specified' must not populate the salary field")
    }

    func testMissingTitleReturnsNil() {
        XCTAssertNil(JobURLImportService.makeJobApp(from: fields(jobTitle: ""), sourceURL: sourceURL),
                     "a missing job title must fail the essential-data guard")
    }

    func testMissingCompanyReturnsNil() {
        XCTAssertNil(JobURLImportService.makeJobApp(from: fields(company: ""), sourceURL: sourceURL),
                     "a missing company must fail the essential-data guard")
    }

    // MARK: - jobImportModelId resolution

    func testRequireJobImportModelIdThrowsWhenUnconfigured() {
        let defaults = TestDefaults()
        XCTAssertThrowsError(
            try JobURLImportService.requireJobImportModelId(operationName: "Test Import", defaults: defaults.store)
        ) { error in
            guard case ModelConfigurationError.modelNotConfigured(let settingKey, _) = error else {
                return XCTFail("Expected .modelNotConfigured, got \(error)")
            }
            XCTAssertEqual(settingKey, "jobImportModelId")
        }
    }

    func testRequireJobImportModelIdThrowsWhenEmpty() {
        let defaults = TestDefaults()
        defaults.store.set("", forKey: "jobImportModelId")
        XCTAssertThrowsError(
            try JobURLImportService.requireJobImportModelId(operationName: "Test Import", defaults: defaults.store)
        )
    }

    func testRequireJobImportModelIdReturnsConfiguredValue() throws {
        let defaults = TestDefaults()
        defaults.store.set("test-model-id", forKey: "jobImportModelId")
        XCTAssertEqual(
            try JobURLImportService.requireJobImportModelId(operationName: "Test Import", defaults: defaults.store),
            "test-model-id"
        )
    }
}
