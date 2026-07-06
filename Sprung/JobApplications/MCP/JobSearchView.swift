//
//  JobSearchView.swift
//  Sprung
//
//  Search an MCP job board (Dice, ZipRecruiter, or LinkedIn via the local
//  MCP server) — or point the agentic Custom Site search at any small
//  "web-fetch friendly" board or careers page — and import results into the
//  pipeline as `.new` leads. The thin async glue and UI state live here
//  while the request/decode/mapping halves live in JobMCPImportService,
//  LinkedInMCPImportService, and SiteJobSearchService (mirroring
//  NewAppSheetView + JobURLImportService).
//

import SwiftUI

/// Which job source the sheet is currently searching. Each mode keeps its
/// own search fields, results, pagination cursor, and client/agent state —
/// they're independent search sessions, not tabs over one shared query.
private enum JobBoard: String, CaseIterable, Identifiable, Hashable {
    case dice = "Dice"
    case zipRecruiter = "ZipRecruiter"
    case linkedIn = "LinkedIn"
    case customSite = "Custom Site"

    var id: String { rawValue }
}

struct JobSearchView: View {
    let jobAppStore: JobAppStore

    /// Supplies the LLMFacade the Custom Site agent loop runs on. Present in
    /// both the main and Discovery windows' environments.
    @Environment(AppEnvironment.self) private var appEnvironment

    /// Owns the local LinkedIn MCP server's lifecycle (spawn + handshake +
    /// stop-on-quit). Injected from AppDependencies.
    @Environment(LinkedInMCPServerService.self) private var linkedInServer

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

    // MARK: LinkedIn session state

    /// One-time risk consent for the LinkedIn board (LinkedIn's User
    /// Agreement prohibits automated access) — the first Search presents
    /// LinkedInConsentDialog instead of searching; declining aborts. The
    /// flag itself lives on `linkedInServer.consentAccepted` (persisted
    /// under `LinkedInMCPServerService.consentDefaultsKey`).
    @State private var showingLinkedInConsent = false
    @State private var linkedInKeywords = ""
    @State private var linkedInLocation = ""
    @State private var linkedInDatePosted: LinkedInDatePosted?
    @State private var linkedInWorkTypes: Set<LinkedInWorkType> = []
    @State private var linkedInResults: [LinkedInJobLead] = []
    @State private var linkedInHasSearched = false
    /// One client per sheet so the initialize handshake happens once per
    /// session. The generous timeout covers the server's cold start (first
    /// run downloads a browser) and multi-second page scrapes.
    @State private var linkedInClient: MCPStreamableHTTPClient?
    /// Progress phase while a LinkedIn search runs ("Starting LinkedIn
    /// server…" → "Searching LinkedIn…").
    @State private var linkedInPhase: String?

