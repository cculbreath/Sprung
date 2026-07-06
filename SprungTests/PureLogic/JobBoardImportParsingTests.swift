//
//  JobBoardImportParsingTests.swift
//  SprungTests
//
//  Covers Sprung/JobApplications/MCP/JobMCPImportService.swift's pure halves:
//  Dice's `result.content[0].text` JSON payload and ZipRecruiter's sibling
//  `structuredContent` payload (decoded here directly with the same
//  `JSONDecoder` calls `searchDice`/`searchZipRecruiter` make -- the network
//  extraction step that hands each its raw bytes is covered at the transport
//  level in MCPWireParsingTests.swift), plus salary/date formatting, the
//  `detailsPageUrl` normalization dedup badges depend on, and DTO -> JobApp
//  mapping.
//

import XCTest
@testable import Sprung

@MainActor
final class JobBoardImportParsingTests: XCTestCase {

    // MARK: - Dice decode

    func testDiceSearchPayloadDecodesFullRecord() throws {
        let json = """
        {
          "data": [
            {
              "id": "12345",
              "title": "Senior iOS Engineer",
              "summary": "Build great apps.",
              "postedDate": "2026-06-01T00:00:00.000Z",
              "jobLocation": { "displayName": "Austin, TX" },
              "detailsPageUrl": "https://www.dice.com/job-detail/abc-123?utm_source=partner",
              "salary": "$140,000 - $180,000",
              "companyName": "Acme Corp",
              "employmentType": "Full Time",
              "employerType": "Direct",
              "workplaceTypes": ["Remote"],
              "easyApply": true,
              "willingToSponsor": false
            }
          ],
          "meta": { "currentPage": 1, "pageCount": 5, "pageSize": 20, "totalResults": 97 }
        }
        """
        let payload = try JSONDecoder().decode(DiceSearchPayload.self, from: XCTUnwrap(json.data(using: .utf8)))
        XCTAssertEqual(payload.jobs.count, 1)
        let job = try XCTUnwrap(payload.jobs.first)
        XCTAssertEqual(job.id, "12345")
        XCTAssertEqual(job.title, "Senior iOS Engineer")
        XCTAssertEqual(job.jobLocation?.displayName, "Austin, TX")
        XCTAssertEqual(job.companyName, "Acme Corp")
        XCTAssertEqual(job.workplaceTypes, ["Remote"])
        XCTAssertEqual(job.easyApply, true)
        XCTAssertEqual(job.willingToSponsor, false)
        XCTAssertEqual(payload.meta?.currentPage, 1)
        XCTAssertEqual(payload.meta?.pageCount, 5)
        XCTAssertEqual(payload.meta?.pageSize, 20)
        XCTAssertEqual(payload.meta?.totalResults, 97)
    }

    func testDiceJobResultToleratesAllOptionalFieldsMissing() throws {
        let json = #"{"data": [{"id": "only-id"}]}"#
        let payload = try JSONDecoder().decode(DiceSearchPayload.self, from: XCTUnwrap(json.data(using: .utf8)))
        let job = try XCTUnwrap(payload.jobs.first)
        XCTAssertEqual(job.id, "only-id")
        XCTAssertNil(job.title)
        XCTAssertNil(job.summary)
        XCTAssertNil(job.jobLocation)
        XCTAssertNil(job.detailsPageUrl)
        XCTAssertNil(job.workplaceTypes)
        XCTAssertNil(payload.meta)
    }

    func testDiceSearchMetaToleratesPartialFields() throws {
        let json = #"{"data": [], "meta": {"currentPage": 3}}"#
        let payload = try JSONDecoder().decode(DiceSearchPayload.self, from: XCTUnwrap(json.data(using: .utf8)))
        XCTAssertEqual(payload.meta?.currentPage, 3)
        XCTAssertNil(payload.meta?.pageCount)
        XCTAssertNil(payload.meta?.pageSize)
        XCTAssertNil(payload.meta?.totalResults)
    }

