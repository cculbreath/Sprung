//
//  JobScoutService.swift
//  Sprung
//
//  The Job Scout engine: automatically sources newly posted positions from
//  the run's enabled boards (Dice / ZipRecruiter / LinkedIn) and recommends
//  the best matches. Owns the run lifecycle (`start`/`cancel`, non-blocking,
//  progress via BackgroundActivityTracker), routes the JobScoutLoop's tools
//  into the existing board services (JobMCPImportService,
//  LinkedInMCPImportService/LinkedInJobDetailsService), filters pipeline +
//  run-local duplicates before the agent sees results, imports accepted
//  recommendations through the shared lead path (findDuplicateJobApp →
//  addJobApp(deferringPreprocessing:) → leadEnrichment.enqueue) at high
//  priority, and persists the run report.
//
//  LinkedIn rails: the board participates only behind the one-time risk
//  consent (`LinkedInMCPServerService.consentAccepted`) — a run without it
//  drops the board with a report note, never bypasses, never prompts (the UI
//  ensures consent BEFORE manual runs). Budget exhaustion and the one
//  auth-doctrine string surface as explanatory tool results so the loop
//  continues on other boards, and land in the report notes.
//

import Foundation

@Observable
@MainActor
final class JobScoutService {

    // MARK: - Contract Types

