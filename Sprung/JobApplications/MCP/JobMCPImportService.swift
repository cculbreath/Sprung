//
//  JobMCPImportService.swift
//  Sprung
//
//  Pure, testable halves of the "search a job board over MCP and import
//  results as pipeline leads" flow, for both boards this app searches: Dice
//  and ZipRecruiter. Each board gets its own search_jobs argument builder,
//  result-payload decode, and result → JobApp mapping; both route duplicate
//  detection through `JobAppStore.findDuplicateJobApp`. JobSearchView keeps
//  only the thin async glue + UI state, mirroring how JobURLImportService
//  backs NewAppSheetView.
//
//  Imports are two-stage by design: neither board's search result carries a
//  full description (Dice's `summary` is truncated ~500 chars; ZipRecruiter's
//  result has none at all), and neither MCP server has a job-details tool, so
//  a search result lands as a `.new` lead and full-description enrichment
//  happens later through the existing per-URL import path when the user
//  advances the card.
//

import Foundation

enum JobMCPImportError: LocalizedError {
    case invalidEndpoint
    case emptyResult
    case malformedPayload(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The MCP endpoint URL is invalid."
        case .emptyResult:
            return "The MCP server returned no result content."
        case .malformedPayload(let detail):
            return "Couldn't decode the job search results: \(detail)"
        }
    }
}

// MARK: - Dice wire types

/// One job record from Dice's `search_jobs` tool. Dice emits camelCase keys,
/// so property names match the wire exactly — no CodingKeys needed.
struct DiceJobResult: Codable, Identifiable, Hashable {
    struct Location: Codable, Hashable {
        let displayName: String?
    }

    let id: String
    let title: String?
    let summary: String?
    let postedDate: String?
    let jobLocation: Location?
    let detailsPageUrl: String?
    let salary: String?
    let companyName: String?
    let employmentType: String?
    let employerType: String?
    let workplaceTypes: [String]?
    let easyApply: Bool?
    let willingToSponsor: Bool?
}

/// Pagination metadata from the search payload's `meta` object.
struct DiceSearchMeta: Codable {
    let currentPage: Int?
    let pageCount: Int?
    let pageSize: Int?
    let totalResults: Int?
}

/// Top-level payload inside the tool result's text content block.
struct DiceSearchPayload: Codable {
    let data: [DiceJobResult]?
    let meta: DiceSearchMeta?

    var jobs: [DiceJobResult] { data ?? [] }
}

// MARK: - Search query

/// User-facing search parameters, translated to Dice's snake_case tool
/// arguments (external wire format — explicit keys, never convertToSnakeCase)
/// by `toolArguments`.
struct DiceSearchQuery {
    var keyword: String
    var location: String = ""
    /// One of `""` (any), "Remote", "On-Site", "Hybrid" — Dice's facet values.
    var workplaceType: String = ""
    var pageNumber: Int = 1
    var jobsPerPage: Int = 20

    var toolArguments: [String: Any] {
        var arguments: [String: Any] = [
            "keyword": keyword,
            "jobs_per_page": jobsPerPage,
            "page_number": pageNumber
        ]
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLocation.isEmpty {
            arguments["location"] = trimmedLocation
        }
        if !workplaceType.isEmpty {
            arguments["workplace_types"] = [workplaceType]
        }
        return arguments
    }
}

// MARK: - Service

enum JobMCPImportService {

    static let diceToolName = "search_jobs"
    static let diceWorkplaceTypes = ["Remote", "On-Site", "Hybrid"]
    private static let diceEndpointString = "https://mcp.dice.com/mcp"
    private static let iso8601Formatter = ISO8601DateFormatter()

    /// Build a client for Dice's public (unauthenticated) MCP server.
    static func makeDiceClient() throws -> MCPStreamableHTTPClient {
        guard let endpoint = URL(string: diceEndpointString) else {
            throw JobMCPImportError.invalidEndpoint
        }
        return MCPStreamableHTTPClient(endpoint: endpoint)
    }

    /// Run a Dice search over MCP and decode the result payload.
    static func searchDice(_ query: DiceSearchQuery, client: MCPStreamableHTTPClient) async throws -> DiceSearchPayload {
        let result = try await client.callTool(name: diceToolName, arguments: query.toolArguments)
        guard let text = result.firstText, let data = text.data(using: .utf8) else {
            throw JobMCPImportError.emptyResult
        }
        do {
            return try JSONDecoder().decode(DiceSearchPayload.self, from: data)
        } catch {
            throw JobMCPImportError.malformedPayload(error.localizedDescription)
        }
    }

