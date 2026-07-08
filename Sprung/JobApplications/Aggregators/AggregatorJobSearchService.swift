//
//  AggregatorJobSearchService.swift
//  Sprung
//
//  Pure, testable halves of the two Google-for-Jobs aggregator boards the
//  Scout can search over plain REST (BYO API key): JSearch (via RapidAPI) and
//  SerpApi's google_jobs engine. Both read the same underlying Google-for-Jobs
//  index (Indeed, LinkedIn, Glassdoor, ZipRecruiter, company ATS boards, …),
//  so one board = broad coverage in a single call.
//
//  Mirrors JobMCPImportService's split: each provider gets its own request
//  builder, response DTO decode, and (in JobScoutService) result → compact
//  ScoutSearchResult mapping. The async halves are thin URLSession glue.
//
//  Request-format assumptions (documented so runtime drift is a one-line fix):
//   - JSearch: GET https://jsearch.p.rapidapi.com/search-v2 (verified live —
//     the older /search path 404s), headers X-RapidAPI-Key + X-RapidAPI-Host:
//     jsearch.p.rapidapi.com; location folded into `query`
//     ("<keywords> in <location>"); `country` is a separate ISO code;
//     `date_posted` ∈ all|today|3days|week|month. Results nest under data.jobs.
//   - SerpApi: GET https://serpapi.com/search.json?engine=google_jobs, key as
//     the `api_key` query param, `q` = keywords, `location` = free text. Date
//     filtering (the `uds`/`chips` token) is deliberately omitted — it's an
//     optimization, never worth failing a search over.
//   - Indeed (jobs-api14): GET https://jobs-api14.p.rapidapi.com/v2/indeed/search,
//     same RapidAPI headers as JSearch; `query`, `location`, `countryCode`
//     (required), `sortType` (relevance|date). Results are self-sufficient —
//     applyUrl + description in the search response. Verified live.
//

import Foundation

enum AggregatorSearchError: LocalizedError {
    /// The board is enabled but has no key configured (belt-and-suspenders —
    /// the run's key gate normally drops keyless boards before this).
    case missingKey(provider: String)
    case invalidEndpoint
    case http(provider: String, statusCode: Int)
    case malformedPayload(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider):
            return "\(provider) is enabled but has no API key. Add one under Settings > API Keys."
        case .invalidEndpoint:
            return "The job-search endpoint URL is invalid."
        case .http(let provider, let statusCode):
            let hint: String
            switch statusCode {
            case 401, 403: hint = " — check the API key"
            case 429: hint = " — hourly/monthly request limit reached"
            default: hint = ""
            }
            return "\(provider) search failed (HTTP \(statusCode))\(hint)."
        case .malformedPayload(let detail):
            return "Couldn't decode the job-search results: \(detail)"
        }
    }
}

// MARK: - JSearch wire types

/// One job record from JSearch's `/search` `data[]`. All fields optional so a
/// schema drift on a non-essential field never fails the whole decode; the
/// mapping (JobScoutService.scoutResult) requires only title + apply link.
struct JSearchJobResult: Codable {
    let jobTitle: String?
    let employerName: String?
    let jobCity: String?
    let jobState: String?
    let jobCountry: String?
    let jobApplyLink: String?
    let jobDescription: String?
    let jobIsRemote: Bool?
    let jobPostedAtDatetimeUtc: String?
    let jobPostedAt: String?
    let jobMinSalary: Double?
    let jobMaxSalary: Double?
    let jobSalaryPeriod: String?

    enum CodingKeys: String, CodingKey {
        case jobTitle = "job_title"
        case employerName = "employer_name"
        case jobCity = "job_city"
        case jobState = "job_state"
        case jobCountry = "job_country"
        case jobApplyLink = "job_apply_link"
        case jobDescription = "job_description"
        case jobIsRemote = "job_is_remote"
        case jobPostedAtDatetimeUtc = "job_posted_at_datetime_utc"
        case jobPostedAt = "job_posted_at"
        case jobMinSalary = "job_min_salary"
        case jobMaxSalary = "job_max_salary"
        case jobSalaryPeriod = "job_salary_period"
    }
}

