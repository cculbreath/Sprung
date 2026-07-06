//
//  JobSearchView.swift
//  Sprung
//
//  Search either MCP job board (Dice or ZipRecruiter) — or point the agentic
//  Custom Site search at any small "web-fetch friendly" board or careers
//  page — and import results into the pipeline as `.new` leads. The thin
//  async glue and UI state live here while the request/decode/mapping halves
//  live in JobMCPImportService and SiteJobSearchService (mirroring
//  NewAppSheetView + JobURLImportService).
//

import SwiftUI

/// Which job source the sheet is currently searching. Each mode keeps its
/// own search fields, results, pagination cursor, and client/agent state —
/// they're independent search sessions, not tabs over one shared query.
private enum JobBoard: String, CaseIterable, Identifiable, Hashable {
    case dice = "Dice"
    case zipRecruiter = "ZipRecruiter"
    case customSite = "Custom Site"

    var id: String { rawValue }
}

struct JobSearchView: View {
    let jobAppStore: JobAppStore

    /// Supplies the LLMFacade the Custom Site agent loop runs on. Present in
    /// both the main and Discovery windows' environments.
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var selectedBoard: JobBoard = .dice
    @State private var isSearching = false
    /// Which mode the in-flight search belongs to — searches are single-flight
    /// across modes, and an agent run can outlast a board switch, so the
    /// progress display keys off this rather than `selectedBoard`.
    @State private var searchingBoard: JobBoard?
    @State private var errorMessage: String?
    @State private var importSummary: String?

    // MARK: Dice session state

    @State private var diceKeyword = ""
    @State private var diceLocation = ""
    @State private var diceWorkplaceType = ""
    @State private var diceResults: [DiceJobResult] = []
    @State private var diceMeta: DiceSearchMeta?
    @State private var diceCurrentPage = 1
    @State private var diceHasSearched = false
    /// One client per sheet so the initialize handshake happens once per session.
    @State private var diceClient: MCPStreamableHTTPClient?

    // MARK: ZipRecruiter session state

    @State private var zipJobRole = ""
    @State private var zipLocation = ""
    @State private var zipLocationType = ""
    @State private var zipResults: [JobMCPImportService.ZipRecruiterJobResult] = []
    @State private var zipMeta: JobMCPImportService.ZipRecruiterSearchMeta?
    @State private var zipOffset = 0
    @State private var zipHasSearched = false
    @State private var zipClient: MCPStreamableHTTPClient?

    // MARK: Custom Site session state

    @State private var siteURLText = ""
    @State private var siteGuidance = ""
    @State private var siteResults: [SiteJobListing] = []
    /// The agent's honest reason for an empty submission (bot-walled site, no
    /// matching postings) — surfaced instead of a quiet "no results".
    @State private var siteEmptyReason: String?
    @State private var siteHasSearched = false
    /// Host searched by the current results, snapshotted at search time so
    /// imports stay labeled correctly if the URL field is edited afterward.
    @State private var siteSearchedHost = ""
    /// Streaming per-turn progress lines from the agent loop ("Searching: …",
    /// "Fetching: …") — the same affordance the events discovery flow surfaces.
    @State private var siteProgressLines: [String] = []
    /// Retained so Cancel (and view teardown) can stop the loop cooperatively
    /// between turns via the runner's Task.checkCancellation seam.
    @State private var siteSearchTask: Task<Void, Never>?

    /// Stable Dice URLs already in the pipeline — recomputed on every store
    /// mutation (the store's changeVersion invalidates this view), so rows
    /// flip to "Imported" the moment a lead lands.
    private var importedURLs: Set<String> {
        JobMCPImportService.importedPostingURLs(in: jobAppStore)
    }

    /// title+company pairs already in the pipeline, for ZipRecruiter — its
    /// `job_redirect_url` is an unstable match token, so its dedup badge
    /// can't key off URL the way Dice's does.
    private var importedTitleCompanyPairs: Set<JobMCPImportService.TitleCompanyPair> {
        JobMCPImportService.importedTitleCompanyPairs(in: jobAppStore)
    }

    private var canSearch: Bool {
        guard !isSearching else { return false }
        switch selectedBoard {
        case .dice:
            return !diceKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .zipRecruiter:
            let role = zipJobRole.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = zipLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            return !role.isEmpty || !location.isEmpty
        case .customSite:
            return SiteJobSearchService.normalizedSiteURL(siteURLText) != nil
        }
    }

    private var currentResultsEmpty: Bool {
        switch selectedBoard {
        case .dice: return diceResults.isEmpty
        case .zipRecruiter: return zipResults.isEmpty
        case .customSite: return siteResults.isEmpty
        }
    }

    private var currentHasSearched: Bool {
        switch selectedBoard {
        case .dice: return diceHasSearched
        case .zipRecruiter: return zipHasSearched
        case .customSite: return siteHasSearched
        }
    }

