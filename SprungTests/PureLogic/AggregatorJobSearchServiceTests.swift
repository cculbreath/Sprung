//
//  AggregatorJobSearchServiceTests.swift
//  SprungTests
//
//  Pure halves of the two Google-for-Jobs aggregator boards (JSearch via
//  RapidAPI, SerpApi google_jobs): request building, date-posted mapping, and
//  payload decode. The response shapes and the JSearch /search-v2 endpoint were
//  verified against the live APIs (2026-07-08).
//

import XCTest
import Foundation
@testable import Sprung

final class AggregatorJobSearchServiceTests: XCTestCase {

    private func queryDict(_ request: URLRequest?) -> [String: String] {
        guard let url = request?.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - JSearch request

    func testJSearchRequestUsesSearchV2WithFoldedLocationAndHeaders() {
        let request = AggregatorJobSearchService.jsearchRequest(
            keywords: "medical physicist", location: "Austin, TX",
            datePosted: "pastWeek", country: "us", apiKey: "KEY123"
        )
        let url = request?.url?.absoluteString ?? ""
        XCTAssertTrue(url.hasPrefix("https://jsearch.p.rapidapi.com/search-v2"),
                      "the legacy /search path 404s — the endpoint is /search-v2")
        let q = queryDict(request)
        XCTAssertEqual(q["query"], "medical physicist in Austin, TX", "location folds into the query")
        XCTAssertEqual(q["country"], "us")
        XCTAssertEqual(q["date_posted"], "week")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-RapidAPI-Key"), "KEY123")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-RapidAPI-Host"), "jsearch.p.rapidapi.com")
    }

    func testJSearchRequestOmitsLocationFromQueryWhenAbsent() {
        let q = queryDict(AggregatorJobSearchService.jsearchRequest(
            keywords: "physicist", location: nil, datePosted: nil, country: "us", apiKey: "K"
        ))
        XCTAssertEqual(q["query"], "physicist")
        XCTAssertEqual(q["date_posted"], "all", "absent recency filter maps to all")
    }

    func testJSearchDatePostedMapping() {
        XCTAssertEqual(AggregatorJobSearchService.jsearchDatePosted(from: "pastHour"), "today")
        XCTAssertEqual(AggregatorJobSearchService.jsearchDatePosted(from: "past24Hours"), "today")
        XCTAssertEqual(AggregatorJobSearchService.jsearchDatePosted(from: "pastWeek"), "week")
        XCTAssertEqual(AggregatorJobSearchService.jsearchDatePosted(from: "pastMonth"), "month")
        XCTAssertEqual(AggregatorJobSearchService.jsearchDatePosted(from: nil), "all")
        XCTAssertEqual(AggregatorJobSearchService.jsearchDatePosted(from: "bogus"), "all")
    }

    // MARK: - SerpApi request

    func testSerpApiRequestCarriesEngineQueryLocationAndKey() {
        let request = AggregatorJobSearchService.serpApiRequest(
            keywords: "software engineer", location: "Austin, TX", apiKey: "SK"
        )
        XCTAssertEqual(request?.url?.host, "serpapi.com")
        XCTAssertTrue((request?.url?.path ?? "").hasSuffix("/search.json"))
        let q = queryDict(request)
        XCTAssertEqual(q["engine"], "google_jobs")
        XCTAssertEqual(q["q"], "software engineer")
        XCTAssertEqual(q["location"], "Austin, TX")
        XCTAssertEqual(q["api_key"], "SK")
    }

    func testSerpApiRequestOmitsBlankLocation() {
        let q = queryDict(AggregatorJobSearchService.serpApiRequest(keywords: "engineer", location: "  ", apiKey: "SK"))
        XCTAssertNil(q["location"], "a blank location isn't sent")
        XCTAssertEqual(q["q"], "engineer")
    }

    // MARK: - Indeed (jobs-api14) request

    func testIndeedRequestHitsJobsApi14WithCountryAndHeaders() {
        let request = AggregatorJobSearchService.indeedRequest(
            keywords: "software engineer", location: "Austin", countryCode: "us", datePosted: "pastWeek", apiKey: "K"
        )
        XCTAssertEqual(request?.url?.host, "jobs-api14.p.rapidapi.com")
        XCTAssertTrue((request?.url?.path ?? "").hasSuffix("/v2/indeed/search"))
        let q = queryDict(request)
        XCTAssertEqual(q["query"], "software engineer")
        XCTAssertEqual(q["countryCode"], "us")
        XCTAssertEqual(q["location"], "Austin")
        XCTAssertEqual(q["sortType"], "date", "a recency request sorts by date")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-RapidAPI-Host"), "jobs-api14.p.rapidapi.com")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-RapidAPI-Key"), "K")
    }

    func testIndeedSortTypeDefaultsToRelevance() {
        XCTAssertEqual(AggregatorJobSearchService.indeedSortType(from: nil), "relevance")
        XCTAssertEqual(AggregatorJobSearchService.indeedSortType(from: "pastWeek"), "date")
    }

    func testIndeedPayloadDecodesNestedResults() throws {
        let json = """
        {"data":[
          {"title":"Engineer","company":{"name":"Acme","addresses":["Austin, TX"]},
           "location":{"country":"United States","countryCode":"US","location":"Austin, TX"},
           "applyUrl":"https://a/1","description":"role","id":"x"}
        ],"meta":{"count":1},"hasError":false}
        """
        let payload = try JSONDecoder().decode(IndeedSearchPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.jobs.count, 1)
        XCTAssertEqual(payload.jobs[0].company?.name, "Acme")
        XCTAssertEqual(payload.jobs[0].location?.location, "Austin, TX")
        XCTAssertEqual(payload.jobs[0].applyUrl, "https://a/1")
    }

    // MARK: - Payload decode (shapes verified against the live APIs)

    func testJSearchPayloadDecodesNestedDataJobs() throws {
        let json = """
        {"status":"OK","request_id":"x","data":{"jobs":[
          {"job_title":"Physicist","employer_name":"Acme","job_apply_link":"https://a/1",
           "job_city":"Austin","job_state":"TX","job_country":"US","job_is_remote":false,
           "job_min_salary":150000,"job_max_salary":190000,"job_salary_period":"YEAR",
           "job_posted_at_datetime_utc":"2026-06-01T00:00:00.000Z"}
        ],"cursor":"abc"}}
        """
        let payload = try JSONDecoder().decode(JSearchSearchPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.jobs.count, 1)
        XCTAssertEqual(payload.jobs[0].jobTitle, "Physicist")
        XCTAssertEqual(payload.jobs[0].jobApplyLink, "https://a/1")
    }

    func testJSearchPayloadEmptyDataDecodesToNoJobs() throws {
        let payload = try JSONDecoder().decode(
            JSearchSearchPayload.self, from: Data(#"{"status":"OK","data":{"jobs":[]}}"#.utf8)
        )
        XCTAssertTrue(payload.jobs.isEmpty)
    }

    func testSerpApiPayloadDecodesJobsResults() throws {
        let json = """
        {"jobs_results":[
          {"title":"Engineer","company_name":"Beta","location":"Dallas, TX","description":"role",
           "apply_options":[{"title":"LinkedIn","link":"https://li/1"}],
           "detected_extensions":{"posted_at":"3 days ago","schedule_type":"Full-time"},
           "share_link":"https://share"}
        ]}
        """
        let payload = try JSONDecoder().decode(SerpApiSearchPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.jobs.count, 1)
        XCTAssertEqual(payload.jobs[0].applyOptions?.first?.link, "https://li/1")
        XCTAssertEqual(payload.jobs[0].detectedExtensions?.postedAt, "3 days ago")
    }

    func testSerpApiPayloadEmptyResultDecodesToNoJobs() throws {
        // SerpApi returns 200 with an `error` field and no jobs_results for an
        // empty query — a no-result, not a decode failure.
        let payload = try JSONDecoder().decode(SerpApiSearchPayload.self, from: Data(
            #"{"error":"Google hasn't returned any results for this query.","search_metadata":{"status":"Success"}}"#.utf8
        ))
        XCTAssertTrue(payload.jobs.isEmpty)
    }

    // MARK: - Missing key guards before any network

    func testSearchThrowsMissingKeyWithoutNetwork() async {
        do {
            _ = try await AggregatorJobSearchService.searchJSearch(
                keywords: "x", location: nil, datePosted: nil, country: "us", apiKey: "")
            XCTFail("an empty key must throw before any network call")
        } catch let error as AggregatorSearchError {
            guard case .missingKey(let provider) = error else { return XCTFail("expected missingKey") }
            XCTAssertEqual(provider, "JSearch")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        do {
            _ = try await AggregatorJobSearchService.searchSerpApi(keywords: "x", location: nil, apiKey: "")
            XCTFail("an empty key must throw before any network call")
        } catch let error as AggregatorSearchError {
            guard case .missingKey(let provider) = error else { return XCTFail("expected missingKey") }
            XCTAssertEqual(provider, "SerpApi")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        do {
            _ = try await AggregatorJobSearchService.searchIndeed(
                keywords: "x", location: nil, countryCode: "us", datePosted: nil, apiKey: "")
            XCTFail("an empty key must throw before any network call")
        } catch let error as AggregatorSearchError {
            guard case .missingKey(let provider) = error else { return XCTFail("expected missingKey") }
            XCTAssertEqual(provider, "Indeed")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