    /// Rolling hourly call budget (risk rail). Rebuilt on each read — the
    /// state lives in UserDefaults, not the view.
    private var linkedInBudget: LinkedInCallBudget { LinkedInCallBudget() }

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
        case .linkedIn:
            return !linkedInKeywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !linkedInBudget.isExhausted
        case .customSite:
            return SiteJobSearchService.normalizedSiteURL(siteURLText) != nil
        }
    }

    private var currentResultsEmpty: Bool {
        switch selectedBoard {
        case .dice: return diceResults.isEmpty
        case .zipRecruiter: return zipResults.isEmpty
        case .linkedIn: return linkedInResults.isEmpty
        case .customSite: return siteResults.isEmpty
        }
    }

    private var currentHasSearched: Bool {
        switch selectedBoard {
        case .dice: return diceHasSearched
        case .zipRecruiter: return zipHasSearched
        case .linkedIn: return linkedInHasSearched
        case .customSite: return siteHasSearched
        }
    }

    private var unimportedOnPage: Int {
        switch selectedBoard {
        case .dice:
            return diceResults.filter { !JobMCPImportService.isImported($0, importedURLs: importedURLs) }.count
        case .zipRecruiter:
            return zipResults.filter { !JobMCPImportService.isImported($0, importedPairs: importedTitleCompanyPairs) }.count
        case .linkedIn:
            return linkedInResults.filter { !LinkedInMCPImportService.isImported($0, importedURLs: importedURLs) }.count
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
        .sheet(isPresented: $showingLinkedInConsent) {
            // One-time risk consent gates the FIRST LinkedIn call; accepting
            // persists the flag and immediately runs the pending search,
            // declining just dismisses.
            LinkedInConsentDialog(
                onAccept: {
                    linkedInServer.acceptConsent()
                    showingLinkedInConsent = false
                    searchLinkedIn()
                },
                onDecline: {
                    showingLinkedInConsent = false
                }
            )
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
        case .linkedIn:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Keywords (e.g. staff physicist)", text: $linkedInKeywords)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { searchLinkedIn() }

                    TextField("Location (optional)", text: $linkedInLocation)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit { searchLinkedIn() }

                    Picker("Posted", selection: $linkedInDatePosted) {
                        Text("Any time").tag(LinkedInDatePosted?.none)
                        ForEach(LinkedInDatePosted.allCases) { period in
                            Text(period.displayName).tag(Optional(period))
                        }
                    }
                    .fixedSize()

                    Button("Search") {
                        searchLinkedIn()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSearch)
                }

                HStack(spacing: 8) {
                    ForEach(LinkedInWorkType.allCases) { workType in
                        Toggle(workType.displayName, isOn: Binding(
                            get: { linkedInWorkTypes.contains(workType) },
                            set: { isOn in
                                if isOn {
                                    linkedInWorkTypes.insert(workType)
                                } else {
                                    linkedInWorkTypes.remove(workType)
                                }
                            }
                        ))
                        .toggleStyle(.button)
                    }

                    Spacer()

                    if linkedInBudget.isExhausted {
                        // Budget rail: the Search button is disabled and the
                        // cap is explained — never silently queued.
                        Label(linkedInBudgetMessage, systemImage: "hourglass")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
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
                    // LinkedIn searches have two phases (server spawn, then
                    // the search itself) — surface which one is running.
                    Text(searchingBoard == .linkedIn
                        ? (linkedInPhase ?? "Searching LinkedIn…")
                        : "Searching \((searchingBoard ?? selectedBoard).rawValue)…")
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
            case .linkedIn:
                List(linkedInResults) { lead in
                    LinkedInLeadResultRow(
                        lead: lead,
                        isImported: LinkedInMCPImportService.isImported(lead, importedURLs: importedURLs)
                    ) {
                        importResult(lead)
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
        switch selectedBoard {
        case .customSite:
            return "Point the agent at a small job board or company careers page. It browses the site, verifies each posting's page, and imports matches as pipeline leads."
        case .linkedIn:
            return "Search LinkedIn through the local MCP server and import results as pipeline leads. Titles land immediately; company and details arrive as each lead enriches."
        case .dice, .zipRecruiter:
            return "Search \(selectedBoard.rawValue) and import results as pipeline leads."
        }
    }

    /// The budget-exhausted explanation shown beside the disabled Search
    /// button (risk rail: the cap surfaces, it never silently queues).
    private var linkedInBudgetMessage: String {
        let budget = linkedInBudget
        if let nextAvailable = budget.nextAvailableDate() {
            return "Hourly LinkedIn call limit reached (\(budget.limit)/hr). Try again after \(nextAvailable.formatted(date: .omitted, time: .shortened))."
        }
        return "Hourly LinkedIn call limit reached (\(budget.limit)/hr). Try again later."
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
            case .linkedIn:
                // No pagination — one page per user-initiated search
                // (max_pages hard-defaults to 1; a new search is the explicit
                // way to see more).
                if !linkedInResults.isEmpty {
                    Text("\(linkedInResults.count) result\(linkedInResults.count == 1 ? "" : "s") • first page")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        case .linkedIn:
            searchLinkedIn()
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

    /// Run one LinkedIn search: consent gate → ensure the local MCP server
    /// is running → one `search_jobs` call (the only tool this board ever
    /// calls) through the rolling hourly budget → decode into leads. An
    /// auth-failure tool result maps to the single "sign in to linkedin.com
    /// in your browser" state with the standard Retry affordance; every
    /// other failure surfaces its own message. All loud, nothing degrades
    /// silently.
    private func searchLinkedIn() {
        let trimmedKeywords = linkedInKeywords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeywords.isEmpty, !isSearching else { return }
        guard linkedInServer.consentAccepted else {
            showingLinkedInConsent = true
            return
        }
        let budget = linkedInBudget
        guard !budget.isExhausted else {
            // The Search button disables when exhausted; this guard keeps
            // onSubmit paths honest too — with the explanation, never quietly.
            errorMessage = linkedInBudgetMessage
            return
        }
        isSearching = true
        searchingBoard = .linkedIn
        errorMessage = nil
        importSummary = nil
        linkedInPhase = "Starting LinkedIn server…"
        let location = linkedInLocation
        let datePosted = linkedInDatePosted
        let workTypes = LinkedInWorkType.allCases.filter { linkedInWorkTypes.contains($0) }
        Task {
            do {
                try await linkedInServer.ensureRunning()
                linkedInPhase = "Searching LinkedIn…"
                let activeClient: MCPStreamableHTTPClient
                if let linkedInClient {
                    activeClient = linkedInClient
                } else {
                    activeClient = MCPStreamableHTTPClient(
                        endpoint: LinkedInMCPServerService.endpoint,
                        requestTimeout: 180
                    )
                    linkedInClient = activeClient
                }
                linkedInResults = try await LinkedInMCPImportService.searchJobs(
                    keywords: trimmedKeywords,
                    location: location,
                    datePosted: datePosted,
                    workTypes: workTypes,
                    client: activeClient,
                    budget: budget
                )
                linkedInHasSearched = true
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
            searchingBoard = nil
            linkedInPhase = nil
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

    private func importResult(_ lead: LinkedInJobLead) {
        importSummary = nil
        if case .skipped(let reason) = LinkedInMCPImportService.importAsLead(lead, into: jobAppStore) {
            errorMessage = "Couldn't import \"\(lead.title)\": \(reason)"
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
        case .linkedIn:
            for lead in linkedInResults {
                switch LinkedInMCPImportService.importAsLead(lead, into: jobAppStore) {
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

// MARK: - LinkedIn lead row

/// A LinkedIn search result is deliberately thin: the search payload yields
/// only a stable job id + display title, so the row shows the title and the
/// canonical posting URL. Company/location/description arrive after import,
/// when the lead enriches — the row says so rather than showing blanks.
private struct LinkedInLeadResultRow: View {
    let lead: LinkedInJobLead
    let isImported: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lead.title)
                    .font(.headline)

                Text(lead.canonicalURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("Company and details load after import")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
            if let url = URL(string: lead.canonicalURL) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open on LinkedIn", systemImage: "safari")
                }
            }
        }
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