/// JSearch's `/search-v2` nests the results under `data.jobs` (alongside a
/// pagination `cursor`) — not a bare `data[]`. Confirmed against the live API.
struct JSearchSearchPayload: Codable {
    struct DataContainer: Codable {
        let jobs: [JSearchJobResult]?
    }
    let status: String?
    let data: DataContainer?

    var jobs: [JSearchJobResult] { data?.jobs ?? [] }
}

// MARK: - SerpApi wire types

/// One job record from SerpApi's google_jobs `jobs_results[]`.
struct SerpApiJobResult: Codable {
    struct DetectedExtensions: Codable {
        let postedAt: String?
        let scheduleType: String?
        let workFromHome: Bool?
        let salary: String?

        enum CodingKeys: String, CodingKey {
            case postedAt = "posted_at"
            case scheduleType = "schedule_type"
            case workFromHome = "work_from_home"
            case salary
        }
    }

    struct ApplyOption: Codable {
        let title: String?
        let link: String?
    }

    let title: String?
    let companyName: String?
    let location: String?
    let description: String?
    let via: String?
    let shareLink: String?
    let detectedExtensions: DetectedExtensions?
    let applyOptions: [ApplyOption]?

    enum CodingKeys: String, CodingKey {
        case title, location, description, via
        case companyName = "company_name"
        case shareLink = "share_link"
        case detectedExtensions = "detected_extensions"
        case applyOptions = "apply_options"
    }
}

struct SerpApiSearchPayload: Codable {
    let jobsResults: [SerpApiJobResult]?

    var jobs: [SerpApiJobResult] { jobsResults ?? [] }

    enum CodingKeys: String, CodingKey {
        case jobsResults = "jobs_results"
    }
}

// MARK: - Indeed (jobs-api14) wire types

/// One job record from jobs-api14's `/v2/indeed/search` `data[]`. Company and
/// location are nested objects; the search result already carries applyUrl and
/// the full description (no per-job detail call needed). The `*Timestamp`
/// fields are intentionally omitted — the live API returns unusable negative
/// values, and a posted date is display-only.
struct IndeedJobResult: Codable {
    struct Company: Codable {
        let name: String?
        let image: String?
        let addresses: [String]?
    }
    struct Location: Codable {
        let country: String?
        let countryCode: String?
        let location: String?
    }
    let title: String?
    let company: Company?
    let location: Location?
    let applyUrl: String?
    let description: String?
    let id: String?
}

/// jobs-api14's shared response envelope (data + meta + hasError/hasWarning).
struct IndeedSearchPayload: Codable {
    let data: [IndeedJobResult]?
    let hasError: Bool?

    var jobs: [IndeedJobResult] { data ?? [] }
}

// MARK: - Service

enum AggregatorJobSearchService {

    static let jsearchProvider = "JSearch"
    static let serpApiProvider = "SerpApi"
    static let indeedProvider = "Indeed"

    // MARK: JSearch (RapidAPI)

    /// Map the camelCase `datePosted` tool value onto JSearch's `date_posted`
    /// facet. JSearch has no sub-day granularity, so pastHour collapses to
    /// today; unknown/absent means no filter.
    static func jsearchDatePosted(from raw: String?) -> String {
        switch raw {
        case "pastHour", "past24Hours": return "today"
        case "pastWeek": return "week"
        case "pastMonth": return "month"
        default: return "all"
        }
    }

