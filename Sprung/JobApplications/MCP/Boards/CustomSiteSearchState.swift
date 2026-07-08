//
//  CustomSiteSearchState.swift
//  Sprung
//
//  Session state + agent-loop orchestration for the Custom Site board. Owned by
//  JobSearchView so the agent run outlives a board switch; CustomSiteSearchPanel
//  renders it. The agent loop itself lives in SiteJobSearchService.
//

import Foundation
import Observation

@Observable
@MainActor
final class CustomSiteSearchState {
    private let jobAppStore: JobAppStore

    var urlText = ""
    var guidance = ""
    var results: [SiteJobListing] = []
    /// The agent's honest reason for an empty submission (bot-walled site, no
    /// matching postings) — surfaced instead of a quiet "no results".
    var emptyReason: String?
    var hasSearched = false
    var isSearching = false
    var errorMessage: String?
    var importSummary: String?
    /// Host searched by the current results, snapshotted at search time so
    /// imports stay labeled correctly if the URL field is edited afterward.
    var searchedHost = ""
    /// Streaming per-turn progress lines from the agent loop ("Searching: …",
    /// "Fetching: …").
    var progressLines: [String] = []

    /// Retained so Cancel (and view teardown) can stop the loop cooperatively
    /// between turns via the runner's Task.checkCancellation seam.
    private var searchTask: Task<Void, Never>?

    init(jobAppStore: JobAppStore) {
        self.jobAppStore = jobAppStore
    }

    // MARK: Derived

    var canSearch: Bool {
        SiteJobSearchService.normalizedSiteURL(urlText) != nil
    }

    private var importedURLs: Set<String> {
        JobMCPImportService.importedPostingURLs(in: jobAppStore)
    }

    func isImported(_ listing: SiteJobListing) -> Bool {
        SiteJobSearchService.isImported(listing, importedURLs: importedURLs)
    }

    var unimportedOnPage: Int {
        results.filter { !SiteJobSearchService.isImported($0, importedURLs: importedURLs) }.count
    }

    // MARK: Actions

    /// Kick off the agent loop against the typed site. The search runs until the
    /// agent submits (maxTurns-bounded, no wall-clock deadline) or the user
    /// cancels; per-turn progress streams into `progressLines`.
    func search(llmFacade: LLMFacade) {
        guard let siteURL = SiteJobSearchService.normalizedSiteURL(urlText), !isSearching else { return }
        isSearching = true
        errorMessage = nil
        importSummary = nil
        emptyReason = nil
        progressLines = []
        results = []
        searchedHost = siteURL.host ?? siteURL.absoluteString
        let guidance = self.guidance
        searchTask = Task {
            do {
                let submission = try await SiteJobSearchService.run(
                    siteURL: siteURL,
                    guidance: guidance,
                    llmFacade: llmFacade,
                    onProgress: { line in
                        self.progressLines.append(line)
                    }
                )
                results = submission.listings
                if submission.listings.isEmpty {
                    // Honest empty result — surface the agent's reason (or a
                    // clear default) rather than presenting a quiet success.
                    emptyReason = submission.emptyReason
                        ?? "The agent submitted no postings — the site may be bot-walled or have no matching listings."
                }
                hasSearched = true
            } catch is CancellationError {
                errorMessage = "Search cancelled."
            } catch {
                // A cancelled in-flight request can surface as a URL error
                // rather than CancellationError — report it as the user's
                // cancellation, not a failure.
                errorMessage = Task.isCancelled ? "Search cancelled." : error.localizedDescription
            }
            isSearching = false
            searchTask = nil
        }
    }

    /// Cooperative cancellation for the Cancel button and view teardown — never
    /// leave the agent loop burning tokens for results nobody will see.
    func cancel() {
        searchTask?.cancel()
    }

    func importResult(_ listing: SiteJobListing) {
        importSummary = nil
        if case .skipped(let reason) = SiteJobSearchService.importAsLead(listing, siteHost: searchedHost, into: jobAppStore) {
            errorMessage = "Couldn't import \"\(listing.title)\": \(reason)"
        }
    }

    func importAllOnPage() {
        var imported = 0
        var duplicates = 0
        var skipped = 0
        for listing in results {
            switch SiteJobSearchService.importAsLead(listing, siteHost: searchedHost, into: jobAppStore) {
            case .imported: imported += 1
            case .duplicate: duplicates += 1
            case .skipped: skipped += 1
            }
        }
        importSummary = JobSearchImportSummary.text(imported: imported, duplicates: duplicates, skipped: skipped)
    }
}
