//
//  LinkedInMCPImportService.swift
//  Sprung
//
//  Pure, testable halves of the LinkedIn job-search board: search_jobs
//  argument building (the server's external snake_case wire), search-result
//  decoding (the server returns a JSON-serialized text block, not structured
//  records), canonical job-URL construction, lead mapping/import through the
//  shared two-stage pipeline, the auth-failure classifier, and the rolling
//  hourly call budget. Sibling of JobMCPImportService — JobSearchView keeps
//  only the thin async glue + UI state.
//
//  The board calls exactly ONE tool: `search_jobs`. Job details arrive later
//  via the enrichment path (`get_job_details` — outside this file). Search
//  results carry only stable job ids plus display titles, so leads land
//  title + canonical URL only; company/location/description arrive at
//  enrichment (deterministic-only here, no LLM structuring pass).
//

import Foundation

// MARK: - Wire enums (external snake_case values — the server's contract)

/// `search_jobs`'s `date_posted` facet values.
enum LinkedInDatePosted: String, CaseIterable, Identifiable {
    case pastHour = "past_hour"
    case past24Hours = "past_24_hours"
    case pastWeek = "past_week"
    case pastMonth = "past_month"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pastHour: return "Past hour"
        case .past24Hours: return "Past 24 hours"
        case .pastWeek: return "Past week"
        case .pastMonth: return "Past month"
        }
    }
}

/// `search_jobs`'s `work_type` facet values (comma-separated on the wire).
enum LinkedInWorkType: String, CaseIterable, Identifiable {
    case onSite = "on_site"
    case remote = "remote"
    case hybrid = "hybrid"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onSite: return "On-site"
        case .remote: return "Remote"
        case .hybrid: return "Hybrid"
        }
    }
}

// MARK: - Lead record

/// One deterministically-recoverable search result: a stable numeric job id,
/// the display title matched from the result page's references, and the
/// canonical posting URL built from the id. Company, location, and the
/// description are NOT recoverable from the search payload — they arrive at
/// enrichment.
struct LinkedInJobLead: Identifiable, Hashable {
    let jobID: String
    let title: String
    let canonicalURL: String

    var id: String { jobID }
}

// MARK: - Errors

enum LinkedInImportError: LocalizedError {
    case callBudgetExhausted(limit: Int, nextAvailable: Date?)

    var errorDescription: String? {
        switch self {
        case .callBudgetExhausted(let limit, let nextAvailable):
            if let nextAvailable {
                let time = nextAvailable.formatted(date: .omitted, time: .shortened)
                return "LinkedIn call limit reached (\(limit) calls/hour). Try again after \(time)."
            }
            return "LinkedIn call limit reached (\(limit) calls/hour). Try again later."
        }
    }
}

// MARK: - Rolling hourly call budget

/// A rolling one-hour budget over LinkedIn MCP tool calls (risk rail: the
/// board must never sweep). Timestamps persist in UserDefaults so the cap
/// holds across sheet sessions and app relaunches; entries older than the
/// window are pruned on every read and rewrite. Consult before and record
/// around every `tools/call` — when exhausted, searching disables with an
/// explanation (never silently queues).
struct LinkedInCallBudget {
    static let defaultLimit = 30
    static let window: TimeInterval = 3600
    static let timestampsKey = "linkedInMCPCallTimestamps"

    let limit: Int
    private let defaults: UserDefaults
    private let now: () -> Date

    init(
        limit: Int = LinkedInCallBudget.defaultLimit,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.limit = limit
        self.defaults = defaults
        self.now = now
    }

    /// Calls still available in the current rolling hour.
    func remainingCalls() -> Int {
        max(0, limit - recentTimestamps().count)
    }

    var isExhausted: Bool { remainingCalls() == 0 }

    /// When the oldest in-window call ages out — i.e. the earliest moment a
    /// new call becomes available. Nil while the budget isn't exhausted.
    func nextAvailableDate() -> Date? {
        let recent = recentTimestamps()
        guard recent.count >= limit, let oldest = recent.min() else { return nil }
        return Date(timeIntervalSince1970: oldest).addingTimeInterval(Self.window)
    }

    /// Record one tool call now, rewriting the pruned in-window timestamps.
    func recordCall() {
        var recent = recentTimestamps()
        recent.append(now().timeIntervalSince1970)
        defaults.set(recent, forKey: Self.timestampsKey)
    }

    /// The persisted timestamps still inside the rolling window.
    private func recentTimestamps() -> [Double] {
        let cutoff = now().timeIntervalSince1970 - Self.window
        let stored = defaults.array(forKey: Self.timestampsKey) as? [Double] ?? []
        return stored.filter { $0 > cutoff }
    }
}