    /// Build the JSearch request (pure — no network). Nil only if URL assembly
    /// fails, which can't happen with a static host.
    static func jsearchRequest(
        keywords: String,
        location: String?,
        datePosted: String?,
        country: String,
        apiKey: String
    ) -> URLRequest? {
        guard var components = URLComponents(string: "https://jsearch.p.rapidapi.com/search-v2") else {
            return nil
        }
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let query = trimmedLocation.isEmpty ? keywords : "\(keywords) in \(trimmedLocation)"
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "num_pages", value: "1"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "date_posted", value: jsearchDatePosted(from: datePosted))
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue("jsearch.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")
        return request
    }

    /// Run a JSearch search and decode the `data[]` payload.
    static func searchJSearch(
        keywords: String,
        location: String?,
        datePosted: String?,
        country: String,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [JSearchJobResult] {
        guard !apiKey.isEmpty else { throw AggregatorSearchError.missingKey(provider: jsearchProvider) }
        guard let request = jsearchRequest(
            keywords: keywords, location: location, datePosted: datePosted, country: country, apiKey: apiKey
        ) else { throw AggregatorSearchError.invalidEndpoint }
        let (data, response) = try await session.data(for: request)
        try validate(response, provider: jsearchProvider)
        do {
            return try JSONDecoder().decode(JSearchSearchPayload.self, from: data).jobs
        } catch {
            throw AggregatorSearchError.malformedPayload(error.localizedDescription)
        }
    }

    // MARK: SerpApi (google_jobs)

    /// Build the SerpApi google_jobs request (pure — no network).
    static func serpApiRequest(
        keywords: String,
        location: String?,
        apiKey: String
    ) -> URLRequest? {
        guard var components = URLComponents(string: "https://serpapi.com/search.json") else {
            return nil
        }
        var items = [
            URLQueryItem(name: "engine", value: "google_jobs"),
            URLQueryItem(name: "q", value: keywords),
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedLocation.isEmpty {
            items.append(URLQueryItem(name: "location", value: trimmedLocation))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        return request
    }

    /// Run a SerpApi google_jobs search and decode the `jobs_results[]` payload.
    static func searchSerpApi(
        keywords: String,
        location: String?,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [SerpApiJobResult] {
        guard !apiKey.isEmpty else { throw AggregatorSearchError.missingKey(provider: serpApiProvider) }
        guard let request = serpApiRequest(keywords: keywords, location: location, apiKey: apiKey) else {
            throw AggregatorSearchError.invalidEndpoint
        }
        let (data, response) = try await session.data(for: request)
        try validate(response, provider: serpApiProvider)
        do {
            return try JSONDecoder().decode(SerpApiSearchPayload.self, from: data).jobs
        } catch {
            throw AggregatorSearchError.malformedPayload(error.localizedDescription)
        }
    }

    // MARK: Indeed (jobs-api14)

    /// The scout's camelCase `datePosted` has no direct Indeed filter; any
    /// recency request just sorts by date instead of relevance.
    static func indeedSortType(from datePosted: String?) -> String {
        datePosted == nil ? "relevance" : "date"
    }

    /// Build the Indeed (jobs-api14) request (pure — no network).
    static func indeedRequest(
        keywords: String,
        location: String?,
        countryCode: String,
        datePosted: String?,
        apiKey: String
    ) -> URLRequest? {
        guard var components = URLComponents(string: "https://jobs-api14.p.rapidapi.com/v2/indeed/search") else {
            return nil
        }
        var items = [
            URLQueryItem(name: "query", value: keywords),
            URLQueryItem(name: "countryCode", value: countryCode),
            URLQueryItem(name: "sortType", value: indeedSortType(from: datePosted))
        ]
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedLocation.isEmpty {
            items.append(URLQueryItem(name: "location", value: trimmedLocation))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue("jobs-api14.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")
        return request
    }

    /// Run an Indeed (jobs-api14) search and decode the `data[]` payload.
    static func searchIndeed(
        keywords: String,
        location: String?,
        countryCode: String,
        datePosted: String?,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [IndeedJobResult] {
        guard !apiKey.isEmpty else { throw AggregatorSearchError.missingKey(provider: indeedProvider) }
        guard let request = indeedRequest(
            keywords: keywords, location: location, countryCode: countryCode, datePosted: datePosted, apiKey: apiKey
        ) else { throw AggregatorSearchError.invalidEndpoint }
        let (data, response) = try await session.data(for: request)
        try validate(response, provider: indeedProvider)
        do {
            return try JSONDecoder().decode(IndeedSearchPayload.self, from: data).jobs
        } catch {
            throw AggregatorSearchError.malformedPayload(error.localizedDescription)
        }
    }

    // MARK: Shared

    private static func validate(_ response: URLResponse, provider: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw AggregatorSearchError.http(provider: provider, statusCode: http.statusCode)
        }
    }
}
