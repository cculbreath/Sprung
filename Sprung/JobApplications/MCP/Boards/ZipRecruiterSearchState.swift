//
//  ZipRecruiterSearchState.swift
//  Sprung
//
//  Session state + search/import logic for the ZipRecruiter job board. Owned by
//  JobSearchView (survives board switches); ZipRecruiterSearchPanel renders it.
//  The request/decode/mapping halves live in JobMCPImportService.
//

import Foundation
import Observation

@Observable
@MainActor
final class ZipRecruiterSearchState {
    private let jobAppStore: JobAppStore

    var jobRole = ""
    var location = ""
    var locationType = ""
    var results: [JobMCPImportService.ZipRecruiterJobResult] = []
    var meta: JobMCPImportService.ZipRecruiterSearchMeta?
    var offset = 0
    var hasSearched = false
    var isSearching = false
    var errorMessage: String?
    var importSummary: String?

    private var client: MCPStreamableHTTPClient?

    init(jobAppStore: JobAppStore) {
        self.jobAppStore = jobAppStore
    }

    // MARK: Derived

    var canSearch: Bool {
        let role = jobRole.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return !role.isEmpty || !loc.isEmpty
    }

    /// title+company pairs already in the pipeline — ZipRecruiter's
    /// `job_redirect_url` is an unstable match token, so its dedup badge
    /// can't key off URL the way Dice's does.
    private var importedTitleCompanyPairs: Set<JobMCPImportService.TitleCompanyPair> {
        JobMCPImportService.importedTitleCompanyPairs(in: jobAppStore)
    }

    func isImported(_ result: JobMCPImportService.ZipRecruiterJobResult) -> Bool {
        JobMCPImportService.isImported(result, importedPairs: importedTitleCompanyPairs)
    }

    var unimportedOnPage: Int {
        results.filter { !JobMCPImportService.isImported($0, importedPairs: importedTitleCompanyPairs) }.count
    }

    /// Results per page — the server-reported `limit`, defaulting to
    /// ZipRecruiter's documented page size (5) before any search has run.
    var pageSize: Int { meta?.limit ?? 5 }

    var hasMoreResults: Bool {
        guard let meta else { return false }
        return offset + meta.count < meta.total
    }

    var pageLabel: String {
        guard let meta, meta.count > 0 else {
            return results.isEmpty ? "" : "Results \(offset + 1)–\(offset + results.count)"
        }
        let start = offset + 1
        let end = offset + meta.count
        return "\(start)–\(end) of \(meta.total) results"
    }

    var canGoBack: Bool { offset > 0 }

    // MARK: Actions

    func search(offset requestedOffset: Int) {
        let trimmedRole = jobRole.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRole.isEmpty || !trimmedLocation.isEmpty, !isSearching else { return }
        isSearching = true
        errorMessage = nil
        importSummary = nil
        Task {
            do {
                let activeClient: MCPStreamableHTTPClient
                if let client {
                    activeClient = client
                } else {
                    activeClient = try JobMCPImportService.makeZipRecruiterClient()
                    client = activeClient
                }
                var query = JobMCPImportService.ZipRecruiterSearchQuery(jobRole: trimmedRole, location: trimmedLocation)
                query.locationType = locationType
                query.offset = max(0, requestedOffset)
                let payload = try await JobMCPImportService.searchZipRecruiter(query, client: activeClient)
                results = payload.jobs
                meta = payload.meta
                offset = payload.meta?.offset ?? max(0, requestedOffset)
                hasSearched = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    func importResult(_ result: JobMCPImportService.ZipRecruiterJobResult) {
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
