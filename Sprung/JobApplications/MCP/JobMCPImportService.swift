//
//  JobMCPImportService.swift
//  Sprung
//
//  Pure, testable halves of the "search a job board over MCP and import
//  results as pipeline leads" flow: the Dice search_jobs argument builder,
//  the result-payload decode, and the result → JobApp mapping with URL dedup.
//  JobSearchView keeps only the thin async glue + UI state, mirroring how
//  JobURLImportService backs NewAppSheetView.
//
//  Imports are two-stage by design: Dice's `summary` is truncated (~500 chars)
//  and its MCP server has no details tool, so a search result lands as a `.new`
//  lead and full-description enrichment happens later through the existing
//  per-URL import path when the user advances the card.
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

    // MARK: - Import

    enum ImportOutcome {
        case imported(JobApp)
        case duplicate(JobApp)
        case skipped(reason: String)
    }

    /// Import a Dice result as a `.new` pipeline lead. Dedup follows the Indeed
    /// import convention: a job whose `postingURL` already exists is returned
    /// untouched instead of inserted (`JobAppStore.addJobApp` itself doesn't dedup).
    @MainActor
    @discardableResult
    static func importAsLead(_ result: DiceJobResult, into store: JobAppStore) -> ImportOutcome {
        guard let jobApp = makeJobApp(from: result) else {
            return .skipped(reason: "missing title, company, or URL")
        }
        if let existing = store.jobApps.first(where: { $0.postingURL == jobApp.postingURL }) {
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
}