    enum ScoutBoard: String, CaseIterable, Codable, Identifiable {
        case dice
        case zipRecruiter
        case linkedIn

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dice: return "Dice"
            case .zipRecruiter: return "ZipRecruiter"
            case .linkedIn: return "LinkedIn"
            }
        }
    }

    struct ScoutRunConfig {
        var boards: Set<ScoutBoard>
        var keywords: [String]
        var location: String
        var guidance: String
        var recommendationCount: Int
    }

    struct ScoutRecommendation: Codable {
        let url: String
        let title: String
        let company: String
        let reasoning: String
        let imported: Bool
    }

    struct ScoutRunReport: Codable {
        let startedAt: Date
        let boardsSearched: [String]
        let resultsFound: Int
        let duplicatesDropped: Int
        let recommendations: [ScoutRecommendation]
        let notes: [String]
    }

    // MARK: - Observable State

    private(set) var isActive = false
    private(set) var lastReport: ScoutRunReport?

    // MARK: - Dependencies

    private let jobAppStore: JobAppStore
    private let knowledgeCardStore: KnowledgeCardStore
    private let candidateDossierStore: CandidateDossierStore
    private let preferencesStore: SearchPreferencesStore
    private let settingsStore: DiscoverySettingsStore
    private var llmFacade: LLMFacade?
    private weak var linkedInServerService: LinkedInMCPServerService?
    private weak var activityTracker: BackgroundActivityTracker?
    private var runTask: Task<Void, Never>?

    /// Prompt template resource (Sprung/Resources/Prompts/discovery_job_scout.txt).
    static let promptResourceName = "discovery_job_scout"

    init(
        jobAppStore: JobAppStore,
        knowledgeCardStore: KnowledgeCardStore,
        candidateDossierStore: CandidateDossierStore,
        preferencesStore: SearchPreferencesStore,
        settingsStore: DiscoverySettingsStore
    ) {
        self.jobAppStore = jobAppStore
        self.knowledgeCardStore = knowledgeCardStore
        self.candidateDossierStore = candidateDossierStore
        self.preferencesStore = preferencesStore
        self.settingsStore = settingsStore
    }

    /// Late LLM wiring — DiscoveryCoordinator calls this from
    /// `configureLLMService`, before any run can start.
    func configure(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }

    /// The app-lifetime LinkedIn MCP server service, wired by AppDependencies
    /// (same setter pattern as `JobLeadEnrichmentService.setLinkedInServerService`).
    /// Holds the consent flag and the server lifecycle; without it the
    /// LinkedIn board is dropped from runs with a note.
    func setLinkedInServerService(_ service: LinkedInMCPServerService) {
        self.linkedInServerService = service
    }

    /// Surface scout runs in the Background Activity window and the
    /// main-window indicator (forwarded by `DiscoveryCoordinator.setActivityTracker`).
    func setActivityTracker(_ tracker: BackgroundActivityTracker) {
        self.activityTracker = tracker
    }

    // MARK: - Run Lifecycle

    /// Start a scout run. Non-blocking: the run executes in its own task and
    /// reports progress through the BackgroundActivityTracker. A run already
    /// in flight makes this a no-op (logged, never queued). Consent-missing
    /// LinkedIn is dropped from the boards with a report note — the UI ensures
    /// consent BEFORE start on manual runs; auto-runs never prompt.
    func start(config: ScoutRunConfig) {
        guard !isActive else {
            Logger.warning("Job scout: start requested while a run is already active — ignored", category: .ai)
            return
        }
        isActive = true
        runTask = Task { [weak self] in
            guard let self else { return }
            await self.performRun(config: config)
            self.isActive = false
            self.runTask = nil
        }
    }

    // MARK: - Run Execution

    private func performRun(config: ScoutRunConfig) async {
        let startedAt = Date()
        let operationId = UUID().uuidString
        activityTracker?.trackOperation(id: operationId, type: .jobScout, name: "Job Scout")
        activityTracker?.updatePhase(operationId: operationId, phase: "Starting scout run")

        do {
            let report = try await runScout(config: config, startedAt: startedAt, operationId: operationId)
            lastReport = report
            settingsStore.lastScoutReport = report
            settingsStore.recordSuccessfulScoutRun()
            let importedCount = report.recommendations.filter(\.imported).count
            Logger.info(
                "✅ Job scout run complete: searched [\(report.boardsSearched.joined(separator: ", "))], "
                + "found \(report.resultsFound) (\(report.duplicatesDropped) duplicates dropped), "
                + "recommended \(report.recommendations.count), imported \(importedCount)"
                + (report.notes.isEmpty ? "" : "; notes: \(report.notes.joined(separator: " | "))"),
                category: .ai
            )
            activityTracker?.appendTranscript(
                operationId: operationId,
                entryType: .system,
                content: "Completed: \(report.recommendations.count) recommendation\(report.recommendations.count == 1 ? "" : "s"), \(importedCount) imported"
            )
            activityTracker?.markCompleted(operationId: operationId)
        } catch is CancellationError {
            Logger.info("Job scout run cancelled", category: .ai)
            activityTracker?.markFailed(operationId: operationId, error: "Cancelled")
        } catch {
            Logger.error("❌ Job scout run failed: \(error.localizedDescription)", category: .ai)
            activityTracker?.markFailed(operationId: operationId, error: error.localizedDescription)
        }
    }

    private func runScout(
        config: ScoutRunConfig,
        startedAt: Date,
        operationId: String
    ) async throws -> ScoutRunReport {
        // Consent gate: LinkedIn participates only behind the accepted
        // one-time risk consent. Never bypassed, never prompted from here.
        let (boards, consentNote) = Self.boardsAfterConsentGate(
            config.boards,
            linkedInConsentAccepted: linkedInServerService?.consentAccepted ?? false
        )
        let runState = JobScoutRunState()
        if let consentNote {
            Logger.info("Job scout: \(consentNote)", category: .ai)
            runState.addNote(consentNote)
        }
        guard !boards.isEmpty else {
            throw JobScoutError.noBoardsAvailable(
                consentNote ?? "no boards were enabled for this run"
            )
        }

        guard let llmFacade else {
            throw JobScoutError.notConfigured("the LLM service hasn't been configured yet")
        }
        let modelId = try ModelConfigResolver.resolve(
            key: DiscoveryAgentService.anthropicModelSettingKey,
            operation: "Job Scout"
        )
        let systemPrompt = try Self.loadPromptTemplate()

        let preferences = preferencesStore.current()
        let userMessage = Self.scoutUserMessage(
            boards: boards,
            keywords: config.keywords,
            location: config.location,
            preferences: preferences,
            recommendationCount: config.recommendationCount,
            guidance: config.guidance,
            knowledgeContext: knowledgeContext(),
            dossierContext: dossierContext(),
            today: Date()
        )

        let tracker = activityTracker
        let loop = JobScoutLoop(
            llmFacade: llmFacade,
            modelId: modelId,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            enabledBoards: boards,
            searchBoard: { [weak self] board, args in
                guard let self else {
                    return AnthropicToolOutput(content: "The scout service is gone.", isError: true)
                }
                return await self.executeBoardSearch(board: board, args: args, runState: runState)
            },
            fetchJobDetails: { [weak self] url in
                guard let self else {
                    return AnthropicToolOutput(content: "The scout service is gone.", isError: true)
                }
                return await self.executeJobDetailsFetch(url: url, runState: runState)
            },
            onProgress: { line in
                tracker?.updatePhase(operationId: operationId, phase: line)
            }
        )

        let submission = try await AnthropicToolLoopRunner(delegate: loop).run()
        if let emptyReason = submission.emptyReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !emptyReason.isEmpty {
            runState.addNote("Scout: \(emptyReason)")
        }

        // Cap at the configured count (the prompt states the limit; an
        // over-long submission is truncated rather than spent on a retry turn).
        var drafts = submission.recommendations
        if drafts.count > config.recommendationCount {
            runState.addNote(
                "The scout submitted \(drafts.count) recommendations; kept the first \(config.recommendationCount)."
            )
            drafts = Array(drafts.prefix(config.recommendationCount))
        }

        activityTracker?.updatePhase(operationId: operationId, phase: "Importing recommendations")
        let recommendations = drafts.map { importRecommendation($0, runState: runState) }

        return runState.makeReport(startedAt: startedAt, recommendations: recommendations)
    }

    // MARK: - Tool Execution: search_board

    private func executeBoardSearch(
        board: ScoutBoard,
        args: JobScoutSearchBoardArgs,
        runState: JobScoutRunState
    ) async -> AnthropicToolOutput {
        let rawResults: [ScoutSearchResult]
        do {
            switch board {
            case .dice:
                let payload = try await JobMCPImportService.searchDice(
                    Self.diceQuery(keywords: args.keywords, location: args.location),
                    client: JobMCPImportService.makeDiceClient()
                )
                rawResults = payload.jobs.compactMap(Self.scoutResult(from:))
            case .zipRecruiter:
                let payload = try await JobMCPImportService.searchZipRecruiter(
                    Self.zipRecruiterQuery(keywords: args.keywords, location: args.location),
                    client: JobMCPImportService.makeZipRecruiterClient()
                )
                rawResults = payload.jobs.compactMap(Self.scoutResult(from:))
            case .linkedIn:
                rawResults = try await searchLinkedIn(args: args)
            }
        } catch {
            let explanation = Self.boardFailureExplanation(board: board, error: error)
            runState.addNote(explanation)
            Logger.warning("⚠️ Job scout: \(explanation)", category: .ai)
            return AnthropicToolOutput(content: explanation, isError: true)
        }

        let (kept, dropped) = Self.dedupSearchResults(
            rawResults,
            board: board,
            seenURLs: &runState.seenURLs
        ) { [weak self] url, title, company in
            guard let self,
                  let existing = self.jobAppStore.findDuplicateJobApp(url: url, title: title, company: company) else {
                return nil
            }
            return (url != nil && !url!.isEmpty && existing.postingURL == url) ? .byURL : .byTitleCompany
        }
        runState.recordSearch(board: board, found: rawResults.count, duplicatesDropped: dropped)

        return Self.searchToolOutput(board: board, kept: kept, droppedDuplicates: dropped)
    }

    private func searchLinkedIn(args: JobScoutSearchBoardArgs) async throws -> [ScoutSearchResult] {
        guard let serverService = linkedInServerService else {
            throw JobScoutError.notConfigured("the LinkedIn server service isn't wired")
        }
        try await serverService.ensureRunning()
        let client = MCPStreamableHTTPClient(
            endpoint: LinkedInMCPServerService.endpoint,
            requestTimeout: 180
        )
        let leads = try await LinkedInMCPImportService.searchJobs(
            keywords: args.keywords,
            location: args.location ?? "",
            datePosted: Self.linkedInDatePosted(from: args.datePosted),
            workTypes: [],
            client: client,
            budget: LinkedInCallBudget()
        )
        return leads.map(Self.scoutResult(from:))
    }

    // MARK: - Tool Execution: get_job_details

    private func executeJobDetailsFetch(
        url: String,
        runState: JobScoutRunState
    ) async -> AnthropicToolOutput {
        guard let jobId = LinkedInJobDetailsService.jobId(fromURL: url) else {
            return AnthropicToolOutput(
                content: "get_job_details supports LinkedIn posting URLs only — Dice results already "
                    + "carry a description snippet and ZipRecruiter URLs cannot be fetched. Judge those "
                    + "boards' results on what search_board returned.",
                isError: true
            )
        }
        guard let serverService = linkedInServerService else {
            let note = "LinkedIn details unavailable: the LinkedIn server service isn't wired."
            runState.addNote(note)
            return AnthropicToolOutput(content: note, isError: true)
        }
        do {
            let postingText = try await LinkedInJobDetailsService.fetchPostingText(
                jobId: jobId,
                serverService: serverService
            )
            return AnthropicToolOutput(content: String(postingText.prefix(Self.maxPostingTextLength)))
        } catch {
            let explanation = "LinkedIn details fetch failed: \(error.localizedDescription)"
            runState.addNote(explanation)
            Logger.warning("⚠️ Job scout: \(explanation)", category: .ai)
            return AnthropicToolOutput(content: explanation, isError: true)
        }
    }

    /// Posting-text cap for get_job_details tool results — a posting's facts
    /// never need more, and fetched pages otherwise dominate the conversation.
    static let maxPostingTextLength = 6000

    // MARK: - Recommendation Import (shared two-stage lead pipeline)

    /// Import one accepted recommendation as a `.new` high-priority pipeline
    /// lead: dedup through the shared `JobAppStore.findDuplicateJobApp`, land
    /// instantly with preprocessing deferred, queue background enrichment
    /// (which fetches the full posting and drives preprocessing). Returns the
    /// report record with the actual import outcome.
    private func importRecommendation(
        _ draft: JobScoutRecommendationDraft,
        runState: JobScoutRunState
    ) -> ScoutRecommendation {
        let imported: Bool
        if jobAppStore.findDuplicateJobApp(url: draft.url, title: draft.title, company: draft.company) != nil {
            imported = false
        } else if let jobApp = Self.makeJobApp(from: draft),
                  let inserted = jobAppStore.addJobApp(jobApp, deferringPreprocessing: true) {
            jobAppStore.leadEnrichment.enqueue(inserted, store: jobAppStore)
            imported = true
        } else {
            runState.addNote("Couldn't save the recommended lead '\(draft.title)' at \(draft.company).")
            Logger.error("❌ Job scout: failed to import recommendation '\(draft.title)' (\(draft.url))", category: .ai)
            imported = false
        }
        return ScoutRecommendation(
            url: draft.url,
            title: draft.title,
            company: draft.company,
            reasoning: draft.reasoning,
            imported: imported
        )
    }

    // MARK: - Context Assembly

    /// Knowledge context, built the same way ChooseBestJobsFlow builds it:
    /// every approved card's type, title, and narrative.
    private func knowledgeContext() -> String {
        knowledgeCardStore.approvedCards
            .map { card in
                let typeLabel = "[\(card.cardType?.rawValue ?? "general")]"
                return "\(typeLabel) \(card.title):\n\(card.narrative)"
            }
            .joined(separator: "\n\n")
    }

    /// Dossier context: the same job-matching export the Choose Best Jobs
    /// triage feeds its model.
    private func dossierContext() -> String {
        candidateDossierStore.dossier?.exportForJobMatching() ?? ""
    }

    // MARK: - Pure Helpers (static — covered by JobScoutServiceTests)

    /// Drop LinkedIn from the run's boards when the one-time risk consent has
    /// not been accepted. Returns the surviving boards and the report note
    /// explaining the drop (nil when nothing was dropped).
    static func boardsAfterConsentGate(
        _ boards: Set<ScoutBoard>,
        linkedInConsentAccepted: Bool
    ) -> (boards: Set<ScoutBoard>, note: String?) {
        guard boards.contains(.linkedIn), !linkedInConsentAccepted else {
            return (boards, nil)
        }
        var remaining = boards
        remaining.remove(.linkedIn)
        return (
            remaining,
            "LinkedIn was skipped: the one-time LinkedIn consent hasn't been accepted. "
            + "Run a manual scout (or a LinkedIn board search) to review and accept it."
        )
    }

    /// Map `search_board` args onto Dice's search query.
    static func diceQuery(keywords: String, location: String?) -> DiceSearchQuery {
        DiceSearchQuery(keyword: keywords, location: location ?? "")
    }

    /// Map `search_board` args onto ZipRecruiter's search query.
    static func zipRecruiterQuery(keywords: String, location: String?) -> JobMCPImportService.ZipRecruiterSearchQuery {
        JobMCPImportService.ZipRecruiterSearchQuery(jobRole: keywords, location: location ?? "")
    }

    /// Map the camelCase `datePosted` tool value onto LinkedIn's facet.
    /// Unknown/absent values mean no filter — the facet is an optimization,
    /// never worth failing a search over.
    static func linkedInDatePosted(from raw: String?) -> LinkedInDatePosted? {
        switch raw {
        case "pastHour": return .pastHour
        case "past24Hours": return .past24Hours
        case "pastWeek": return .pastWeek
        case "pastMonth": return .pastMonth
        default: return nil
        }
    }

    /// One compact search result as returned to the agent (camelCase keys we
    /// control; nil fields are omitted from the JSON).
    struct ScoutSearchResult: Codable, Equatable {
        let title: String
        let company: String?
        let location: String?
        let url: String
        let snippet: String?
        let salary: String?
        let postedDate: String?
    }

    /// Description-snippet cap in search results — enough to judge relevance
    /// without letting one board's results dominate the conversation.
    static let maxSnippetLength = 600

    static func scoutResult(from result: DiceJobResult) -> ScoutSearchResult? {
        guard let title = result.title, !title.isEmpty,
              let rawURL = result.detailsPageUrl, !rawURL.isEmpty else {
            return nil
        }
        let summary = (result.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ScoutSearchResult(
            title: title,
            company: result.companyName,
            location: result.jobLocation?.displayName,
            url: JobMCPImportService.normalizedPostingURL(rawURL),
            snippet: summary.isEmpty ? nil : String(summary.prefix(maxSnippetLength)),
            salary: result.salary,
            postedDate: result.postedDate.map(JobMCPImportService.displayPostedDate)
        )
    }

    static func scoutResult(from result: JobMCPImportService.ZipRecruiterJobResult) -> ScoutSearchResult? {
        guard let title = result.title, !title.isEmpty,
              let url = result.jobRedirectUrl, !url.isEmpty else {
            return nil
        }
        let location: String?
        if result.isRemote == true {
            let base = result.location ?? ""
            location = base.isEmpty ? "Remote" : "\(base) (Remote)"
        } else {
            location = result.location
        }
        return ScoutSearchResult(
            title: title,
            company: result.company,
            location: location,
            url: url,
            snippet: nil,
            salary: JobMCPImportService.displaySalaryRange(result.salary),
            postedDate: result.daysAgo.map(JobMCPImportService.displayDaysAgo)
        )
    }

    static func scoutResult(from lead: LinkedInJobLead) -> ScoutSearchResult {
        ScoutSearchResult(
            title: lead.title,
            company: nil,
            location: nil,
            url: lead.canonicalURL,
            snippet: nil,
            salary: nil,
            postedDate: nil
        )
    }

    /// How an existing pipeline job matched a search result.
    enum PipelineMatchKind {
        case byURL
        case byTitleCompany
    }

    /// Filter a board's raw results before the agent sees them: drop postings
    /// already returned this run (cross-board seen-URL set) and postings
    /// already in the pipeline. Per-board pipeline-match rules mirror each
    /// board's import path:
    ///  - dice: URL match or title+company match
    ///  - zipRecruiter: title+company only (`url` passed nil — redirect
    ///    tokens are unstable, never a dedup key)
    ///  - linkedIn: URL match ONLY (company is unknown at search time, so a
    ///    title+empty-company fallback would false-match unrelated postings)
    static func dedupSearchResults(
        _ results: [ScoutSearchResult],
        board: ScoutBoard,
        seenURLs: inout Set<String>,
        pipelineMatch: (_ url: String?, _ title: String, _ company: String) -> PipelineMatchKind?
    ) -> (kept: [ScoutSearchResult], dropped: Int) {
        var kept: [ScoutSearchResult] = []
        var dropped = 0
        for result in results {
            if seenURLs.contains(result.url) {
                dropped += 1
                continue
            }
            seenURLs.insert(result.url)

            let dedupURL: String? = (board == .zipRecruiter) ? nil : result.url
            let match = pipelineMatch(dedupURL, result.title, result.company ?? "")
            let isPipelineDuplicate: Bool
            switch match {
            case nil:
                isPipelineDuplicate = false
            case .some(.byTitleCompany):
                isPipelineDuplicate = (board != .linkedIn)
            case .some(.byURL):
                isPipelineDuplicate = true
            }
            if isPipelineDuplicate {
                dropped += 1
            } else {
                kept.append(result)
            }
        }
        return (kept, dropped)
    }

    /// The `search_board` tool-result payload (camelCase keys we control).
    struct SearchBoardResultPayload: Codable {
        let board: String
        let droppedDuplicates: Int
        let results: [ScoutSearchResult]
    }

    /// Encode a board's deduplicated results as the tool result.
    static func searchToolOutput(
        board: ScoutBoard,
        kept: [ScoutSearchResult],
        droppedDuplicates: Int
    ) -> AnthropicToolOutput {
        let payload = SearchBoardResultPayload(
            board: board.rawValue,
            droppedDuplicates: droppedDuplicates,
            results: kept
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(payload)
            return AnthropicToolOutput(content: String(decoding: data, as: UTF8.self))
        } catch {
            // Encodable Strings/Ints can't realistically fail, but never
            // answer a tool_use silently wrong if they somehow do.
            Logger.error("❌ Job scout: search result payload failed to encode: \(error.localizedDescription)", category: .ai)
            return AnthropicToolOutput(
                content: "The \(board.displayName) search succeeded but its results couldn't be encoded.",
                isError: true
            )
        }
    }

    /// One plain sentence explaining a failed board search — sent to the
    /// agent as the tool result (so it continues on other boards) and added
    /// to the report notes. LinkedIn auth failures use the single doctrine
    /// string; every other error keeps its own description.
    static func boardFailureExplanation(board: ScoutBoard, error: Error) -> String {
        if board == .linkedIn, LinkedInMCPImportService.isAuthFailure(error) {
            return "LinkedIn: \(LinkedInMCPImportService.noSessionMessage)"
        }
        return "\(board.displayName) search failed: \(error.localizedDescription)"
    }

    /// Map an accepted recommendation to a fresh high-priority `.new` lead.
    /// The description lands empty — enrichment fetches the full posting in
    /// the background (LinkedIn URLs route through the local MCP server).
    static func makeJobApp(from draft: JobScoutRecommendationDraft) -> JobApp? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let company = draft.company.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !company.isEmpty, !draft.url.isEmpty else {
            return nil
        }
        let jobApp = JobApp()
        jobApp.jobPosition = title
        jobApp.companyName = company
        jobApp.postingURL = draft.url
        jobApp.jobApplyLink = draft.url
        jobApp.status = .new
        jobApp.identifiedDate = Date()
        jobApp.source = "Scout"
        jobApp.priority = .high
        return jobApp
    }

    /// Build the scout task message: enabled boards, role keywords, location,
    /// arrangement preferences, the recommendation limit, today's date, then
    /// the candidate context blocks and the delimited guidance block (scoped
    /// by the prompt to steering, never to loosening judgment).
    static func scoutUserMessage(
        boards: Set<ScoutBoard>,
        keywords: [String],
        location: String,
        preferences: SearchPreferences,
        recommendationCount: Int,
        guidance: String,
        knowledgeContext: String,
        dossierContext: String,
        today: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let boardList = ScoutBoard.allCases
            .filter(boards.contains)
            .map(\.rawValue)
            .joined(separator: ", ")
        var arrangement = preferences.preferredArrangement.rawValue
        if preferences.remoteAcceptable, preferences.preferredArrangement != .remote {
            arrangement += " (remote acceptable)"
        }

        var message = """
            Scout the enabled job boards for newly posted positions worth this candidate's attention.

            ENABLED BOARDS: \(boardList)
            ROLE KEYWORDS: \(keywords.joined(separator: ", "))
            LOCATION: \(location)
            WORK ARRANGEMENT PREFERENCE: \(arrangement)
            RECOMMENDATION LIMIT: \(recommendationCount)
            Today: \(formatter.string(from: today))
            """
        if !knowledgeContext.isEmpty {
            message += "\n\n## CANDIDATE KNOWLEDGE CARDS\n\(knowledgeContext)"
        }
        if !dossierContext.isEmpty {
            message += "\n\n## CANDIDATE DOSSIER\n\(dossierContext)"
        }
        let trimmedGuidance = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGuidance.isEmpty {
            message += "\n\n## GUIDANCE FROM THE USER\n\(trimmedGuidance)"
        }
        return message
    }

    // MARK: - Prompt Loading

    static func loadPromptTemplate() throws -> String {
        guard let url = Bundle.main.url(forResource: promptResourceName, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(promptResourceName)", category: .ai)
            throw JobScoutError.promptTemplateMissing(promptResourceName)
        }
        return content
    }
}

