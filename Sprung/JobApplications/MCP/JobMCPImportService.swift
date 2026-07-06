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
//  result has none at all), and neither MCP server has a job-details tool. So
//  `importAsLead` lands the search result instantly as a `.new` lead with
//  preprocessing deferred, and `JobLeadEnrichmentService` (below) fetches the
//  full posting in the background — reusing JobURLImportService's extraction
//  pass (web search for public boards; the local LinkedIn MCP details tool +
//  text extraction for linkedin.com leads) — then triggers the normal
//  preprocessing on the full text (or on the summary as the fallback when the
//  fetch fails).
//

import Foundation
import SwiftOpenAI

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
    ///
    /// The lead lands instantly with Dice's truncated `summary` as a stand-in
    /// description; preprocessing is deferred to `JobLeadEnrichmentService`,
    /// which fetches the full posting behind `detailsPageUrl` in the
    /// background and then drives the normal preprocessing pass.
    @MainActor
    @discardableResult
    static func importAsLead(_ result: DiceJobResult, into store: JobAppStore) -> ImportOutcome {
        guard let jobApp = makeJobApp(from: result) else {
            return .skipped(reason: "missing title, company, or URL")
        }
        if let existing = store.findDuplicateJobApp(url: jobApp.postingURL, title: jobApp.jobPosition, company: jobApp.companyName) {
            return .duplicate(existing)
        }
        guard let inserted = store.addJobApp(jobApp, deferringPreprocessing: true) else {
            return .skipped(reason: "the job couldn't be saved")
        }
        store.leadEnrichment.enqueue(inserted, store: store)
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
    ///
    /// ZipRecruiter results carry no description at all, so the lead lands
    /// with an empty one and `JobLeadEnrichmentService` fetches the posting
    /// behind `job_redirect_url` in the background (which may fail on bot
    /// protection — the failure is surfaced, and with no summary to fall back
    /// on the lead simply stays unpreprocessed, as it would today).
    @MainActor
    @discardableResult
    static func importAsLead(_ result: ZipRecruiterJobResult, into store: JobAppStore) -> ImportOutcome {
        guard let jobApp = makeJobApp(from: result) else {
            return .skipped(reason: "missing title, company, or redirect URL")
        }
        if let existing = store.findDuplicateJobApp(url: nil, title: jobApp.jobPosition, company: jobApp.companyName) {
            return .duplicate(existing)
        }
        guard let inserted = store.addJobApp(jobApp, deferringPreprocessing: true) else {
            return .skipped(reason: "the job couldn't be saved")
        }
        store.leadEnrichment.enqueue(inserted, store: store)
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

// MARK: - Background lead enrichment

/// Errors from the background full-posting fetch for an MCP-imported lead.
enum JobLeadEnrichmentError: LocalizedError {
    case invalidPostingURL(String)
    case missingOpenAIKey
    case linkedInServerUnavailable
    case noResponse
    case extractionFailed
    case descriptionNotImproved

    var errorDescription: String? {
        switch self {
        case .invalidPostingURL(let url):
            return "The lead's posting URL is invalid: \(url)"
        case .missingOpenAIKey:
            return "An OpenAI API key is required to fetch full job postings. Add one in Settings."
        case .linkedInServerUnavailable:
            return "The local LinkedIn MCP server isn't available, so this LinkedIn lead can't be enriched."
        case .noResponse:
            return "The extraction model returned no response."
        case .extractionFailed:
            return "Couldn't extract job details from the posting page."
        case .descriptionNotImproved:
            return "The fetched page didn't yield a fuller job description than the search summary."
        }
    }
}

/// Fetches the full posting behind an MCP-imported lead in the background,
/// then triggers the normal preprocessing pass — so preprocessing runs on the
/// real job description, never on Dice's ~500-char truncated `summary` (or
/// ZipRecruiter's absent description) when the full text is reachable.
///
/// Flow per lead (see `enqueue`):
///  1. `importAsLead` lands the `.new` lead instantly — the user never waits —
///     with preprocessing deferred (`JobAppStore.addJobApp(_:deferringPreprocessing:)`).
///  2. This service, throttled to `maxConcurrentEnrichments` so a bulk
///     "Import All as Leads" can't stampede N web-search calls, fetches the
///     posting via the same JobURLImportService extraction pass that
///     NewAppSheetView's URL import drives (Dice's `detailsPageUrl`;
///     ZipRecruiter's `job_redirect_url`, which may fail on bot protection).
///     Leads whose posting host is linkedin.com route through the local
///     LinkedIn MCP server's `get_job_details` + the text-input extraction
///     instead (the public web path dead-ends at LinkedIn's authwall) — one
///     deterministic rule, `isLinkedInPostingHost`.
///  3. On success it stores the full description and runs the standard
///     preprocessing. On failure the summary stays as the description,
///     preprocessing falls back to it (when non-empty), and the failure is
///     surfaced (Logger + error toast) — never silently discarded.
@MainActor
final class JobLeadEnrichmentService {

    /// Maximum in-flight full-posting fetches. Small on purpose: a bulk import
    /// enqueues every lead on the page at once, and each fetch is a
    /// web-search LLM pass.
    static let maxConcurrentEnrichments = 3

    /// Whether a lead's posting host routes through the LinkedIn MCP details
    /// path instead of the web-search extraction. Matches linkedin.com and
    /// its subdomains only — never lookalike hosts.
    static func isLinkedInPostingHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "linkedin.com" || host.hasSuffix(".linkedin.com")
    }

    /// The app-lifetime LinkedIn MCP server service, wired by AppDependencies
    /// (same setter-injection pattern as `setActivityTracker`). LinkedIn leads
    /// fail enrichment loudly when it's absent.
    private weak var linkedInServerService: LinkedInMCPServerService?

    /// Set the server service used for linkedin.com lead enrichment.
    func setLinkedInServerService(_ service: LinkedInMCPServerService) {
        self.linkedInServerService = service
    }

    private struct PendingLead {
        let jobAppID: UUID
        /// The lead's description at enqueue time (the board summary; empty
        /// for ZipRecruiter). If it differs by the time this lead is
        /// processed, the user edited the lead and `JobAppStore.saveForm`
        /// already drove preprocessing on their text — enrichment backs off
        /// rather than clobber a user edit.
        let descriptionAtEnqueue: String
        weak var store: JobAppStore?
    }

    private var pending: [PendingLead] = []
    private var activeCount = 0
    private weak var activityTracker: BackgroundActivityTracker?

    /// Set the tracker that surfaces per-lead enrichment in the Background
    /// Activity window and the main-window indicator.
    func setActivityTracker(_ tracker: BackgroundActivityTracker) {
        self.activityTracker = tracker
    }

    /// True when the process hosts the XCTest bundle. Mirrors
    /// `DiscoveryCoordinator.isRunningUnitTests`: the test suite launches the
    /// full app, so automatic LLM work must never fire under XCTest.
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    // MARK: Queue

    /// Queue a freshly imported lead for full-posting enrichment. Runs at most
    /// `maxConcurrentEnrichments` fetches at a time; the rest wait their turn.
    func enqueue(_ jobApp: JobApp, store: JobAppStore) {
        guard !Self.isRunningUnitTests else { return }
        pending.append(PendingLead(
            jobAppID: jobApp.id,
            descriptionAtEnqueue: jobApp.jobDescription,
            store: store
        ))
        processNextIfAvailable()
    }

    private func processNextIfAvailable() {
        guard activeCount < Self.maxConcurrentEnrichments, !pending.isEmpty else { return }
        let lead = pending.removeFirst()
        activeCount += 1
        Task {
            await enrich(lead)
            activeCount -= 1
            processNextIfAvailable()
        }
    }

    // MARK: Per-lead enrichment

    private func enrich(_ lead: PendingLead) async {
        // Re-resolve by ID: the lead may have been deleted (or the store torn
        // down) between enqueue and now.
        guard let store = lead.store, let jobApp = store.jobApp(byId: lead.jobAppID) else {
            Logger.info("ℹ️ [LeadEnrichment] Lead gone before enrichment ran — skipping", category: .ai)
            return
        }
        guard jobApp.jobDescription == lead.descriptionAtEnqueue else {
            Logger.info("ℹ️ [LeadEnrichment] Description edited before enrichment ran for \(jobApp.jobPosition) — keeping the user's text", category: .ai)
            return
        }

        // Snapshot everything the fetch and its logging need — the model must
        // not be touched across the await (it can be deleted mid-fetch).
        let title = jobApp.jobPosition
        let leadName = "\(jobApp.jobPosition) at \(jobApp.companyName)"
        let postingURL = jobApp.postingURL

        // Surface the fetch in the background-activity UI: one operation per
        // lead. The preprocessing pass it hands off to is tracked separately
        // (as `.preprocessing`) by JobAppPreprocessor.
        let operationId = UUID().uuidString
        activityTracker?.trackOperation(
            id: operationId,
            type: .leadEnrichment,
            name: "\(jobApp.jobPosition) — \(jobApp.companyName)"
        )
        activityTracker?.updatePhase(operationId: operationId, phase: "Fetching full posting")

        do {
            let fullDescription = try await fetchFullDescription(
                postingURL: postingURL,
                currentDescription: lead.descriptionAtEnqueue
            )
            // The user may have edited or deleted the lead while the fetch ran.
            guard let liveJobApp = store.jobApp(byId: lead.jobAppID),
                  liveJobApp.jobDescription == lead.descriptionAtEnqueue else {
                Logger.info("ℹ️ [LeadEnrichment] Lead changed while fetching \(leadName) — discarding fetched description", category: .ai)
                activityTracker?.appendTranscript(
                    operationId: operationId,
                    entryType: .system,
                    content: "Lead edited while fetching — fetched description discarded"
                )
                activityTracker?.markCompleted(operationId: operationId)
                return
            }
            liveJobApp.jobDescription = fullDescription
            store.updateJobApp(liveJobApp)
            Logger.info("✅ [LeadEnrichment] Full posting fetched for \(leadName) (\(lead.descriptionAtEnqueue.count) → \(fullDescription.count) chars)", category: .ai)
            activityTracker?.appendTranscript(
                operationId: operationId,
                entryType: .system,
                content: "Full posting fetched (\(lead.descriptionAtEnqueue.count) → \(fullDescription.count) chars)"
            )
            activityTracker?.updatePhase(operationId: operationId, phase: "Queued for preprocessing")
            store.rerunPreprocessing(for: liveJobApp)
            activityTracker?.markCompleted(operationId: operationId)
        } catch {
            Logger.error("❌ [LeadEnrichment] Full-posting fetch failed for \(leadName) (\(postingURL)): \(error.localizedDescription)", category: .ai)
            activityTracker?.markFailed(operationId: operationId, error: error.localizedDescription)
            // Fall back only when the lead still exists with its imported
            // summary intact (an edit mid-fetch already drove preprocessing).
            guard let liveJobApp = store.jobApp(byId: lead.jobAppID),
                  liveJobApp.jobDescription == lead.descriptionAtEnqueue else {
                return
            }
            ToastCenter.shared.show(
                .error("Couldn't fetch the full posting for \"\(title)\" — using the search summary instead.")
            )
            if liveJobApp.jobDescription.isEmpty {
                // ZipRecruiter lead with no summary: nothing to preprocess.
                Logger.warning("⚠️ [LeadEnrichment] \(leadName) has no summary to fall back on — preprocessing skipped", category: .ai)
            } else {
                store.rerunPreprocessing(for: liveJobApp)
            }
        }
    }

    /// Fetch the posting and extract the full description, reusing
    /// JobURLImportService's request/parse halves (the same extraction pass
    /// NewAppSheetView drives). Routed by posting host: linkedin.com leads go
    /// through the local MCP details tool + text extraction, everything else
    /// through the web-search extraction.
    private func fetchFullDescription(postingURL: String, currentDescription: String) async throws -> String {
        guard let url = URL(string: postingURL), url.scheme != nil else {
            throw JobLeadEnrichmentError.invalidPostingURL(postingURL)
        }
        let outputText: String
        if Self.isLinkedInPostingHost(url.host) {
            outputText = try await fetchLinkedInExtractionText(postingURL: postingURL)
        } else {
            outputText = try await fetchWebSearchExtractionText(url: url)
        }
        guard let parsed = JobURLImportService.parseJob(from: outputText, sourceURL: postingURL) else {
            throw JobLeadEnrichmentError.extractionFailed
        }
        guard let accepted = Self.acceptedFullDescription(parsed.jobDescription, current: currentDescription) else {
            throw JobLeadEnrichmentError.descriptionNotImproved
        }
        return accepted
    }

    /// LinkedIn leads: the posting text comes from the local MCP server's
    /// `get_job_details` (the public web path hits LinkedIn's authwall) and
    /// the extraction runs on that text — no web search.
    private func fetchLinkedInExtractionText(postingURL: String) async throws -> String {
        guard let jobId = LinkedInJobDetailsService.jobId(fromURL: postingURL) else {
            throw JobLeadEnrichmentError.invalidPostingURL(postingURL)
        }
        guard let serverService = linkedInServerService else {
            throw JobLeadEnrichmentError.linkedInServerUnavailable
        }
        // Resolve the extraction config up front — no point spending a
        // budgeted LinkedIn call when the extraction can't run.
        guard let apiKey = APIKeyStore.get(.openAI), !apiKey.isEmpty else {
            throw JobLeadEnrichmentError.missingOpenAIKey
        }
        let modelId = try JobURLImportService.requireJobImportModelId(operationName: "Job Lead Enrichment")
        let postingText = try await LinkedInJobDetailsService.fetchPostingText(
            jobId: jobId,
            serverService: serverService
        )
        return try await runExtraction(
            JobURLImportService.buildTextParameters(postingText: postingText, modelId: modelId),
            apiKey: apiKey
        )
    }

    /// Every other board: the same web-search extraction pass NewAppSheetView's
    /// URL import drives.
    private func fetchWebSearchExtractionText(url: URL) async throws -> String {
        guard let apiKey = APIKeyStore.get(.openAI), !apiKey.isEmpty else {
            throw JobLeadEnrichmentError.missingOpenAIKey
        }
        let modelId = try JobURLImportService.requireJobImportModelId(operationName: "Job Lead Enrichment")
        return try await runExtraction(
            JobURLImportService.buildParameters(url: url, modelId: modelId),
            apiKey: apiKey
        )
    }

    /// Drain one OpenAI Responses stream to its completed response text.
    private func runExtraction(_ parameters: ModelResponseParameter, apiKey: String) async throws -> String {
        let service = OpenAIServiceFactory.service(apiKey: apiKey)
        var finalResponse: ResponseModel?
        let stream = try await service.responseCreateStream(parameters)
        for try await event in stream {
            if case .responseCompleted(let completed) = event {
                finalResponse = completed.response
            }
        }
        guard let response = finalResponse else {
            throw JobLeadEnrichmentError.noResponse
        }
        guard let outputText = JobURLImportService.extractResponseText(from: response) else {
            throw JobLeadEnrichmentError.extractionFailed
        }
        return outputText
    }

    // MARK: Pure half

    /// Adopt a fetched description only when it genuinely improves on the
    /// current one: non-empty, not the extractor's "Not specified" filler,
    /// and strictly longer than what's already stored. A Dice `summary` is a
    /// truncation of the real posting, so a legitimate fetch is always
    /// longer — a shorter result means the extractor hit a bot wall or the
    /// wrong page, and the summary is the higher-quality input. Returns the
    /// trimmed description to store, or nil to reject the fetch.
    static func acceptedFullDescription(_ fetched: String, current: String) -> String? {
        let trimmedFetched = fetched.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFetched.isEmpty else { return nil }
        guard trimmedFetched.lowercased() != "not specified" else { return nil }
        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedFetched.count > trimmedCurrent.count else { return nil }
        return trimmedFetched
    }
}
