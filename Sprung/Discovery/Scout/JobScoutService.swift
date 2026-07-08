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
import SwiftOpenAI

@Observable
@MainActor
final class JobScoutService {

    // MARK: - Contract Types

    enum ScoutBoard: String, CaseIterable, Codable, Identifiable {
        case dice
        case zipRecruiter
        case linkedIn
        case jsearch
        case serpApi
        case indeed

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dice: return "Dice"
            case .zipRecruiter: return "ZipRecruiter"
            case .linkedIn: return "LinkedIn"
            case .jsearch: return "JSearch"
            case .serpApi: return "SerpApi"
            case .indeed: return "Indeed"
            }
        }

        /// Aggregator boards need a user-provided API key (BYO). Off by default,
        /// and dropped from a run with a note when the key is missing — never a
        /// silent no-result. JSearch and Indeed share the RapidAPI key.
        var requiresAPIKey: Bool {
            switch self {
            case .jsearch, .serpApi, .indeed: return true
            case .dice, .zipRecruiter, .linkedIn: return false
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
        /// Where a recommendation stands in the user's review. A run produces
        /// `pending` picks — or `alreadyInPipeline` for duplicates, or
        /// `imported` when the auto-import-strong setting is on and the verdict
        /// is strong. The review UI moves each `pending` pick to `imported` or
        /// `dismissed`; nothing enters the pipeline without passing through it.
        enum Disposition: String, Codable {
            case pending
            case imported
            case dismissed
            case alreadyInPipeline
        }
        let url: String
        let title: String
        let company: String
        let reasoning: String
        let match: JobScoutMatchAssessment
        var disposition: Disposition
    }

    struct ScoutRunReport: Codable {
        let startedAt: Date
        let boardsSearched: [String]
        let resultsFound: Int
        let duplicatesDropped: Int
        /// Results removed because the user dismissed them in a past review —
        /// counted apart from pipeline duplicates so the report can explain why
        /// the list shrank (cross-run memory, not this-run bookkeeping).
        let previouslyDismissedDropped: Int
        var recommendations: [ScoutRecommendation]
        let notes: [String]
    }

    /// A posting the user dismissed in a scout review. Persisted (with a TTL)
    /// in `DiscoverySettingsStore.scoutDismissedPostings` and filtered out of
    /// future runs' search results so a rejected posting stays gone. Matched by
    /// URL, or by title+company when the URL is unstable (ZipRecruiter redirect
    /// tokens), where the same posting can return under a different link.
    struct ScoutDismissedPosting: Codable, Equatable {
        let url: String
        let title: String
        let company: String
        let dismissedAt: Date
        /// The reason the user gave when dismissing, if any — carried into the
        /// next run's outcome-feedback context so the agent calibrates.
        let reason: String?
    }

    /// A past scout pick and where it ended up in the pipeline, for the
    /// outcome-feedback context. `statusLabel` names the stage it reached
    /// (applied and beyond); nil for a pick still sitting as an unactioned lead.
    struct ScoutOutcomePick: Equatable {
        let title: String
        let company: String
        let statusLabel: String?
    }

    // MARK: - Observable State

    private(set) var isActive = false
    /// Completed runs, newest first, capped. The source of truth the review UI
    /// observes so import/dismiss decisions render live; written through to
    /// `DiscoverySettingsStore.scoutRunHistory` on every change so pending
    /// picks survive relaunches (an unattended run's recommendations wait here
    /// until the user curates them).
    private(set) var runHistory: [ScoutRunReport] = []

    /// The most recent run's report — the one PipelineView surfaces and the
    /// review sheet curates by default.
    var lastReport: ScoutRunReport? { runHistory.first }

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
        self.runHistory = settingsStore.scoutRunHistory
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
            prependToHistory(report)
            settingsStore.recordSuccessfulScoutRun()
            let pendingCount = Self.pendingCount(in: report)
            let importedCount = report.recommendations.filter { $0.disposition == .imported }.count
            Logger.info(
                "✅ Job scout run complete: searched [\(report.boardsSearched.joined(separator: ", "))], "
                + "found \(report.resultsFound) (\(report.duplicatesDropped) duplicates dropped), "
                + "recommended \(report.recommendations.count) (\(pendingCount) awaiting review, \(importedCount) auto-imported)"
                + (report.notes.isEmpty ? "" : "; notes: \(report.notes.joined(separator: " | "))"),
                category: .ai
            )
            activityTracker?.appendTranscript(
                operationId: operationId,
                entryType: .system,
                content: "Completed: \(report.recommendations.count) recommendation\(report.recommendations.count == 1 ? "" : "s") for review"
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
        let (consentBoards, consentNote) = Self.boardsAfterConsentGate(
            config.boards,
            linkedInConsentAccepted: linkedInServerService?.consentAccepted ?? false
        )
        // Aggregator boards (JSearch/SerpApi) need a BYO API key; drop keyless
        // ones with a note rather than failing a search turn on them.
        let (boards, keyNotes) = Self.boardsAfterKeyGate(
            consentBoards,
            rapidApiKeyPresent: APIKeyStore.get(.rapidApi) != nil,
            serpApiKeyPresent: APIKeyStore.get(.serpApi) != nil
        )
        let runState = JobScoutRunState(dismissed: settingsStore.scoutDismissedPostings)
        if let consentNote {
            Logger.info("Job scout: \(consentNote)", category: .ai)
            runState.addNote(consentNote)
        }
        for note in keyNotes {
            Logger.info("Job scout: \(note)", category: .ai)
            runState.addNote(note)
        }
        guard !boards.isEmpty else {
            throw JobScoutError.noBoardsAvailable(
                consentNote ?? keyNotes.first ?? "no boards were enabled for this run"
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
            learnedPreferences: settingsStore.scoutTasteProfile,
            outcomeContext: outcomeFeedbackContext(),
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
        // Order strongest verdict first for the report and review UI; the cap
        // above already kept the agent's own top picks.
        drafts = Self.sortedByVerdict(drafts)

        activityTracker?.updatePhase(operationId: operationId, phase: "Preparing recommendations for review")
        let autoImportStrong = settingsStore.scoutAutoImportStrongMatches
        let recommendations = drafts.map { buildInitialRecommendation($0, autoImportStrong: autoImportStrong) }

        // Refresh the learned taste profile if enough decisions have accrued
        // since the last synthesis (uses the model already resolved for this run).
        await synthesizeTasteProfileIfDue(modelId: modelId, runState: runState)

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
            case .jsearch:
                let jobs = try await AggregatorJobSearchService.searchJSearch(
                    keywords: args.keywords,
                    location: args.location,
                    datePosted: args.datePosted,
                    country: Self.aggregatorCountry,
                    apiKey: APIKeyStore.get(.rapidApi) ?? ""
                )
                rawResults = jobs.compactMap(Self.scoutResult(from:))
            case .serpApi:
                let jobs = try await AggregatorJobSearchService.searchSerpApi(
                    keywords: args.keywords,
                    location: args.location,
                    apiKey: APIKeyStore.get(.serpApi) ?? ""
                )
                rawResults = jobs.compactMap(Self.scoutResult(from:))
            case .indeed:
                let jobs = try await AggregatorJobSearchService.searchIndeed(
                    keywords: args.keywords,
                    location: args.location,
                    countryCode: Self.aggregatorCountry,
                    datePosted: args.datePosted,
                    apiKey: APIKeyStore.get(.rapidApi) ?? ""
                )
                rawResults = jobs.compactMap(Self.scoutResult(from:))
            }
        } catch {
            let explanation = Self.boardFailureExplanation(board: board, error: error)
            runState.addNote(explanation)
            Logger.warning("⚠️ Job scout: \(explanation)", category: .ai)
            return AnthropicToolOutput(content: explanation, isError: true)
        }

        let (kept, dropped, dismissedDropped) = Self.dedupSearchResults(
            rawResults,
            board: board,
            seenURLs: &runState.seenURLs,
            dismissed: runState.dismissed
        ) { [weak self] url, title, company in
            guard let self,
                  let existing = self.jobAppStore.findDuplicateJobApp(url: url, title: title, company: company) else {
                return nil
            }
            return (url != nil && !url!.isEmpty && existing.postingURL == url) ? .byURL : .byTitleCompany
        }
        runState.recordSearch(
            board: board,
            found: rawResults.count,
            duplicatesDropped: dropped,
            previouslyDismissedDropped: dismissedDropped
        )

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
                content: "get_job_details is for LinkedIn posting URLs only. Read Dice and ZipRecruiter "
                    + "postings with web_fetch on the posting url instead.",
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

    // MARK: - Recommendation Build + Review

    /// Turn a fresh draft into a report record. Nothing enters the pipeline by
    /// default — the pick lands `pending` for the user's review. A draft that
    /// duplicates an existing pipeline job is `alreadyInPipeline`; a strong
    /// verdict is auto-imported only when the user has opted into that setting.
    private func buildInitialRecommendation(
        _ draft: JobScoutRecommendationDraft,
        autoImportStrong: Bool
    ) -> ScoutRecommendation {
        let isDuplicate = jobAppStore.findDuplicateJobApp(
            url: draft.url, title: draft.title, company: draft.company
        ) != nil
        let intended = Self.initialDisposition(
            isDuplicate: isDuplicate,
            verdict: draft.match.verdict,
            autoImportStrong: autoImportStrong
        )
        let disposition = (intended == .imported) ? importIntoPipeline(draft) : intended
        return ScoutRecommendation(
            url: draft.url,
            title: draft.title,
            company: draft.company,
            reasoning: draft.reasoning,
            match: draft.match,
            disposition: disposition
        )
    }

    /// Bring one recommendation into the pipeline as a `.new` high-priority
    /// lead: dedup through the shared `JobAppStore.findDuplicateJobApp`, land
    /// instantly with preprocessing deferred, queue background enrichment
    /// (which fetches the full posting and drives preprocessing). Returns the
    /// resulting disposition — `.alreadyInPipeline` if a duplicate appeared,
    /// `.pending` (logged) if the save failed so the user can retry from the
    /// review sheet. Shared by auto-import and the manual accept action.
    private func importIntoPipeline(_ draft: JobScoutRecommendationDraft) -> ScoutRecommendation.Disposition {
        if jobAppStore.findDuplicateJobApp(url: draft.url, title: draft.title, company: draft.company) != nil {
            return .alreadyInPipeline
        }
        guard let jobApp = Self.makeJobApp(from: draft),
              let inserted = jobAppStore.addJobApp(jobApp, deferringPreprocessing: true) else {
            Logger.error("❌ Job scout: failed to import recommendation '\(draft.title)' (\(draft.url))", category: .ai)
            return .pending
        }
        jobAppStore.leadEnrichment.enqueue(inserted, store: jobAppStore)
        return .imported
    }

    /// The report for a completed run, addressed by its start time (stable
    /// identity across the review UI and relaunches).
    func report(forRunStartedAt startedAt: Date) -> ScoutRunReport? {
        runHistory.first { $0.startedAt == startedAt }
    }

    /// Accept a pending recommendation: import it into the pipeline and record
    /// the outcome. A no-op if the run or url isn't found.
    func acceptRecommendation(runStartedAt: Date, url: String) {
        guard let recommendation = report(forRunStartedAt: runStartedAt)?
            .recommendations.first(where: { $0.url == url }) else { return }
        settingsStore.recordScoutDecision()
        let draft = JobScoutRecommendationDraft(
            url: recommendation.url,
            title: recommendation.title,
            company: recommendation.company,
            reasoning: recommendation.reasoning,
            match: recommendation.match
        )
        let disposition = importIntoPipeline(draft)
        setDisposition(disposition, forURL: url, runStartedAt: runStartedAt)
    }

    /// Dismiss a pending recommendation: record it in the cross-run dismissed
    /// set (so it never returns) and mark it dismissed. A no-op if not found.
    func dismissRecommendation(runStartedAt: Date, url: String, reason: String?) {
        guard let recommendation = report(forRunStartedAt: runStartedAt)?
            .recommendations.first(where: { $0.url == url }) else { return }
        settingsStore.recordScoutDecision()
        settingsStore.recordDismissedPostings([
            ScoutDismissedPosting(
                url: recommendation.url,
                title: recommendation.title,
                company: recommendation.company,
                dismissedAt: Date(),
                reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? reason : nil
            )
        ])
        setDisposition(.dismissed, forURL: url, runStartedAt: runStartedAt)
    }

    /// Apply a disposition change through the pure helper and persist.
    private func setDisposition(
        _ disposition: ScoutRecommendation.Disposition,
        forURL url: String,
        runStartedAt: Date
    ) {
        let updated = Self.settingDisposition(disposition, forURL: url, runStartedAt: runStartedAt, in: runHistory)
        runHistory = updated
        settingsStore.scoutRunHistory = updated
    }

    /// Prepend a completed run to the history (newest first), cap it, and
    /// persist. The in-memory array is the observable source of truth; the
    /// settings-store blob is its durable mirror.
    private func prependToHistory(_ report: ScoutRunReport) {
        var history = runHistory
        history.insert(report, at: 0)
        history = Array(history.prefix(DiscoverySettingsStore.scoutRunHistoryCap))
        runHistory = history
        settingsStore.scoutRunHistory = history
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

    /// Gather scout-outcome signal from the pipeline (scout-sourced leads
    /// partitioned by how far they progressed) and the dismissed set, each
    /// section capped (most recent first). Shared by the per-run outcome block
    /// and the taste-profile synthesis (which uses a larger cap).
    private func scoutOutcomeSignal(
        cap: Int
    ) -> (applied: [ScoutOutcomePick], imported: [ScoutOutcomePick], dismissed: [ScoutDismissedPosting]) {
        let scoutApps = jobAppStore.jobApps
            .filter { $0.source == "Scout" }
            .sorted { ($0.identifiedDate ?? .distantPast) > ($1.identifiedDate ?? .distantPast) }

        var applied: [ScoutOutcomePick] = []
        var imported: [ScoutOutcomePick] = []
        for app in scoutApps {
            switch app.status {
            case .submitted, .interview, .offer, .accepted:
                applied.append(ScoutOutcomePick(
                    title: app.jobPosition, company: app.companyName, statusLabel: app.status.displayName
                ))
            case .new, .queued, .inProgress:
                imported.append(ScoutOutcomePick(
                    title: app.jobPosition, company: app.companyName, statusLabel: nil
                ))
            case .rejected, .withdrawn:
                break   // terminal/ambiguous — a poor calibration signal
            }
        }

        let dismissed = settingsStore.scoutDismissedPostings
            .sorted { $0.dismissedAt > $1.dismissedAt }
            .prefix(cap)

        return (Array(applied.prefix(cap)), Array(imported.prefix(cap)), Array(dismissed))
    }

    /// Outcome-feedback context: what the user actually did with past scout
    /// picks. Empty string when there's no history yet.
    private func outcomeFeedbackContext() -> String {
        let signal = scoutOutcomeSignal(cap: Self.outcomeFeedbackMaxPerSection)
        return Self.outcomeFeedbackContext(
            appliedOrBeyond: signal.applied,
            importedPending: signal.imported,
            dismissed: signal.dismissed
        )
    }

    // MARK: - Learned Taste Profile Synthesis

    /// Re-synthesize the learned taste profile after this many accept/dismiss
    /// decisions accrue — often enough to track shifting taste, rare enough to
    /// stay cheap.
    static let tasteProfileSynthesisThreshold = 10
    /// A larger outcome slice for synthesis than the per-run block uses — the
    /// profile distills the longer tail of decisions.
    static let tasteProfileSynthesisCap = 40
    /// Output cap for the synthesis call — a few sentences of prose, never
    /// structured output, so no truncation trap.
    static let tasteProfileMaxTokens = 500

    static let tasteProfileSystemPrompt = """
        You maintain a short "taste profile" for one job seeker — a few plain sentences capturing what kinds of roles they actually pursue and what they pass on, learned from their real decisions. You are given the previous profile (if any) and a record of what they recently applied to, imported, and dismissed (with their reasons).

        Write 3 to 6 plain sentences. Capture concrete, durable preferences: the role types and seniority they pursue, work-arrangement and location constraints, compensation expectations if evident, sectors or company types they favor or avoid, and consistent dealbreakers (especially from stated dismissal reasons). Update the previous profile toward the pattern the evidence shows; drop anything the latest evidence contradicts.

        Be specific and honest in the candidate's own terms. No hedging, no invented specifics, no recruiter buzzwords ("leverage", "synergy", "dynamic", "results-driven", "cutting-edge", "fast-paced"), no "[verb] [thing] resulting in [X]% improvement" formulas. If the evidence is too thin to say anything durable, keep the previous profile (or write one honest sentence if there was none).

        Output only the profile text — no preamble, no headings, no list.
        """

    /// Build the synthesis user message from the previous profile and a summary
    /// of recent decisions (pure — the LLM-driven half is the service call).
    static func tasteProfileUserMessage(previousProfile: String, outcomeSummary: String) -> String {
        let trimmed = previousProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            trimmed.isEmpty ? "There is no previous taste profile yet." : "Previous taste profile:\n\(trimmed)",
            "The user's recent decisions:\n\(outcomeSummary)",
            "Write the updated taste profile now."
        ].joined(separator: "\n\n")
    }

    /// Extract the profile text from a synthesis response (pure). Nil when the
    /// model returned no usable text.
    static func parseTasteProfile(from response: AnthropicMessageResponse) -> String? {
        let text = response.content.compactMap { block -> String? in
            if case .text(let textBlock) = block { return textBlock.text }
            return nil
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// When enough review decisions have accrued, distill them into a refreshed
    /// taste profile. Loud but non-fatal — a failure notes the report and keeps
    /// the previous profile; it never blocks or fails the run.
    private func synthesizeTasteProfileIfDue(modelId: String, runState: JobScoutRunState) async {
        guard settingsStore.scoutDecisionsSinceSynthesis >= Self.tasteProfileSynthesisThreshold,
              let llmFacade else { return }
        let signal = scoutOutcomeSignal(cap: Self.tasteProfileSynthesisCap)
        let outcomeSummary = Self.outcomeFeedbackContext(
            appliedOrBeyond: signal.applied, importedPending: signal.imported, dismissed: signal.dismissed
        )
        guard !outcomeSummary.isEmpty else { return }

        let decisionCount = settingsStore.scoutDecisionsSinceSynthesis
        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: [.user(Self.tasteProfileUserMessage(
                previousProfile: settingsStore.scoutTasteProfile,
                outcomeSummary: outcomeSummary
            ))],
            system: .text(Self.tasteProfileSystemPrompt),
            maxTokens: Self.tasteProfileMaxTokens,
            stream: false
        )
        do {
            let response = try await llmFacade.anthropicMessages(parameters: parameters)
            guard let profile = Self.parseTasteProfile(from: response) else {
                runState.addNote("Couldn't refresh the scout's learned preferences: the model returned no text.")
                Logger.warning("Job scout: taste-profile synthesis returned empty", category: .ai)
                return
            }
            settingsStore.applyTasteProfile(profile)
            Logger.info("Job scout: refreshed the learned-preferences profile from \(decisionCount) decisions", category: .ai)
        } catch {
            runState.addNote("Couldn't refresh the scout's learned preferences: \(error.localizedDescription)")
            Logger.error("❌ Job scout: taste-profile synthesis failed: \(error.localizedDescription)", category: .ai)
        }
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

    /// Drop the aggregator boards whose BYO API key isn't configured, with a
    /// note pointing at Settings. Returns the surviving boards and one note per
    /// dropped board — never a silent no-result.
    static func boardsAfterKeyGate(
        _ boards: Set<ScoutBoard>,
        rapidApiKeyPresent: Bool,
        serpApiKeyPresent: Bool
    ) -> (boards: Set<ScoutBoard>, notes: [String]) {
        var remaining = boards
        var notes: [String] = []
        // JSearch and Indeed both authenticate with the shared RapidAPI key.
        if !rapidApiKeyPresent {
            if boards.contains(.jsearch) {
                remaining.remove(.jsearch)
                notes.append("JSearch was skipped: add your RapidAPI key under Settings > API Keys.")
            }
            if boards.contains(.indeed) {
                remaining.remove(.indeed)
                notes.append("Indeed was skipped: add your RapidAPI key under Settings > API Keys.")
            }
        }
        if boards.contains(.serpApi), !serpApiKeyPresent {
            remaining.remove(.serpApi)
            notes.append("SerpApi was skipped: add your SerpApi API key under Settings > API Keys.")
        }
        return (remaining, notes)
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

    /// ISO country code the aggregator boards search. Matches the US-oriented
    /// Dice/ZipRecruiter/LinkedIn setup; a single place to change if the user
    /// searches another market.
    static let aggregatorCountry = "us"

    static func scoutResult(from result: JSearchJobResult) -> ScoutSearchResult? {
        guard let title = result.jobTitle, !title.isEmpty,
              let rawURL = result.jobApplyLink, !rawURL.isEmpty else {
            return nil
        }
        let cityState = [result.jobCity, result.jobState]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }
            .joined(separator: ", ")
        var location = cityState.isEmpty ? (result.jobCountry ?? "") : cityState
        if result.jobIsRemote == true {
            location = location.isEmpty ? "Remote" : "\(location) (Remote)"
        }
        let description = (result.jobDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let posted = result.jobPostedAtDatetimeUtc.map(JobMCPImportService.displayPostedDate) ?? result.jobPostedAt
        return ScoutSearchResult(
            title: title,
            company: result.employerName,
            location: location.isEmpty ? nil : location,
            url: JobMCPImportService.normalizedPostingURL(rawURL),
            snippet: description.isEmpty ? nil : String(description.prefix(maxSnippetLength)),
            salary: Self.aggregatorSalary(min: result.jobMinSalary, max: result.jobMaxSalary, period: result.jobSalaryPeriod),
            postedDate: posted
        )
    }

    static func scoutResult(from result: SerpApiJobResult) -> ScoutSearchResult? {
        guard let title = result.title, !title.isEmpty else { return nil }
        // Prefer a real apply link; fall back to the Google Jobs share link.
        let applyLink = result.applyOptions?.compactMap { $0.link }.first { !$0.isEmpty }
        guard let rawURL = applyLink ?? result.shareLink, !rawURL.isEmpty else { return nil }
        var location = result.location ?? ""
        if result.detectedExtensions?.workFromHome == true {
            location = location.isEmpty ? "Remote" : "\(location) (Remote)"
        }
        let description = (result.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ScoutSearchResult(
            title: title,
            company: result.companyName,
            location: location.isEmpty ? nil : location,
            url: JobMCPImportService.normalizedPostingURL(rawURL),
            snippet: description.isEmpty ? nil : String(description.prefix(maxSnippetLength)),
            salary: result.detectedExtensions?.salary,
            postedDate: result.detectedExtensions?.postedAt
        )
    }

    static func scoutResult(from result: IndeedJobResult) -> ScoutSearchResult? {
        guard let title = result.title, !title.isEmpty,
              let rawURL = result.applyUrl, !rawURL.isEmpty else {
            return nil
        }
        let description = (result.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ScoutSearchResult(
            title: title,
            company: result.company?.name,
            location: result.location?.location,
            url: JobMCPImportService.normalizedPostingURL(rawURL),
            snippet: description.isEmpty ? nil : String(description.prefix(maxSnippetLength)),
            salary: nil,
            postedDate: nil
        )
    }

    /// Format an aggregator's numeric salary range for display (nil when the
    /// posting gives no figures).
    static func aggregatorSalary(min: Double?, max: Double?, period: String?) -> String? {
        let money: (Double) -> String = { "$" + Int($0).formatted(.number) }
        let range: String
        switch (min, max) {
        case let (low?, high?): range = "\(money(low)) – \(money(high))"
        case let (low?, nil): range = "From \(money(low))"
        case let (nil, high?): range = "Up to \(money(high))"
        default: return nil
        }
        if let period, !period.isEmpty {
            return "\(range)/\(period.lowercased())"
        }
        return range
    }

    /// How an existing pipeline job matched a search result.
    enum PipelineMatchKind {
        case byURL
        case byTitleCompany
    }

    /// The disposition a fresh recommendation starts in. A duplicate of an
    /// existing pipeline job is `alreadyInPipeline`; otherwise a strong verdict
    /// is `imported` only when the user opted into auto-import; everything else
    /// waits for review as `pending`. Curation is the default — nothing is
    /// imported behind the user's back unless they asked for it.
    static func initialDisposition(
        isDuplicate: Bool,
        verdict: JobScoutMatchAssessment.Verdict,
        autoImportStrong: Bool
    ) -> ScoutRecommendation.Disposition {
        if isDuplicate { return .alreadyInPipeline }
        if autoImportStrong, verdict == .strong { return .imported }
        return .pending
    }

    /// Return a copy of the run history with one recommendation's disposition
    /// replaced (matched by run start time + posting url). A no-op copy when
    /// the run or the recommendation isn't found.
    static func settingDisposition(
        _ disposition: ScoutRecommendation.Disposition,
        forURL url: String,
        runStartedAt: Date,
        in history: [ScoutRunReport]
    ) -> [ScoutRunReport] {
        guard let reportIndex = history.firstIndex(where: { $0.startedAt == runStartedAt }),
              let recIndex = history[reportIndex].recommendations.firstIndex(where: { $0.url == url }) else {
            return history
        }
        var updated = history
        updated[reportIndex].recommendations[recIndex].disposition = disposition
        return updated
    }

    /// How many of a run's recommendations still await the user's decision.
    static func pendingCount(in report: ScoutRunReport?) -> Int {
        report?.recommendations.filter { $0.disposition == .pending }.count ?? 0
    }

    /// Cap per section of the outcome-feedback block — recent decisions are the
    /// calibration signal; the whole history would just be noise.
    static let outcomeFeedbackMaxPerSection = 10

    /// Compose the `## RECENT SCOUT OUTCOMES` block from the user's real
    /// decisions: what they applied to or advanced (the strongest fit signal),
    /// what they imported but haven't acted on, and what they dismissed (with
    /// reasons). Sections with nothing are omitted; an entirely empty history
    /// returns "" so the caller drops the block. Deterministic (no dates, no
    /// ordering surprises) to keep the cached prefix byte-stable.
    static func outcomeFeedbackContext(
        appliedOrBeyond: [ScoutOutcomePick],
        importedPending: [ScoutOutcomePick],
        dismissed: [ScoutDismissedPosting]
    ) -> String {
        func pickLine(_ pick: ScoutOutcomePick) -> String {
            let base = "- \(pick.title) — \(pick.company)"
            if let status = pick.statusLabel, !status.isEmpty { return "\(base) (\(status))" }
            return base
        }
        var sections: [String] = []
        if !appliedOrBeyond.isEmpty {
            sections.append(
                "Applied to or advanced — the strongest signal of what fits this candidate:\n"
                + appliedOrBeyond.map(pickLine).joined(separator: "\n")
            )
        }
        if !importedPending.isEmpty {
            sections.append(
                "Imported, not yet acted on — a milder positive:\n"
                + importedPending.map(pickLine).joined(separator: "\n")
            )
        }
        if !dismissed.isEmpty {
            sections.append(
                "Dismissed — do not surface these or close matches again:\n"
                + dismissed.map { entry in
                    let base = "- \(entry.title) — \(entry.company)"
                    guard let reason = entry.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !reason.isEmpty else { return base }
                    return "\(base) — reason: \(reason)"
                }.joined(separator: "\n")
            )
        }
        return sections.joined(separator: "\n\n")
    }

    /// Order recommendations strongest verdict first (strong > promising >
    /// marginal), preserving the agent's original order within each tier
    /// (stable — decorated with the source index so ties never reshuffle).
    static func sortedByVerdict(_ drafts: [JobScoutRecommendationDraft]) -> [JobScoutRecommendationDraft] {
        drafts.enumerated()
            .sorted { lhs, rhs in
                let lRank = lhs.element.match.verdict.sortRank
                let rRank = rhs.element.match.verdict.sortRank
                return lRank == rRank ? lhs.offset < rhs.offset : lRank < rRank
            }
            .map(\.element)
    }

    /// Whether a search result matches a previously-dismissed posting: the
    /// same posting URL, or the same title+company (both non-empty,
    /// case-insensitive). The title+company arm keeps a dismissed posting gone
    /// on boards whose URLs are unstable (ZipRecruiter redirect tokens), where
    /// the same posting can return under a different link.
    static func isDismissed(
        _ result: ScoutSearchResult,
        in dismissed: [ScoutDismissedPosting]
    ) -> Bool {
        guard !dismissed.isEmpty else { return false }
        let resultCompany = result.company ?? ""
        return dismissed.contains { entry in
            if !entry.url.isEmpty, entry.url == result.url {
                return true
            }
            guard !result.title.isEmpty, !resultCompany.isEmpty,
                  !entry.title.isEmpty, !entry.company.isEmpty else {
                return false
            }
            return entry.title.caseInsensitiveCompare(result.title) == .orderedSame
                && entry.company.caseInsensitiveCompare(resultCompany) == .orderedSame
        }
    }

    /// Filter a board's raw results before the agent sees them: drop postings
    /// already returned this run (cross-board seen-URL set), postings the user
    /// dismissed in a past review (cross-run memory — returned as a separate
    /// count), and postings already in the pipeline. Per-board pipeline-match
    /// rules mirror each board's import path:
    ///  - dice: URL match or title+company match
    ///  - zipRecruiter: title+company only (`url` passed nil — redirect
    ///    tokens are unstable, never a dedup key)
    ///  - linkedIn: URL match ONLY (company is unknown at search time, so a
    ///    title+empty-company fallback would false-match unrelated postings)
    static func dedupSearchResults(
        _ results: [ScoutSearchResult],
        board: ScoutBoard,
        seenURLs: inout Set<String>,
        dismissed: [ScoutDismissedPosting],
        pipelineMatch: (_ url: String?, _ title: String, _ company: String) -> PipelineMatchKind?
    ) -> (kept: [ScoutSearchResult], dropped: Int, dismissedDropped: Int) {
        var kept: [ScoutSearchResult] = []
        var dropped = 0
        var dismissedDropped = 0
        for result in results {
            if seenURLs.contains(result.url) {
                dropped += 1
                continue
            }
            seenURLs.insert(result.url)

            // Cross-run memory: a posting the user dismissed in a past review
            // never comes back. Counted apart from pipeline duplicates so the
            // report can tell the user why the list shrank.
            if isDismissed(result, in: dismissed) {
                dismissedDropped += 1
                continue
            }

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
        return (kept, dropped, dismissedDropped)
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
        learnedPreferences: String,
        outcomeContext: String,
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
        let trimmedPreferences = learnedPreferences.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPreferences.isEmpty {
            message += "\n\n## LEARNED PREFERENCES (distilled from your past decisions)\n\(trimmedPreferences)"
        }
        if !outcomeContext.isEmpty {
            message += "\n\n## RECENT SCOUT OUTCOMES\n\(outcomeContext)"
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
    private(set) var previouslyDismissedDropped = 0
    private(set) var notes: [String] = []
    /// Cross-board run-local dedup: every result URL already returned to the
    /// agent this run.
    var seenURLs: Set<String> = []
    /// Snapshot of the user's dismissed postings, captured at run start; the
    /// dedup filter reads it to keep rejected postings out of this run.
    let dismissed: [JobScoutService.ScoutDismissedPosting]

    init(dismissed: [JobScoutService.ScoutDismissedPosting] = []) {
        self.dismissed = dismissed
    }

    func recordSearch(
        board: JobScoutService.ScoutBoard,
        found: Int,
        duplicatesDropped: Int,
        previouslyDismissedDropped: Int = 0
    ) {
        if !boardsSearched.contains(board) {
            boardsSearched.append(board)
        }
        resultsFound += found
        self.duplicatesDropped += duplicatesDropped
        self.previouslyDismissedDropped += previouslyDismissedDropped
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
            previouslyDismissedDropped: previouslyDismissedDropped,
            recommendations: recommendations,
            notes: notes
        )
    }
}