// MARK: - Run State

/// Mutable per-run bookkeeping the tool closures write into: which boards
/// actually got searched, found/duplicate counts, the cross-board seen-URL
/// set, and the report notes. A class so the loop's closures and the
/// service's completion path share one instance.
@MainActor
final class JobScoutRunState {
    /// Boards searched this run, in first-search order (deduplicated).
    private(set) var boardsSearched: [JobScoutService.ScoutBoard] = []
    private(set) var resultsFound = 0
    private(set) var duplicatesDropped = 0
    private(set) var notes: [String] = []
    /// Cross-board run-local dedup: every result URL already returned to the
    /// agent this run.
    var seenURLs: Set<String> = []

    func recordSearch(board: JobScoutService.ScoutBoard, found: Int, duplicatesDropped: Int) {
        if !boardsSearched.contains(board) {
            boardsSearched.append(board)
        }
        resultsFound += found
        self.duplicatesDropped += duplicatesDropped
    }

    func addNote(_ note: String) {
        notes.append(note)
    }

    func makeReport(
        startedAt: Date,
        recommendations: [JobScoutService.ScoutRecommendation]
    ) -> JobScoutService.ScoutRunReport {
        JobScoutService.ScoutRunReport(
            startedAt: startedAt,
            boardsSearched: boardsSearched.map(\.displayName),
            resultsFound: resultsFound,
            duplicatesDropped: duplicatesDropped,
            recommendations: recommendations,
            notes: notes
        )
    }
}