    func testDiceSearchPayloadWithoutDataKeyYieldsEmptyJobs() throws {
        let json = #"{"meta": {"currentPage": 1}}"#
        let payload = try JSONDecoder().decode(DiceSearchPayload.self, from: XCTUnwrap(json.data(using: .utf8)))
        XCTAssertNil(payload.data)
        XCTAssertEqual(payload.jobs, [])
    }

    // MARK: - Dice URL normalization (dedup-stability contract)

    func testNormalizedPostingURLStripsQueryAndFragment() {
        let raw = "https://www.dice.com/job-detail/abc-123?utm_source=partner&utm_campaign=x&ref=456#section"
        let normalized = JobMCPImportService.normalizedPostingURL(raw)
        XCTAssertEqual(normalized, "https://www.dice.com/job-detail/abc-123")
        // NOTE (real contract, not what the doc comment's framing implies): the
        // implementation strips the *entire* query string unconditionally via
        // `components.query = nil`, not just `utm_*` keys -- `ref=456` above is
        // discarded too even though it isn't a utm_ param. "utm_*" in the source
        // comment describes what Dice's payload typically contains, not a filter
        // the code applies.
    }

    func testNormalizedPostingURLLeavesQuerylessURLUnchanged() {
        let raw = "https://www.dice.com/job-detail/abc-123"
        XCTAssertEqual(JobMCPImportService.normalizedPostingURL(raw), raw)
    }

    func testIsImportedDiceMatchesAfterNormalization() {
        let result = DiceJobResult(
            id: "1", title: "Engineer", summary: nil, postedDate: nil, jobLocation: nil,
            detailsPageUrl: "https://www.dice.com/job-detail/abc-123?utm_source=partner",
            salary: nil, companyName: "Acme", employmentType: nil, employerType: nil,
            workplaceTypes: nil, easyApply: nil, willingToSponsor: nil
        )
        let importedURLs: Set<String> = ["https://www.dice.com/job-detail/abc-123"]
        XCTAssertTrue(JobMCPImportService.isImported(result, importedURLs: importedURLs))
    }

    func testIsImportedDiceFalseWhenURLNotInSet() {
        let result = DiceJobResult(
            id: "1", title: "Engineer", summary: nil, postedDate: nil, jobLocation: nil,
            detailsPageUrl: "https://www.dice.com/job-detail/other-job",
            salary: nil, companyName: "Acme", employmentType: nil, employerType: nil,
            workplaceTypes: nil, easyApply: nil, willingToSponsor: nil
        )
        let importedURLs: Set<String> = ["https://www.dice.com/job-detail/abc-123"]
        XCTAssertFalse(JobMCPImportService.isImported(result, importedURLs: importedURLs))
    }

    // MARK: - Dice mapping

    func testMakeJobAppFromDiceMapsCoreFields() throws {
        let result = DiceJobResult(
            id: "1", title: "Senior iOS Engineer", summary: "Build great apps.",
            postedDate: "2026-06-01T00:00:00.000Z",
            jobLocation: .init(displayName: "Austin, TX"),
            detailsPageUrl: "https://www.dice.com/job-detail/abc-123?utm_source=partner",
            salary: "$140,000 - $180,000", companyName: "Acme Corp",
            employmentType: "Full Time", employerType: "Direct",
            workplaceTypes: ["Remote", "Hybrid"], easyApply: true, willingToSponsor: nil
        )
        let jobApp = try XCTUnwrap(JobMCPImportService.makeJobApp(from: result))
        XCTAssertEqual(jobApp.jobPosition, "Senior iOS Engineer")
        XCTAssertEqual(jobApp.companyName, "Acme Corp")
        XCTAssertEqual(jobApp.jobLocation, "Austin, TX")
        XCTAssertEqual(jobApp.jobDescription, "Build great apps.")
        XCTAssertEqual(jobApp.postingURL, "https://www.dice.com/job-detail/abc-123", "postingURL must be the normalized (query-stripped) URL")
        XCTAssertEqual(jobApp.jobApplyLink, "https://www.dice.com/job-detail/abc-123")
        XCTAssertEqual(jobApp.salary, "$140,000 - $180,000")
        XCTAssertEqual(jobApp.employmentType, "Full Time (Remote, Hybrid)")
        XCTAssertEqual(jobApp.status, .new)
        XCTAssertEqual(jobApp.source, "Dice")
    }

