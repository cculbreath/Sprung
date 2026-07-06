//
//  LinkedInJobDetailsService.swift
//  Sprung
//
//  The single LinkedIn job-detail path: fetch a posting's text over the local
//  MCP server's `get_job_details` tool (replacing the deleted WKWebView
//  scraper). The pure halves — job-id extraction from pasted URLs and the
//  result payload → posting text decode — are static and unit-tested; the
//  async fetch is thin glue over `LinkedInMCPServerService` and
//  `MCPStreamableHTTPClient`. The auth doctrine (one loud "sign in to
//  linkedin.com in your browser" state), the auth-failure classifier, the
//  canonical job URL, and the rolling hourly call budget are all shared with
//  the search board (LinkedInMCPImportService) — one source each.
//

import Foundation

enum LinkedInJobDetailsError: LocalizedError {
    /// The MCP server reported an authentication/session failure. The one
    /// recovery path is the user's own browser session (auth doctrine).
    case noSession
    case emptyResult
    case malformedPayload(String)
    case missingPostingSection

    var errorDescription: String? {
        switch self {
        case .noSession:
            return LinkedInMCPImportService.noSessionMessage
        case .emptyResult:
            return "The LinkedIn MCP server returned no result content."
        case .malformedPayload(let detail):
            return "Couldn't decode the LinkedIn job details payload: \(detail)"
        case .missingPostingSection:
            return "The LinkedIn job details payload has no job posting text."
        }
    }
}

enum LinkedInJobDetailsService {

    /// The only LinkedIn MCP tool this path ever calls.
    static let toolName = "get_job_details"

    // MARK: - Job-id extraction (pure)

    /// Extract the numeric job id from a LinkedIn URL. Handles:
    ///  - `/jobs/view/<id>/` (with or without trailing slash, trailing
    ///    segments, or a query string)
    ///  - slug forms like `/jobs/view/some-role-at-some-co-<id>/`
    ///  - `currentJobId=<id>` query forms (search results, collections pages)
    /// Returns nil for any URL that names no job — the caller routes those
    /// through the generic URL importer like any other host.
    static func jobId(fromURL urlString: String) -> String? {
        guard let components = URLComponents(string: urlString) else { return nil }

        if let currentJobId = components.queryItems?.first(where: { $0.name == "currentJobId" })?.value,
           isNumericId(currentJobId) {
            return currentJobId
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)
        guard let viewIndex = pathComponents.firstIndex(of: "view"),
              viewIndex > 0, pathComponents[viewIndex - 1] == "jobs",
              pathComponents.count > viewIndex + 1 else {
            return nil
        }
        let candidate = pathComponents[viewIndex + 1]
        if isNumericId(candidate) {
            return candidate
        }
        // Slug form: the id is the trailing digit run after the last hyphen.
        let trailingDigits = String(candidate.reversed().prefix(while: { $0.isASCII && $0.isNumber }).reversed())
        if !trailingDigits.isEmpty, candidate.dropLast(trailingDigits.count).hasSuffix("-") {
            return trailingDigits
        }
        return nil
    }

    private static func isNumericId(_ candidate: String) -> Bool {
        !candidate.isEmpty && candidate.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: - Payload decode (pure)

    /// The tool result's text block is a JSON-serialized page capture:
    /// `{url, sections: {name: rawInnerText}, job_ids: [...], references: {...}}`.
    /// Only `sections.job_posting` matters here.
    private struct DetailsPayload: Decodable {
        let sections: [String: String]?
    }

    /// Decode the posting's raw innerText out of a `get_job_details` result
    /// text block. Throws loudly on malformed JSON or a missing/empty
    /// `job_posting` section — never returns partial content.
    static func postingText(fromResultText text: String) throws -> String {
        guard let data = text.data(using: .utf8) else {
            throw LinkedInJobDetailsError.malformedPayload("result text is not UTF-8")
        }
        let payload: DetailsPayload
        do {
            payload = try JSONDecoder().decode(DetailsPayload.self, from: data)
        } catch {
            throw LinkedInJobDetailsError.malformedPayload(error.localizedDescription)
        }
        guard let posting = payload.sections?["job_posting"],
              !posting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LinkedInJobDetailsError.missingPostingSection
        }
        return posting
    }

    // MARK: - Fetch

    /// Fetch the posting text for a job id: ensure the local MCP server is
    /// running, consult/record the shared hourly call budget, call
    /// `get_job_details`, and decode `sections.job_posting`. An auth-failure
    /// tool result maps to `LinkedInJobDetailsError.noSession` (the single
    /// user-facing auth state); every other failure propagates as-is.
    @MainActor
    static func fetchPostingText(
        jobId: String,
        serverService: LinkedInMCPServerService
    ) async throws -> String {
        try await serverService.ensureRunning()

        // The same rolling hourly rail as the search board: consult before
        // the call, record the attempt (success or not, it hits LinkedIn).
        let budget = LinkedInCallBudget()
        guard !budget.isExhausted else {
            throw LinkedInImportError.callBudgetExhausted(
                limit: budget.limit,
                nextAvailable: budget.nextAvailableDate()
            )
        }
        budget.recordCall()

        let client = MCPStreamableHTTPClient(
            endpoint: LinkedInMCPServerService.endpoint,
            requestTimeout: 180
        )
        let result: MCPToolResult
        do {
            result = try await client.callTool(name: toolName, arguments: ["job_id": jobId])
        } catch let error where LinkedInMCPImportService.isAuthFailure(error) {
            throw LinkedInJobDetailsError.noSession
        }
        guard let text = result.firstText, !text.isEmpty else {
            throw LinkedInJobDetailsError.emptyResult
        }
        return try postingText(fromResultText: text)
    }
}