    // MARK: - Mapping

    /// Dice appends client-dependent `utm_*` query parameters to
    /// `detailsPageUrl`; the path (`/job-detail/<guid>`) is the stable identity.
    /// Strip the query + fragment so the stored URL dedups across sessions.
    static func normalizedPostingURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return raw }
        components.query = nil
        components.fragment = nil
        return components.string ?? raw
    }

    /// Human-readable rendering of Dice's ISO 8601 `postedDate`; the raw string
    /// is kept when it isn't parseable so no information is dropped.
    static func displayPostedDate(_ isoString: String) -> String {
        guard let date = iso8601Formatter.date(from: isoString) else { return isoString }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Map a Dice result to a fresh `.new` JobApp lead. Returns nil when the
    /// record lacks the essentials (title, company, URL) for a useful card.
    static func makeJobApp(from result: DiceJobResult) -> JobApp? {
        guard let title = result.title, !title.isEmpty,
              let company = result.companyName, !company.isEmpty,
              let rawURL = result.detailsPageUrl, !rawURL.isEmpty else {
            return nil
        }
        let postingURL = normalizedPostingURL(rawURL)
        let jobApp = JobApp()
        jobApp.jobPosition = title
        jobApp.companyName = company
        jobApp.jobLocation = result.jobLocation?.displayName ?? ""
        jobApp.jobDescription = result.summary ?? ""
        jobApp.postingURL = postingURL
        jobApp.jobApplyLink = postingURL
        if let salary = result.salary, !salary.isEmpty {
            jobApp.salary = salary
        }
        if let postedDate = result.postedDate, !postedDate.isEmpty {
            jobApp.jobPostingTime = displayPostedDate(postedDate)
        }
        var employmentParts: [String] = []
        if let employmentType = result.employmentType, !employmentType.isEmpty {
            employmentParts.append(employmentType)
        }
        if let workplaceTypes = result.workplaceTypes, !workplaceTypes.isEmpty {
            employmentParts.append("(\(workplaceTypes.joined(separator: ", ")))")
        }
        jobApp.employmentType = employmentParts.joined(separator: " ")
        jobApp.status = .new
        jobApp.identifiedDate = Date()
        jobApp.source = "Dice"
        return jobApp
    }

    // MARK: - ZipRecruiter wire types

    /// `search_jobs`'s salary range for one result. ZipRecruiter emits
    /// snake_case keys, so this uses explicit `CodingKeys` (external wire
    /// format) rather than camelCase-matching property names.
    struct ZipRecruiterSalary: Codable, Hashable {
        let minAnnual: Int?
        let maxAnnual: Int?

        private enum CodingKeys: String, CodingKey {
            case minAnnual = "min_annual"
            case maxAnnual = "max_annual"
        }
    }

    /// One job record from ZipRecruiter's `search_jobs` tool
    /// (`structuredContent.results[]`).
    struct ZipRecruiterJobResult: Codable, Identifiable, Hashable {
        let title: String?
        let company: String?
        let location: String?
        let isRemote: Bool?
        let salary: ZipRecruiterSalary?
        let companyLogo: String?
        /// An unstable match-token redirect to the listing on ZipRecruiter —
        /// fine to store as the lead's URL for the user to open, but never
        /// stable enough to dedup on (see `makeJobApp` / `importAsLead`).
        let jobRedirectUrl: String?
        let jobType: String?
        let benefits: String?
        let daysAgo: Int?

        var id: String {
            jobRedirectUrl ?? "\(title ?? "")|\(company ?? "")|\(location ?? "")"
        }

        private enum CodingKeys: String, CodingKey {
            case title, company, location, salary, benefits
            case isRemote = "is_remote"
            case companyLogo = "company_logo"
            case jobRedirectUrl = "job_redirect_url"
            case jobType = "job_type"
            case daysAgo = "days_ago"
        }
    }

    /// Pagination + result-count metadata from `structuredContent.meta`.
    struct ZipRecruiterSearchMeta: Codable {
        let count: Int
        let limit: Int
        let total: Int
        /// Absent from `meta` when a request omitted `offset` (defaults to 0
        /// server-side); optional here rather than defaulted so callers can
        /// tell "server didn't say" from "server said zero."
        let offset: Int?
    }

    /// The tool result's `structuredContent` object — a sibling of the text
    /// content block, not something decoded from `firstText` (ZipRecruiter's
    /// text block re-wraps the same payload one level deeper, under its own
    /// `"structuredContent"` key, which callers don't need).
    struct ZipRecruiterSearchPayload: Codable {
        let results: [ZipRecruiterJobResult]?
        let meta: ZipRecruiterSearchMeta?
        let status: String?
        let warnings: [String]?

        var jobs: [ZipRecruiterJobResult] { results ?? [] }
    }

    // MARK: - ZipRecruiter search query

    /// User-facing search parameters, translated to ZipRecruiter's snake_case
    /// tool arguments (external wire format — explicit keys, never
    /// convertToSnakeCase) by `toolArguments`.
    struct ZipRecruiterSearchQuery {
        var jobRole: String = ""
        var location: String = ""
        /// One of `""` (any), "REMOTE", "HYBRID", "PHYSICAL" — ZipRecruiter's
        /// `location_types` facet.
        var locationType: String = ""
        var offset: Int = 0

        var toolArguments: [String: Any] {
            var arguments: [String: Any] = [:]
            let trimmedRole = jobRole.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedRole.isEmpty {
                arguments["job_role"] = trimmedRole
            }
            let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLocation.isEmpty {
                arguments["location"] = trimmedLocation
            }
            if !locationType.isEmpty {
                arguments["location_types"] = [locationType]
            }
            if offset > 0 {
                arguments["offset"] = offset
            }
            return arguments
        }
    }

    // MARK: - ZipRecruiter service

    static let zipRecruiterToolName = "search_jobs"
    static let zipRecruiterLocationTypes = ["REMOTE", "HYBRID", "PHYSICAL"]
    private static let zipRecruiterEndpointString = "https://api.ziprecruiter.com/mcp"

    /// Build a client for ZipRecruiter's public (unauthenticated) MCP server.
    static func makeZipRecruiterClient() throws -> MCPStreamableHTTPClient {
        guard let endpoint = URL(string: zipRecruiterEndpointString) else {
            throw JobMCPImportError.invalidEndpoint
        }
        return MCPStreamableHTTPClient(endpoint: endpoint)
    }

    /// Run a ZipRecruiter search over MCP and decode the result payload from
    /// the tool result's `structuredContent` object.
    static func searchZipRecruiter(_ query: ZipRecruiterSearchQuery, client: MCPStreamableHTTPClient) async throws -> ZipRecruiterSearchPayload {
        let result = try await client.callTool(name: zipRecruiterToolName, arguments: query.toolArguments)
        guard let structuredContent = result.structuredContent else {
            throw JobMCPImportError.emptyResult
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: structuredContent)
            return try JSONDecoder().decode(ZipRecruiterSearchPayload.self, from: data)
        } catch {
            throw JobMCPImportError.malformedPayload(error.localizedDescription)
        }
    }

    // MARK: - ZipRecruiter mapping

    /// Human-readable rendering of a salary range; nil when neither bound is
    /// present.
    static func displaySalaryRange(_ salary: ZipRecruiterSalary?) -> String? {
        guard let salary else { return nil }
        func dollars(_ amount: Int) -> String { "$\(amount.formatted(.number))" }
        switch (salary.minAnnual, salary.maxAnnual) {
        case let (.some(minAnnual), .some(maxAnnual)):
            return "\(dollars(minAnnual)) – \(dollars(maxAnnual))"
        case let (.some(minAnnual), .none):
            return "\(dollars(minAnnual))+"
        case let (.none, .some(maxAnnual)):
            return "Up to \(dollars(maxAnnual))"
        case (.none, .none):
            return nil
        }
    }

    /// Human-readable rendering of ZipRecruiter's `days_ago`, mirroring
    /// Dice's `displayPostedDate`: an abbreviated calendar date, computed by
    /// subtracting the day count from now.
    static func displayDaysAgo(_ daysAgo: Int) -> String {
        guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) else {
            return "\(daysAgo) day\(daysAgo == 1 ? "" : "s") ago"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Map a ZipRecruiter result to a fresh `.new` JobApp lead. Returns nil
    /// when the record lacks the essentials (title, company, redirect URL)
    /// for a useful card. `benefits` has no comparable `JobApp` field, so it's
    /// intentionally dropped rather than stuffed into an unrelated one.
    static func makeJobApp(from result: ZipRecruiterJobResult) -> JobApp? {
        guard let title = result.title, !title.isEmpty,
              let company = result.company, !company.isEmpty,
              let redirectURL = result.jobRedirectUrl, !redirectURL.isEmpty else {
            return nil
        }
        let jobApp = JobApp()
        jobApp.jobPosition = title
        jobApp.companyName = company
        let location = result.location ?? ""
        if result.isRemote == true {
            jobApp.jobLocation = location.isEmpty ? "Remote" : "\(location) (Remote)"
        } else {
            jobApp.jobLocation = location
        }
        jobApp.postingURL = redirectURL
        jobApp.jobApplyLink = redirectURL
        if let salaryDisplay = displaySalaryRange(result.salary) {
            jobApp.salary = salaryDisplay
        }
        if let daysAgo = result.daysAgo {
            jobApp.jobPostingTime = displayDaysAgo(daysAgo)
        }
        if let jobType = result.jobType, !jobType.isEmpty {
            jobApp.employmentType = jobType
        }
        jobApp.status = .new
        jobApp.identifiedDate = Date()
        jobApp.source = "ZipRecruiter"
        return jobApp
    }

    // MARK: - Import

    enum ImportOutcome {
        case imported(JobApp)
        case duplicate(JobApp)
        case skipped(reason: String)
    }

    /// Import a Dice result as a `.new` pipeline lead. Dedup runs through the
    /// shared `JobAppStore.findDuplicateJobApp` (URL match, falling back to
    /// title+company) — `JobAppStore.addJobApp` itself doesn't dedup.
    @MainActor
    @discardableResult
    static func importAsLead(_ result: DiceJobResult, into store: JobAppStore) -> ImportOutcome {
        guard let jobApp = makeJobApp(from: result) else {
            return .skipped(reason: "missing title, company, or URL")
        }
        if let existing = store.findDuplicateJobApp(url: jobApp.postingURL, title: jobApp.jobPosition, company: jobApp.companyName) {
            return .duplicate(existing)
        }
        guard let inserted = store.addJobApp(jobApp) else {
            return .skipped(reason: "the job couldn't be saved")
        }
        return .imported(inserted)
    }

    /// The set of already-imported posting URLs, for dedup badges in search results.
    @MainActor
    static func importedPostingURLs(in store: JobAppStore) -> Set<String> {
        Set(store.jobApps.map(\.postingURL))
    }

    /// Whether a search result's stable URL is already in the pipeline.
    static func isImported(_ result: DiceJobResult, importedURLs: Set<String>) -> Bool {
        guard let rawURL = result.detailsPageUrl else { return false }
        return importedURLs.contains(normalizedPostingURL(rawURL))
    }

    /// Import a ZipRecruiter result as a `.new` pipeline lead. `job_redirect_url`
    /// is an unstable match-token redirect, so dedup is title+company only
    /// (`JobAppStore.findDuplicateJobApp` with `url: nil`), never URL-based.
    @MainActor
    @discardableResult
    static func importAsLead(_ result: ZipRecruiterJobResult, into store: JobAppStore) -> ImportOutcome {
        guard let jobApp = makeJobApp(from: result) else {
            return .skipped(reason: "missing title, company, or redirect URL")
        }
        if let existing = store.findDuplicateJobApp(url: nil, title: jobApp.jobPosition, company: jobApp.companyName) {
            return .duplicate(existing)
        }
        guard let inserted = store.addJobApp(jobApp) else {
            return .skipped(reason: "the job couldn't be saved")
        }
        return .imported(inserted)
    }

    /// A title+company pairing, for boards (ZipRecruiter) whose result URLs
    /// are too unstable to dedup badges on.
    struct TitleCompanyPair: Hashable {
        let title: String
        let company: String
    }

    /// The set of already-imported (title, company) pairs, for dedup badges
    /// in ZipRecruiter search results.
    @MainActor
    static func importedTitleCompanyPairs(in store: JobAppStore) -> Set<TitleCompanyPair> {
        Set(store.jobApps.map { TitleCompanyPair(title: $0.jobPosition, company: $0.companyName) })
    }

    /// Whether a search result's title+company is already in the pipeline.
    static func isImported(_ result: ZipRecruiterJobResult, importedPairs: Set<TitleCompanyPair>) -> Bool {
        guard let title = result.title, let company = result.company else { return false }
        return importedPairs.contains(TitleCompanyPair(title: title, company: company))
    }
}