    func testMakeJobAppFromDiceReturnsNilWithoutEssentials() {
        let missingTitle = DiceJobResult(
            id: "1", title: nil, summary: nil, postedDate: nil, jobLocation: nil,
            detailsPageUrl: "https://example.com/x", salary: nil, companyName: "Acme",
            employmentType: nil, employerType: nil, workplaceTypes: nil, easyApply: nil, willingToSponsor: nil
        )
        XCTAssertNil(JobMCPImportService.makeJobApp(from: missingTitle))

        let missingCompany = DiceJobResult(
            id: "1", title: "Engineer", summary: nil, postedDate: nil, jobLocation: nil,
            detailsPageUrl: "https://example.com/x", salary: nil, companyName: nil,
            employmentType: nil, employerType: nil, workplaceTypes: nil, easyApply: nil, willingToSponsor: nil
        )
        XCTAssertNil(JobMCPImportService.makeJobApp(from: missingCompany))

        let missingURL = DiceJobResult(
            id: "1", title: "Engineer", summary: nil, postedDate: nil, jobLocation: nil,
            detailsPageUrl: nil, salary: nil, companyName: "Acme",
            employmentType: nil, employerType: nil, workplaceTypes: nil, easyApply: nil, willingToSponsor: nil
        )
        XCTAssertNil(JobMCPImportService.makeJobApp(from: missingURL))
    }

    // MARK: - ZipRecruiter decode (arrives in the sibling `structuredContent` object)

    func testZipRecruiterSearchPayloadDecodesFullRecord() throws {
        let json = """
        {
          "results": [
            {
              "title": "Backend Engineer",
              "company": "Widget Co",
              "location": "Denver, CO",
              "is_remote": true,
              "salary": { "min_annual": 120000, "max_annual": 160000 },
              "company_logo": "https://example.com/logo.png",
              "job_redirect_url": "https://ziprecruiter.com/redirect/xyz",
              "job_type": "Full Time",
              "benefits": "Health, dental",
              "days_ago": 3
            }
          ],
          "meta": { "count": 1, "limit": 20, "total": 42, "offset": 0 },
          "status": "ok",
          "warnings": []
        }
        """
        let payload = try JSONDecoder().decode(JobMCPImportService.ZipRecruiterSearchPayload.self, from: XCTUnwrap(json.data(using: .utf8)))
        let job = try XCTUnwrap(payload.jobs.first)
        XCTAssertEqual(job.title, "Backend Engineer")
        XCTAssertEqual(job.company, "Widget Co")
        XCTAssertEqual(job.isRemote, true)
        XCTAssertEqual(job.salary?.minAnnual, 120000)
        XCTAssertEqual(job.salary?.maxAnnual, 160000)
        XCTAssertEqual(job.jobRedirectUrl, "https://ziprecruiter.com/redirect/xyz")
        XCTAssertEqual(job.daysAgo, 3)
        XCTAssertEqual(payload.meta?.count, 1)
        XCTAssertEqual(payload.meta?.limit, 20)
        XCTAssertEqual(payload.meta?.total, 42)
        XCTAssertEqual(payload.meta?.offset, 0)
        XCTAssertEqual(payload.status, "ok")
        XCTAssertEqual(payload.warnings, [])
    }

    func testZipRecruiterJobResultToleratesAllFieldsMissing() throws {
        let json = #"{"results": [{}]}"#
        let payload = try JSONDecoder().decode(JobMCPImportService.ZipRecruiterSearchPayload.self, from: XCTUnwrap(json.data(using: .utf8)))
        let job = try XCTUnwrap(payload.jobs.first)
        XCTAssertNil(job.title)
        XCTAssertNil(job.jobRedirectUrl)
        XCTAssertEqual(job.id, "||", "the Identifiable fallback joins title|company|location, all empty when absent")
    }

    func testZipRecruiterSearchMetaOffsetOmittedIsNil() throws {
        let json = #"{"results": [], "meta": {"count": 5, "limit": 20, "total": 100}}"#
        let payload = try JSONDecoder().decode(JobMCPImportService.ZipRecruiterSearchPayload.self, from: XCTUnwrap(json.data(using: .utf8)))
        XCTAssertEqual(payload.meta?.count, 5)
        XCTAssertNil(payload.meta?.offset, "offset absent server-side (defaults to 0 remotely) must decode as nil, not 0")
    }

