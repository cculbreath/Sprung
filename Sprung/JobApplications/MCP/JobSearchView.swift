//
//  JobSearchView.swift
//  Sprung
//
//  Search Dice's public MCP job board and import results into the pipeline as
//  `.new` leads. Presented as a sheet from SourcesView; the thin async glue and
//  UI state live here while the request/decode/mapping halves live in
//  JobMCPImportService (mirroring NewAppSheetView + JobURLImportService).
//

import SwiftUI

struct JobSearchView: View {
    let jobAppStore: JobAppStore
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var location = ""
    @State private var workplaceType = ""
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var importSummary: String?
    @State private var results: [DiceJobResult] = []
    @State private var meta: DiceSearchMeta?
    @State private var currentPage = 1
    @State private var hasSearched = false
    /// One client per sheet so the initialize handshake happens once per session.
    @State private var client: MCPStreamableHTTPClient?

    /// Stable URLs already in the pipeline — recomputed on every store mutation
    /// (the store's changeVersion invalidates this view), so rows flip to
    /// "Imported" the moment a lead lands.
    private var importedURLs: Set<String> {
        JobMCPImportService.importedPostingURLs(in: jobAppStore)
    }

    private var canSearch: Bool {
        !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching
    }

    private var unimportedOnPage: Int {
        results.filter { !JobMCPImportService.isImported($0, importedURLs: importedURLs) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchControls
            Divider()
            resultsArea
            Divider()
            footer
        }
        .frame(width: 700, height: 640)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Text("Search Dice Jobs")
                .font(.headline)

            Spacer()

            // Balance the Close button so the title stays centered
            Button("Close") { }
                .hidden()
        }
        .padding()
    }

    // MARK: - Search controls

    private var searchControls: some View {
        HStack(spacing: 8) {
            TextField("Keywords (e.g. iOS developer)", text: $keyword)
                .textFieldStyle(.roundedBorder)
                .onSubmit { search(page: 1) }

            TextField("Location (optional)", text: $location)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit { search(page: 1) }

            Picker("Workplace", selection: $workplaceType) {
                Text("Any").tag("")
                ForEach(JobMCPImportService.diceWorkplaceTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .fixedSize()

            Button("Search") {
                search(page: 1)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSearch)
        }
        .padding()
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        if isSearching {
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Searching Dice…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let errorMessage {
            VStack(spacing: 12) {
                Spacer()
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                Button("Try Again") {
                    search(page: currentPage)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if results.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(hasSearched ? "No jobs matched your search." : "Search Dice and import results as pipeline leads.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(results) { result in
                JobSearchResultRow(
                    result: result,
                    isImported: JobMCPImportService.isImported(result, importedURLs: importedURLs)
                ) {
                    importResult(result)
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                search(page: currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(isSearching || currentPage <= 1)

            Text(pageLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                search(page: currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isSearching || currentPage >= (meta?.pageCount ?? 1))

            Spacer()

            if let importSummary {
                Text(importSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Import All as Leads") {
                importAllOnPage()
            }
            .buttonStyle(.bordered)
            .disabled(isSearching || unimportedOnPage == 0)
        }
        .padding()
    }

    private var pageLabel: String {
        guard let meta, let totalResults = meta.totalResults else {
            return results.isEmpty ? "" : "Page \(currentPage)"
        }
        let pageCount = meta.pageCount ?? 1
        return "Page \(currentPage) of \(pageCount) • \(totalResults) results"
    }

    // MARK: - Actions

    private func search(page: Int) {
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

    private func importResult(_ result: DiceJobResult) {
        importSummary = nil
        if case .skipped(let reason) = JobMCPImportService.importAsLead(result, into: jobAppStore) {
            errorMessage = "Couldn't import \"\(result.title ?? "job")\": \(reason)"
        }
    }

    private func importAllOnPage() {
        var imported = 0
        var duplicates = 0
        var skipped = 0
        for result in results {
            switch JobMCPImportService.importAsLead(result, into: jobAppStore) {
            case .imported:
                imported += 1
            case .duplicate:
                duplicates += 1
            case .skipped:
                skipped += 1
            }
        }
        var parts = ["Imported \(imported)"]
        if duplicates > 0 {
            parts.append("\(duplicates) already in pipeline")
        }
        if skipped > 0 {
            parts.append("\(skipped) skipped")
        }
        importSummary = parts.joined(separator: " • ")
    }
}

// MARK: - Result row

private struct JobSearchResultRow: View {
    let result: DiceJobResult
    let isImported: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title ?? "Untitled")
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(result.companyName ?? "Unknown company")
                    if let locationName = result.jobLocation?.displayName, !locationName.isEmpty {
                        Text("•")
                        Text(locationName)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let summary = result.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    if let employmentType = result.employmentType, !employmentType.isEmpty {
                        detailTag(employmentType)
                    }
                    if let workplaceTypes = result.workplaceTypes, !workplaceTypes.isEmpty {
                        detailTag(workplaceTypes.joined(separator: ", "))
                    }
                    if let salary = result.salary, !salary.isEmpty {
                        detailTag(salary)
                    }
                    if result.easyApply == true {
                        detailTag("Easy Apply")
                    }
                    if let postedDate = result.postedDate, !postedDate.isEmpty {
                        Text(JobMCPImportService.displayPostedDate(postedDate))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if isImported {
                Label("Imported", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Import") {
                    onImport()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let rawURL = result.detailsPageUrl, let url = URL(string: rawURL) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open on Dice", systemImage: "safari")
                }
            }
        }
    }

    private func detailTag(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)
            .lineLimit(1)
    }
}