    private var unimportedOnPage: Int {
        switch selectedBoard {
        case .dice:
            return diceResults.filter { !JobMCPImportService.isImported($0, importedURLs: importedURLs) }.count
        case .zipRecruiter:
            return zipResults.filter { !JobMCPImportService.isImported($0, importedPairs: importedTitleCompanyPairs) }.count
        case .customSite:
            return siteResults.filter { !SiteJobSearchService.isImported($0, importedURLs: importedURLs) }.count
        }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedBoard) { _, _ in
            errorMessage = nil
            importSummary = nil
        }
        .onDisappear {
            // Cooperative cancellation: never leave the agent loop burning
            // tokens for results nobody will see.
            siteSearchTask?.cancel()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Search Job Boards")
                .font(.headline)

            Picker("Job Board", selection: $selectedBoard) {
                ForEach(JobBoard.allCases) { board in
                    Text(board.rawValue).tag(board)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
        }
        .padding()
    }

    // MARK: - Search controls

    @ViewBuilder
    private var searchControls: some View {
        switch selectedBoard {
        case .dice:
            HStack(spacing: 8) {
                TextField("Keywords (e.g. iOS developer)", text: $diceKeyword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { searchDice(page: 1) }

                TextField("Location (optional)", text: $diceLocation)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { searchDice(page: 1) }

                Picker("Workplace", selection: $diceWorkplaceType) {
                    Text("Any").tag("")
                    ForEach(JobMCPImportService.diceWorkplaceTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .fixedSize()

                Button("Search") {
                    searchDice(page: 1)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSearch)
            }
            .padding()
        case .zipRecruiter:
            HStack(spacing: 8) {
                TextField("Job role (e.g. software engineer)", text: $zipJobRole)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { searchZipRecruiter(offset: 0) }

                TextField("Location (optional)", text: $zipLocation)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { searchZipRecruiter(offset: 0) }

                Picker("Workplace", selection: $zipLocationType) {
                    Text("Any").tag("")
                    ForEach(JobMCPImportService.zipRecruiterLocationTypes, id: \.self) { type in
                        Text(type.capitalized).tag(type)
                    }
                }
                .fixedSize()

                Button("Search") {
                    searchZipRecruiter(offset: 0)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSearch)
            }
            .padding()
        case .customSite:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Site URL (e.g. austinjobs.com or a company careers page)", text: $siteURLText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { searchCustomSite() }

                    Button("Search") {
                        searchCustomSite()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSearch)
                    .help("An AI agent browses the site with web search + page fetches and submits only page-verified postings")
                }

                TextField("Keywords or guidance (optional, e.g. \"embedded firmware roles, on-site\")", text: $siteGuidance)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { searchCustomSite() }
            }
            .padding()
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        if isSearching {
            if searchingBoard == .customSite {
                siteSearchProgress
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Searching \((searchingBoard ?? selectedBoard).rawValue)…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        } else if let errorMessage {
            VStack(spacing: 12) {
                Spacer()
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                Button("Try Again") {
                    retrySearch()
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if currentResultsEmpty {
            if selectedBoard == .customSite, currentHasSearched, let siteEmptyReason {
                // The agent submitted nothing and said why — an honest failure
                // the user must see, never a quiet "no results" success.
                VStack(spacing: 12) {
                    Spacer()
                    Label(siteEmptyReason, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                    Button("Try Again") {
                        retrySearch()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(emptyStateMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            switch selectedBoard {
            case .dice:
                List(diceResults) { result in
                    JobSearchResultRow(
                        result: result,
                        isImported: JobMCPImportService.isImported(result, importedURLs: importedURLs)
                    ) {
                        importResult(result)
                    }
                }
                .listStyle(.inset)
            case .zipRecruiter:
                List(zipResults) { result in
                    ZipRecruiterResultRow(
                        result: result,
                        isImported: JobMCPImportService.isImported(result, importedPairs: importedTitleCompanyPairs)
                    ) {
                        importResult(result)
                    }
                }
                .listStyle(.inset)
            case .customSite:
                List(siteResults) { listing in
                    SiteListingResultRow(
                        listing: listing,
                        isImported: SiteJobSearchService.isImported(listing, importedURLs: importedURLs)
                    ) {
                        importResult(listing)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var emptyStateMessage: String {
        if currentHasSearched {
            return selectedBoard == .customSite
                ? "The agent found no matching postings on the site."
                : "No jobs matched your search."
        }
        return selectedBoard == .customSite
            ? "Point the agent at a small job board or company careers page. It browses the site, verifies each posting's page, and imports matches as pipeline leads."
            : "Search \(selectedBoard.rawValue) and import results as pipeline leads."
    }

    /// Live agent activity while a Custom Site search runs: spinner, the
    /// streaming per-turn progress lines, and a Cancel affordance.
    private var siteSearchProgress: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Agent searching \(siteSearchedHost)…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    siteSearchTask?.cancel()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(siteProgressLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .onChange(of: siteProgressLines.count) { _, count in
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            switch selectedBoard {
            case .dice:
                Button {
                    searchDice(page: diceCurrentPage - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(isSearching || diceCurrentPage <= 1)

                Text(dicePageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    searchDice(page: diceCurrentPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(isSearching || diceCurrentPage >= (diceMeta?.pageCount ?? 1))
            case .zipRecruiter:
                Button {
                    searchZipRecruiter(offset: max(0, zipOffset - zipPageSize))
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(isSearching || zipOffset <= 0)

                Text(zipPageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    searchZipRecruiter(offset: zipOffset + zipPageSize)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(isSearching || !zipHasMoreResults)
            case .customSite:
                // No pagination — the agent submits one verified list per run.
                if !siteResults.isEmpty {
                    Text("\(siteResults.count) page-verified posting\(siteResults.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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

    private var dicePageLabel: String {
        guard let diceMeta, let totalResults = diceMeta.totalResults else {
            return diceResults.isEmpty ? "" : "Page \(diceCurrentPage)"
        }
        let pageCount = diceMeta.pageCount ?? 1
        return "Page \(diceCurrentPage) of \(pageCount) • \(totalResults) results"
    }

    /// Results per ZipRecruiter page — the server-reported `limit`, defaulting
    /// to the count actually returned by the last search (5, per ZipRecruiter's
    /// documented page size) before any search has run.
    private var zipPageSize: Int {
        zipMeta?.limit ?? 5
    }

    private var zipHasMoreResults: Bool {
        guard let zipMeta else { return false }
        return zipOffset + zipMeta.count < zipMeta.total
    }

    private var zipPageLabel: String {
        guard let zipMeta, zipMeta.count > 0 else {
            return zipResults.isEmpty ? "" : "Results \(zipOffset + 1)–\(zipOffset + zipResults.count)"
        }
        let start = zipOffset + 1
        let end = zipOffset + zipMeta.count
        return "\(start)–\(end) of \(zipMeta.total) results"
    }

    // MARK: - Actions

    private func retrySearch() {
        switch selectedBoard {
        case .dice:
            searchDice(page: diceCurrentPage)
        case .zipRecruiter:
            searchZipRecruiter(offset: zipOffset)
        case .customSite:
            searchCustomSite()
        }
    }

    private func searchDice(page: Int) {
        let trimmedKeyword = diceKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty, !isSearching else { return }
        isSearching = true
        searchingBoard = .dice
        errorMessage = nil
        importSummary = nil
        Task {
            do {
                let activeClient: MCPStreamableHTTPClient
                if let diceClient {
                    activeClient = diceClient
                } else {
                    activeClient = try JobMCPImportService.makeDiceClient()
                    diceClient = activeClient
                }
                var query = DiceSearchQuery(keyword: trimmedKeyword)
                query.location = diceLocation
                query.workplaceType = diceWorkplaceType
                query.pageNumber = max(1, page)
                let payload = try await JobMCPImportService.searchDice(query, client: activeClient)
                diceResults = payload.jobs
                diceMeta = payload.meta
                diceCurrentPage = payload.meta?.currentPage ?? max(1, page)
                diceHasSearched = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
            searchingBoard = nil
        }
    }

    private func searchZipRecruiter(offset: Int) {
        let trimmedRole = zipJobRole.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = zipLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRole.isEmpty || !trimmedLocation.isEmpty, !isSearching else { return }
        isSearching = true
        searchingBoard = .zipRecruiter
        errorMessage = nil
        importSummary = nil
        Task {
            do {
                let activeClient: MCPStreamableHTTPClient
                if let zipClient {
                    activeClient = zipClient
                } else {
                    activeClient = try JobMCPImportService.makeZipRecruiterClient()
                    zipClient = activeClient
                }
                var query = JobMCPImportService.ZipRecruiterSearchQuery(jobRole: trimmedRole, location: trimmedLocation)
                query.locationType = zipLocationType
                query.offset = max(0, offset)
                let payload = try await JobMCPImportService.searchZipRecruiter(query, client: activeClient)
                zipResults = payload.jobs
                zipMeta = payload.meta
                zipOffset = payload.meta?.offset ?? max(0, offset)
                zipHasSearched = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
            searchingBoard = nil
        }
    }

    /// Kick off the agent loop against the typed site. The search runs until
    /// the agent submits (maxTurns-bounded, no wall-clock deadline) or the
    /// user cancels; per-turn progress streams into `siteProgressLines`.
    private func searchCustomSite() {
        guard let siteURL = SiteJobSearchService.normalizedSiteURL(siteURLText), !isSearching else { return }
        isSearching = true
        searchingBoard = .customSite
        errorMessage = nil
        importSummary = nil
        siteEmptyReason = nil
        siteProgressLines = []
        siteResults = []
        siteSearchedHost = siteURL.host ?? siteURL.absoluteString
        let guidance = siteGuidance
        siteSearchTask = Task {
            do {
                let submission = try await SiteJobSearchService.run(
                    siteURL: siteURL,
                    guidance: guidance,
                    llmFacade: appEnvironment.llmFacade,
                    onProgress: { line in
                        siteProgressLines.append(line)
                    }
                )
                siteResults = submission.listings
                if submission.listings.isEmpty {
                    // Honest empty result — surface the agent's reason (or a
                    // clear default) rather than presenting a quiet success.
                    siteEmptyReason = submission.emptyReason
                        ?? "The agent submitted no postings — the site may be bot-walled or have no matching listings."
                }
                siteHasSearched = true
            } catch is CancellationError {
                errorMessage = "Search cancelled."
            } catch {
                // A cancelled in-flight request can surface as a URL error
                // rather than CancellationError — report it as the user's
                // cancellation, not a failure.
                errorMessage = Task.isCancelled ? "Search cancelled." : error.localizedDescription
            }
            isSearching = false
            searchingBoard = nil
            siteSearchTask = nil
        }
    }

    private func importResult(_ result: DiceJobResult) {
        importSummary = nil
        if case .skipped(let reason) = JobMCPImportService.importAsLead(result, into: jobAppStore) {
            errorMessage = "Couldn't import \"\(result.title ?? "job")\": \(reason)"
        }
    }

    private func importResult(_ result: JobMCPImportService.ZipRecruiterJobResult) {
        importSummary = nil
        if case .skipped(let reason) = JobMCPImportService.importAsLead(result, into: jobAppStore) {
            errorMessage = "Couldn't import \"\(result.title ?? "job")\": \(reason)"
        }
    }

    private func importResult(_ listing: SiteJobListing) {
        importSummary = nil
        if case .skipped(let reason) = SiteJobSearchService.importAsLead(listing, siteHost: siteSearchedHost, into: jobAppStore) {
            errorMessage = "Couldn't import \"\(listing.title)\": \(reason)"
        }
    }

    private func importAllOnPage() {
        var imported = 0
        var duplicates = 0
        var skipped = 0
        switch selectedBoard {
        case .dice:
            for result in diceResults {
                switch JobMCPImportService.importAsLead(result, into: jobAppStore) {
                case .imported: imported += 1
                case .duplicate: duplicates += 1
                case .skipped: skipped += 1
                }
            }
        case .zipRecruiter:
            for result in zipResults {
                switch JobMCPImportService.importAsLead(result, into: jobAppStore) {
                case .imported: imported += 1
                case .duplicate: duplicates += 1
                case .skipped: skipped += 1
                }
            }
        case .customSite:
            for listing in siteResults {
                switch SiteJobSearchService.importAsLead(listing, siteHost: siteSearchedHost, into: jobAppStore) {
                case .imported: imported += 1
                case .duplicate: duplicates += 1
                case .skipped: skipped += 1
                }
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

// MARK: - Dice result row

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

// MARK: - Custom Site listing row

private struct SiteListingResultRow: View {
    let listing: SiteJobListing
    let isImported: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(listing.title)
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(listing.company)
                    if let location = listing.location, !location.isEmpty {
                        Text("•")
                        Text(location)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !listing.summary.isEmpty {
                    Text(listing.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    if let salary = listing.salary, !salary.isEmpty {
                        detailTag(salary)
                    }
                    if let postedDate = listing.postedDate, !postedDate.isEmpty {
                        Text(postedDate)
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
            if let url = URL(string: listing.url) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open Posting", systemImage: "safari")
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

// MARK: - ZipRecruiter result row

private struct ZipRecruiterResultRow: View {
    let result: JobMCPImportService.ZipRecruiterJobResult
    let isImported: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title ?? "Untitled")
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(result.company ?? "Unknown company")
                    if let location = result.location, !location.isEmpty {
                        Text("•")
                        Text(location)
                    }
                    if result.isRemote == true {
                        Text("•")
                        Text("Remote")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let benefits = result.benefits, !benefits.isEmpty {
                    Text(benefits)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let jobType = result.jobType, !jobType.isEmpty {
                        detailTag(jobType)
                    }
                    if let salaryDisplay = JobMCPImportService.displaySalaryRange(result.salary) {
                        detailTag(salaryDisplay)
                    }
                    if let daysAgo = result.daysAgo {
                        Text(JobMCPImportService.displayDaysAgo(daysAgo))
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
            if let rawURL = result.jobRedirectUrl, let url = URL(string: rawURL) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open on ZipRecruiter", systemImage: "safari")
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