// MARK: - Service

enum LinkedInMCPImportService {

    /// The ONLY tool the search board ever calls.
    static let searchToolName = "search_jobs"

    static let sourceLabel = "LinkedIn"

    /// The single loud auth-failure state (auth doctrine): the server's
    /// AUTO_IMPORT_FROM_BROWSER imports the session from a locally logged-in
    /// browser on first tool call — there is no in-app login flow to offer,
    /// only this instruction plus a Retry.
    static let noSessionMessage = "No LinkedIn session. Sign in to linkedin.com in your browser, then search again."

    // MARK: Arguments (external snake_case wire — explicit keys, never convertToSnakeCase)

    /// Build `search_jobs` tool arguments. `keywords` is required; blank
    /// optionals are omitted; `max_pages` hard-defaults to 1 (risk rail:
    /// one page per user-initiated search).
    static func searchArguments(
        keywords: String,
        location: String = "",
        datePosted: LinkedInDatePosted? = nil,
        workTypes: [LinkedInWorkType] = [],
        maxPages: Int = 1
    ) -> [String: Any] {
        var arguments: [String: Any] = [
            "keywords": keywords.trimmingCharacters(in: .whitespacesAndNewlines),
            "max_pages": maxPages
        ]
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLocation.isEmpty {
            arguments["location"] = trimmedLocation
        }
        if let datePosted {
            arguments["date_posted"] = datePosted.rawValue
        }
        if !workTypes.isEmpty {
            arguments["work_type"] = workTypes.map(\.rawValue).joined(separator: ",")
        }
        return arguments
    }

    // MARK: Decode

    /// The server's result payload, JSON-serialized inside the tool result's
    /// text content block: `{url, sections: {name: rawInnerText}, job_ids:
    /// [String], references: {section: [{kind, url, text, context?}]}}`.
    /// External wire → explicit snake_case CodingKeys.
    private struct SearchPayload: Decodable {
        struct Reference: Decodable {
            let kind: String?
            let url: String?
            let text: String?
        }

        let jobIds: [String]?
        let references: [String: [Reference]]?

        private enum CodingKeys: String, CodingKey {
            case jobIds = "job_ids"
            case references
        }
    }

    /// Canonical, stable posting URL for a LinkedIn job id — the dedup key
    /// for this board (stable across sessions, unlike ZipRecruiter's
    /// redirect tokens).
    static func canonicalJobURL(jobID: String) -> String {
        "https://www.linkedin.com/jobs/view/\(jobID)/"
    }

    /// Decode a `search_jobs` text payload into leads. Every entry of
    /// `job_ids` becomes a lead; titles come from the `references` entries of
    /// kind `"job"` whose url contains the id (reference urls may be relative
    /// `/jobs/view/<id>/`). Count mismatches are tolerated — an id without a
    /// matched title keeps a placeholder title and the mismatch is LOGGED,
    /// never silently dropped. A payload missing `job_ids` entirely is
    /// malformed (decode failures must surface — an upstream DOM change must
    /// never read as an honest empty result); an empty `job_ids` array is an
    /// honest zero-result search.
    static func decodeSearchResults(from text: String) throws -> [LinkedInJobLead] {
        guard let data = text.data(using: .utf8) else {
            throw JobMCPImportError.emptyResult
        }
        let payload: SearchPayload
        do {
            payload = try JSONDecoder().decode(SearchPayload.self, from: data)
        } catch {
            throw JobMCPImportError.malformedPayload(error.localizedDescription)
        }
        guard let jobIDs = payload.jobIds else {
            throw JobMCPImportError.malformedPayload("search_jobs payload has no job_ids array")
        }
        let jobReferences = (payload.references ?? [:]).values
            .flatMap { $0 }
            .filter { $0.kind == "job" }

        var leads: [LinkedInJobLead] = []
        var unmatchedIDs: [String] = []
        for jobID in jobIDs where !jobID.isEmpty {
            let match = jobReferences.first { ($0.url ?? "").contains("/jobs/view/\(jobID)") }
            let matchedTitle = match?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String
            if let matchedTitle, !matchedTitle.isEmpty {
                title = matchedTitle
            } else {
                unmatchedIDs.append(jobID)
                title = "LinkedIn job \(jobID)"
            }
            leads.append(LinkedInJobLead(
                jobID: jobID,
                title: title,
                canonicalURL: canonicalJobURL(jobID: jobID)
            ))
        }
        if !unmatchedIDs.isEmpty {
            Logger.warning(
                "⚠️ [LinkedInImport] \(unmatchedIDs.count) of \(jobIDs.count) job ids had no matching job reference (\(unmatchedIDs.joined(separator: ", "))) — kept with placeholder titles",
                category: .networking
            )
        }
        return leads
    }

