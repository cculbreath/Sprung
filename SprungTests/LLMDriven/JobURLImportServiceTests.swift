//
//  JobURLImportServiceTests.swift
//  SprungTests
//
//  Covers the pure halves of the job-import flow, extracted out of
//  NewAppSheetView so they are testable: parseJob(from:sourceURL:) (the JSON →
//  JobApp mapping), the text-input request-build variant (posting text supplied
//  directly — the LinkedIn MCP detail path — so no web-search tool, with an
//  explicit output-token cap and the same schema as the URL variant), and the
//  jobImportModelId resolution that throws instead of substituting a default.
//  The live OpenAI streaming half is not unit-testable.
//

import XCTest
import SwiftOpenAI
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

    // MARK: - Text-input variant (request-build half)

    /// Encode a request the way the SDK ships it, for wire-shape assertions.
    private func encodedWire(_ parameters: ModelResponseParameter) throws -> [String: Any] {
        let data = try JSONEncoder().encode(parameters)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTextVariantUsesSuppliedModelId() {
        let params = JobURLImportService.buildTextParameters(postingText: "posting", modelId: "test-model-id")
        XCTAssertEqual(params.model, "test-model-id")
    }

    func testTextVariantSetsExplicitMaxOutputTokens() {
        // Reasoning + structured output without an explicit cap silently
        // truncates — the cap must always be present on the text variant.
        let params = JobURLImportService.buildTextParameters(postingText: "posting", modelId: "test-model-id")
        XCTAssertEqual(params.maxOutputTokens, JobURLImportService.textVariantMaxOutputTokens)
    }

    func testTextVariantCarriesNoTools() {
        // The posting text is supplied directly; there is no web-search step.
        let params = JobURLImportService.buildTextParameters(postingText: "posting", modelId: "test-model-id")
        XCTAssertNil(params.tools)
        XCTAssertNil(params.toolChoice)
    }

    func testTextVariantSchemaMatchesURLVariant() throws {
        // Both variants must emit the identical structured-output config —
        // one schema, two transports.
        let urlParams = JobURLImportService.buildParameters(
            url: URL(string: "https://example.com/jobs/1")!, modelId: "test-model-id"
        )
        let textParams = JobURLImportService.buildTextParameters(postingText: "posting", modelId: "test-model-id")
        let urlTextConfig = try XCTUnwrap(encodedWire(urlParams)["text"] as? [String: Any])
        let textTextConfig = try XCTUnwrap(encodedWire(textParams)["text"] as? [String: Any])
        XCTAssertEqual(NSDictionary(dictionary: urlTextConfig), NSDictionary(dictionary: textTextConfig))
    }

    func testTextVariantEmbedsThePostingText() throws {
        let params = JobURLImportService.buildTextParameters(
            postingText: "Operate the big lathe safely.", modelId: "test-model-id"
        )
        let wire = try XCTUnwrap(String(data: JSONEncoder().encode(params), encoding: .utf8))
        XCTAssertTrue(wire.contains("Operate the big lathe safely."))
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
