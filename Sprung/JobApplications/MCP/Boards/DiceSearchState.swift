//
//  DiceSearchState.swift
//  Sprung
//
//  Session state + search/import logic for the Dice job board. Owned by
//  JobSearchView (survives board switches); DiceSearchPanel renders it. The
//  request/decode/mapping halves live in JobMCPImportService.
//

import Foundation
import Observation

@Observable
@MainActor
final class DiceSearchState {
    private let jobAppStore: JobAppStore

    var keyword = ""
    var location = ""
    var workplaceType = ""
    var results: [DiceJobResult] = []
    var meta: DiceSearchMeta?
    var currentPage = 1
    var hasSearched = false
    var isSearching = false
    var errorMessage: String?
    var importSummary: String?

    /// One client per session so the initialize handshake happens once.
    private var client: MCPStreamableHTTPClient?

    init(jobAppStore: JobAppStore) {
        self.jobAppStore = jobAppStore
    }

    // MARK: Derived

    var canSearch: Bool {
        !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Stable Dice URLs already in the pipeline — recomputed on every store
    /// mutation so rows flip to "Imported" the moment a lead lands.
    private var importedURLs: Set<String> {
        JobMCPImportService.importedPostingURLs(in: jobAppStore)
    }

    func isImported(_ result: DiceJobResult) -> Bool {
        JobMCPImportService.isImported(result, importedURLs: importedURLs)
    }

    var unimportedOnPage: Int {
        results.filter { !JobMCPImportService.isImported($0, importedURLs: importedURLs) }.count
    }

    var pageLabel: String {
        guard let meta, let totalResults = meta.totalResults else {
            return results.isEmpty ? "" : "Page \(currentPage)"
        }
        let pageCount = meta.pageCount ?? 1
        return "Page \(currentPage) of \(pageCount) • \(totalResults) results"
    }

    var canGoBack: Bool { currentPage > 1 }
    var canGoForward: Bool { currentPage < (meta?.pageCount ?? 1) }

    // MARK: Actions

    func search(page: Int) {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty, !isSearching else { return }
        isSearching = true
        errorMessage = nil
        importSummary = nil
        Task {
            do {
                let activeClient: MCPStreamableHTTPClient
                if let client {
                    activeClient = client
                } else {
                    activeClient = try JobMCPImportService.makeDiceClient()
                    client = activeClient
                }
                var query = DiceSearchQuery(keyword: trimmedKeyword)
                query.location = location
                query.workplaceType = workplaceType
                query.pageNumber = max(1, page)
                let payload = try await JobMCPImportService.searchDice(query, client: activeClient)
                results = payload.jobs
                meta = payload.meta
                currentPage = payload.meta?.currentPage ?? max(1, page)
                hasSearched = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    func importResult(_ result: DiceJobResult) {
        importSummary = nil
        if case .skipped(let reason) = JobMCPImportService.importAsLead(result, into: jobAppStore) {
            errorMessage = "Couldn't import \"\(result.title ?? "job")\": \(reason)"
        }
    }

    func importAllOnPage() {
        var imported = 0
        var duplicates = 0
        var skipped = 0
        for result in results {
            switch JobMCPImportService.importAsLead(result, into: jobAppStore) {
            case .imported: imported += 1
            case .duplicate: duplicates += 1
            case .skipped: skipped += 1
            }
        }
        importSummary = JobSearchImportSummary.text(imported: imported, duplicates: duplicates, skipped: skipped)
    }
}