    // MARK: Search (thin async glue over the pure halves)

    /// Run one `search_jobs` call: consult + record the rolling budget around
    /// the MCP call, then decode the text payload. The budget records before
    /// the call — a failed call still hit LinkedIn and still counts.
    static func searchJobs(
        keywords: String,
        location: String,
        datePosted: LinkedInDatePosted?,
        workTypes: [LinkedInWorkType],
        client: MCPStreamableHTTPClient,
        budget: LinkedInCallBudget
    ) async throws -> [LinkedInJobLead] {
        guard !budget.isExhausted else {
            throw LinkedInImportError.callBudgetExhausted(
                limit: budget.limit,
                nextAvailable: budget.nextAvailableDate()
            )
        }
        budget.recordCall()
        let result = try await client.callTool(
            name: searchToolName,
            arguments: searchArguments(
                keywords: keywords,
                location: location,
                datePosted: datePosted,
                workTypes: workTypes
            )
        )
        guard let text = result.firstText else {
            throw JobMCPImportError.emptyResult
        }
        return try decodeSearchResults(from: text)
    }

    // MARK: Auth-failure classification (auth doctrine)

    /// Whether an error from the LinkedIn MCP server is an auth failure —
    /// the server surfaces session problems as tool/JSON-RPC errors whose
    /// message carries session/authentication language (e.g.
    /// "AuthenticationError: Session expired or invalid"). Matched broadly
    /// but safely: whole auth words only, so unrelated tool failures (rate
    /// limits, DOM churn) never masquerade as a missing session.
    static func isAuthFailure(_ error: Error) -> Bool {
        guard let mcpError = error as? MCPClientError else { return false }
        switch mcpError {
        case .toolError(let message):
            return isAuthFailureMessage(message)
        case .jsonRPCError(_, let message):
            return isAuthFailureMessage(message)
        case .httpError, .malformedResponse:
            return false
        }
    }

    static func isAuthFailureMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let markers = [
            "session", "authentication", "unauthorized", "credential",
            "login", "log in", "logged in", "sign in", "signed in"
        ]
        return markers.contains { lowered.contains($0) }
    }

    // MARK: Mapping + import (shared two-stage lead pipeline)

    /// Map a lead to a fresh `.new` JobApp. Only title and the canonical URL
    /// are known at search time; company/location/description arrive at
    /// enrichment, so they land empty — never guessed.
    static func makeJobApp(from lead: LinkedInJobLead) -> JobApp? {
        guard !lead.jobID.isEmpty, !lead.title.isEmpty else { return nil }
        let jobApp = JobApp()
        jobApp.jobPosition = lead.title
        jobApp.postingURL = lead.canonicalURL
        jobApp.jobApplyLink = lead.canonicalURL
        jobApp.status = .new
        jobApp.identifiedDate = Date()
        jobApp.source = sourceLabel
        return jobApp
    }

    /// Import a lead as a `.new` pipeline lead: dedup through the shared
    /// `JobAppStore.findDuplicateJobApp`, land instantly with preprocessing
    /// deferred, queue background enrichment.
    ///
    /// The canonical URL is the ONLY dedup key for this board: company is
    /// unknown until enrichment, so `findDuplicateJobApp`'s title+company
    /// fallback (with an empty company) would false-match unrelated leads
    /// that share a generic title (real search pages list e.g. two distinct
    /// "Physicist" postings). A fallback hit is therefore accepted only when
    /// the posting URL actually matched.
    @MainActor
    @discardableResult
    static func importAsLead(_ lead: LinkedInJobLead, into store: JobAppStore) -> JobMCPImportService.ImportOutcome {
        guard let jobApp = makeJobApp(from: lead) else {
            return .skipped(reason: "missing job id or title")
        }
        if let existing = store.findDuplicateJobApp(
            url: jobApp.postingURL,
            title: jobApp.jobPosition,
            company: jobApp.companyName
        ), existing.postingURL == jobApp.postingURL {
            return .duplicate(existing)
        }
        guard let inserted = store.addJobApp(jobApp, deferringPreprocessing: true) else {
            return .skipped(reason: "the job couldn't be saved")
        }
        store.leadEnrichment.enqueue(inserted, store: store)
        return .imported(inserted)
    }

    /// Whether a lead's canonical URL is already in the pipeline (for the
    /// "Imported" badge — the same URL-keyed affordance as Dice rows).
    static func isImported(_ lead: LinkedInJobLead, importedURLs: Set<String>) -> Bool {
        importedURLs.contains(lead.canonicalURL)
    }
}