    func testZipRecruiterSearchPayloadEmptyObjectDecodes() throws {
        let payload = try JSONDecoder().decode(JobMCPImportService.ZipRecruiterSearchPayload.self, from: XCTUnwrap("{}".data(using: .utf8)))
        XCTAssertEqual(payload.jobs, [])
        XCTAssertNil(payload.meta)
        XCTAssertNil(payload.status)
    }

    // MARK: - ZipRecruiter salary formatting

    private func dollars(_ amount: Int) -> String { "$\(amount.formatted(.number))" }

    func testDisplaySalaryRangeBothBounds() {
        let salary = JobMCPImportService.ZipRecruiterSalary(minAnnual: 120_000, maxAnnual: 160_000)
        XCTAssertEqual(JobMCPImportService.displaySalaryRange(salary), "\(dollars(120_000)) – \(dollars(160_000))")
    }

    func testDisplaySalaryRangeMinOnly() {
        let salary = JobMCPImportService.ZipRecruiterSalary(minAnnual: 90_000, maxAnnual: nil)
        XCTAssertEqual(JobMCPImportService.displaySalaryRange(salary), "\(dollars(90_000))+")
    }

    func testDisplaySalaryRangeMaxOnly() {
        let salary = JobMCPImportService.ZipRecruiterSalary(minAnnual: nil, maxAnnual: 90_000)
        XCTAssertEqual(JobMCPImportService.displaySalaryRange(salary), "Up to \(dollars(90_000))")
    }

    func testDisplaySalaryRangeNeitherBoundReturnsNil() {
        let salary = JobMCPImportService.ZipRecruiterSalary(minAnnual: nil, maxAnnual: nil)
        XCTAssertNil(JobMCPImportService.displaySalaryRange(salary))
    }

    func testDisplaySalaryRangeNilSalaryReturnsNil() {
        XCTAssertNil(JobMCPImportService.displaySalaryRange(nil))
    }

    // MARK: - ZipRecruiter days-ago -> date mapping

