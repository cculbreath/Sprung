//
//  LinkedInSearchState.swift
//  Sprung
//
//  Session state + search/import logic for the LinkedIn board (via the local
//  MCP server). Owned by JobSearchView; LinkedInSearchPanel renders it and owns
//  the one-time risk-consent gate. The request/decode/mapping halves live in
//  LinkedInMCPImportService.
//

import Foundation
import Observation

@Observable
@MainActor
final class LinkedInSearchState {
    private let jobAppStore: JobAppStore

    var keywords = ""
    var location = ""
    var datePosted: LinkedInDatePosted?
    var workTypes: Set<LinkedInWorkType> = []
    var results: [LinkedInJobLead] = []
    var hasSearched = false
    var isSearching = false
    var errorMessage: String?
    var importSummary: String?

    /// Progress phase while a search runs ("Starting LinkedIn server…" →
    /// "Searching LinkedIn…").
    var phase: String?

    /// One client per session so the initialize handshake happens once. The
    /// generous timeout covers the server's cold start (first run downloads a
    /// browser) and multi-second page scrapes.
    private var client: MCPStreamableHTTPClient?

    init(jobAppStore: JobAppStore) {
        self.jobAppStore = jobAppStore
    }

    // MARK: Derived

    /// Rolling hourly call budget (risk rail). Rebuilt on each read — the state
    /// lives in UserDefaults, not here.
    var budget: LinkedInCallBudget { LinkedInCallBudget() }

    var canSearch: Bool {
        !keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !budget.isExhausted
    }

    /// The budget-exhausted explanation shown beside the disabled Search button
    /// (risk rail: the cap surfaces, it never silently queues).
    var budgetMessage: String {
        let budget = self.budget
        if let nextAvailable = budget.nextAvailableDate() {
            return "Hourly LinkedIn call limit reached (\(budget.limit)/hr). Try again after \(nextAvailable.formatted(date: .omitted, time: .shortened))."
        }
        return "Hourly LinkedIn call limit reached (\(budget.limit)/hr). Try again later."
    }

    private var importedURLs: Set<String> {
        JobMCPImportService.importedPostingURLs(in: jobAppStore)
    }

    func isImported(_ lead: LinkedInJobLead) -> Bool {
        LinkedInMCPImportService.isImported(lead, importedURLs: importedURLs)
    }

    var unimportedOnPage: Int {
        results.filter { !LinkedInMCPImportService.isImported($0, importedURLs: importedURLs) }.count
    }

    // MARK: Actions

    /// Run one LinkedIn search: ensure the local MCP server is running → one
    /// `search_jobs` call (the only tool this board ever calls) through the
    /// rolling hourly budget → decode into leads. Consent is gated by the panel
    /// before this runs. An auth-failure tool result maps to the single "sign in
    /// to linkedin.com in your browser" state with the standard Retry
    /// affordance; every other failure surfaces its own message. All loud,
    /// nothing degrades silently.
    func search(server: LinkedInMCPServerService) {
        let trimmedKeywords = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeywords.isEmpty, !isSearching else { return }
        let budget = self.budget
        guard !budget.isExhausted else {
            // The Search button disables when exhausted; this guard keeps
            // onSubmit paths honest too — with the explanation, never quietly.
            errorMessage = budgetMessage
            return
        }
        isSearching = true
        errorMessage = nil
        importSummary = nil
        phase = "Starting LinkedIn server…"
        let location = self.location
        let datePosted = self.datePosted
        let workTypes = LinkedInWorkType.allCases.filter { self.workTypes.contains($0) }
        Task {
            do {
                try await server.ensureRunning()
                phase = "Searching LinkedIn…"
                let activeClient: MCPStreamableHTTPClient
                if let client {
                    activeClient = client
                } else {
                    activeClient = MCPStreamableHTTPClient(
                        endpoint: LinkedInMCPServerService.endpoint,
                        requestTimeout: 180
                    )
                    client = activeClient
                }
                results = try await LinkedInMCPImportService.searchJobs(
                    keywords: trimmedKeywords,
                    location: location,
                    datePosted: datePosted,
                    workTypes: workTypes,
                    client: activeClient,
                    budget: budget
                )
                hasSearched = true
            } catch {
                if LinkedInMCPImportService.isAuthFailure(error) {
                    Logger.error("❌ [LinkedInSearch] Auth failure from \(LinkedInMCPImportService.searchToolName): \(error.localizedDescription)", category: .networking)
                    errorMessage = LinkedInMCPImportService.noSessionMessage
                } else {
                    Logger.error("❌ [LinkedInSearch] \(LinkedInMCPImportService.searchToolName) failed: \(error.localizedDescription)", category: .networking)
                    errorMessage = error.localizedDescription
                }
            }
            isSearching = false
            phase = nil
        }
    }

    func importResult(_ lead: LinkedInJobLead) {
        importSummary = nil
        if case .skipped(let reason) = LinkedInMCPImportService.importAsLead(lead, into: jobAppStore) {
            errorMessage = "Couldn't import \"\(lead.title)\": \(reason)"
        }
    }

    func importAllOnPage() {
        var imported = 0
        var duplicates = 0
        var skipped = 0
        for lead in results {
            switch LinkedInMCPImportService.importAsLead(lead, into: jobAppStore) {
            case .imported: imported += 1
            case .duplicate: duplicates += 1
            case .skipped: skipped += 1
            }
        }
        importSummary = JobSearchImportSummary.text(imported: imported, duplicates: duplicates, skipped: skipped)
    }
}