    func testDisplayDaysAgoMatchesCalendarSubtraction() throws {
        let daysAgo = 5
        let expectedDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()))
        let expected = expectedDate.formatted(date: .abbreviated, time: .omitted)
        XCTAssertEqual(JobMCPImportService.displayDaysAgo(daysAgo), expected)
    }

    // MARK: - ZipRecruiter is_remote location suffix + mapping

    func testMakeJobAppFromZipRecruiterAppendsRemoteSuffixWithLocation() throws {
        let result = JobMCPImportService.ZipRecruiterJobResult(
            title: "Backend Engineer", company: "Widget Co", location: "Denver, CO",
            isRemote: true, salary: nil, companyLogo: nil,
            jobRedirectUrl: "https://ziprecruiter.com/redirect/xyz", jobType: nil, benefits: nil, daysAgo: nil
        )
        let jobApp = try XCTUnwrap(JobMCPImportService.makeJobApp(from: result))
        XCTAssertEqual(jobApp.jobLocation, "Denver, CO (Remote)")
    }

    func testMakeJobAppFromZipRecruiterRemoteWithoutLocationIsJustRemote() throws {
        let result = JobMCPImportService.ZipRecruiterJobResult(
            title: "Backend Engineer", company: "Widget Co", location: nil,
            isRemote: true, salary: nil, companyLogo: nil,
            jobRedirectUrl: "https://ziprecruiter.com/redirect/xyz", jobType: nil, benefits: nil, daysAgo: nil
        )
        let jobApp = try XCTUnwrap(JobMCPImportService.makeJobApp(from: result))
        XCTAssertEqual(jobApp.jobLocation, "Remote")
    }

    func testMakeJobAppFromZipRecruiterNonRemoteUsesLocationAsIs() throws {
        let result = JobMCPImportService.ZipRecruiterJobResult(
            title: "Backend Engineer", company: "Widget Co", location: "Denver, CO",
            isRemote: false, salary: nil, companyLogo: nil,
            jobRedirectUrl: "https://ziprecruiter.com/redirect/xyz", jobType: nil, benefits: nil, daysAgo: nil
        )
        let jobApp = try XCTUnwrap(JobMCPImportService.makeJobApp(from: result))
        XCTAssertEqual(jobApp.jobLocation, "Denver, CO")
    }

    func testMakeJobAppFromZipRecruiterCarriesSalaryAndDaysAgoAndJobType() throws {
        let result = JobMCPImportService.ZipRecruiterJobResult(
            title: "Backend Engineer", company: "Widget Co", location: "Denver, CO",
            isRemote: false, salary: .init(minAnnual: 100_000, maxAnnual: 130_000), companyLogo: nil,
            jobRedirectUrl: "https://ziprecruiter.com/redirect/xyz", jobType: "Full Time", benefits: "Health", daysAgo: 2
        )
        let jobApp = try XCTUnwrap(JobMCPImportService.makeJobApp(from: result))
        XCTAssertEqual(jobApp.salary, "\(dollars(100_000)) – \(dollars(130_000))")
        XCTAssertEqual(jobApp.employmentType, "Full Time")
        XCTAssertEqual(jobApp.jobPostingTime, JobMCPImportService.displayDaysAgo(2))
        XCTAssertEqual(jobApp.status, .new)
        XCTAssertEqual(jobApp.source, "ZipRecruiter")
        // `benefits` has no corresponding JobApp field and is intentionally
        // dropped by makeJobApp -- nothing to assert for it directly.
    }

    func testMakeJobAppFromZipRecruiterReturnsNilWithoutEssentials() {
        let missingTitle = JobMCPImportService.ZipRecruiterJobResult(
            title: nil, company: "Acme", location: nil, isRemote: nil, salary: nil,
            companyLogo: nil, jobRedirectUrl: "https://x", jobType: nil, benefits: nil, daysAgo: nil
        )
        XCTAssertNil(JobMCPImportService.makeJobApp(from: missingTitle))

        let missingCompany = JobMCPImportService.ZipRecruiterJobResult(
            title: "Engineer", company: nil, location: nil, isRemote: nil, salary: nil,
            companyLogo: nil, jobRedirectUrl: "https://x", jobType: nil, benefits: nil, daysAgo: nil
        )
        XCTAssertNil(JobMCPImportService.makeJobApp(from: missingCompany))

        let missingRedirect = JobMCPImportService.ZipRecruiterJobResult(
            title: "Engineer", company: "Acme", location: nil, isRemote: nil, salary: nil,
            companyLogo: nil, jobRedirectUrl: nil, jobType: nil, benefits: nil, daysAgo: nil
        )
        XCTAssertNil(JobMCPImportService.makeJobApp(from: missingRedirect))
    }

    func testIsImportedZipRecruiterMatchesTitleAndCompany() {
        let result = JobMCPImportService.ZipRecruiterJobResult(
            title: "Backend Engineer", company: "Widget Co", location: nil, isRemote: nil,
            salary: nil, companyLogo: nil, jobRedirectUrl: "https://x", jobType: nil, benefits: nil, daysAgo: nil
        )
        let pairs: Set<JobMCPImportService.TitleCompanyPair> = [
            JobMCPImportService.TitleCompanyPair(title: "Backend Engineer", company: "Widget Co")
        ]
        XCTAssertTrue(JobMCPImportService.isImported(result, importedPairs: pairs))
    }

    func testIsImportedZipRecruiterFalseWhenPairNotInSet() {
        let result = JobMCPImportService.ZipRecruiterJobResult(
            title: "Backend Engineer", company: "Widget Co", location: nil, isRemote: nil,
            salary: nil, companyLogo: nil, jobRedirectUrl: "https://x", jobType: nil, benefits: nil, daysAgo: nil
        )
        let pairs: Set<JobMCPImportService.TitleCompanyPair> = [
            JobMCPImportService.TitleCompanyPair(title: "Someone Else", company: "Other Co")
        ]
        XCTAssertFalse(JobMCPImportService.isImported(result, importedPairs: pairs))
    }
}
