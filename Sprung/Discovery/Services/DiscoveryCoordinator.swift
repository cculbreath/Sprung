//
//  DiscoveryCoordinator.swift
//  Sprung
//
//  Main coordinator for Discovery module. Composes pipeline and networking
//  sub-coordinators and orchestrates cross-concern operations.
//

import Foundation
import SwiftData

// MARK: - Discovery Status

enum DiscoveryStatus: Equatable {
    case idle
    case starting
    case webSearching(context: String)
    case webSearchComplete
    case complete(added: Int, filtered: Int)
    case error(String)

    var message: String {
        switch self {
        case .idle: return ""
        case .starting: return "Starting discovery..."
        case .webSearching(let context): return "Searching the web for \(context)..."
        case .webSearchComplete: return "Processing search results..."
        case .complete(let added, let filtered):
            if added == 0 && filtered == 0 {
                return "No new events found"
            } else if filtered > 0 {
                return "Added \(added) events (\(filtered) duplicates skipped)"
            } else {
                return "Added \(added) events"
            }
        case .error(let msg): return msg
        }
    }
}

// MARK: - Discovery State (reusable across tabs)

/// Observable state for LLM discovery operations that persists across navigation
@Observable
@MainActor
final class DiscoveryState {
    private(set) var isActive = false
    private(set) var status: DiscoveryStatus = .idle
    private(set) var reasoningText = ""
    private var task: Task<Void, Never>?


    func start(operation: @escaping (@escaping @MainActor (DiscoveryStatus, String?) -> Void) async throws -> Void) {
        guard !isActive else { return }

        task = Task { [weak self] in
            guard let self = self else { return }

            self.isActive = true
            self.reasoningText = ""
            self.status = .starting

            do {
                try await operation { [weak self] status, reasoning in
                    guard let self = self, !Task.isCancelled else { return }
                    self.status = status
                    if let reasoning = reasoning {
                        self.reasoningText += reasoning
                    }
                }
            } catch {
                if !Task.isCancelled {
                    Logger.error("Discovery failed: \(error)", category: .ai)
                    self.status = .error(error.localizedDescription)
                }
            }

            self.isActive = false
            self.status = .idle
            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isActive = false
        status = .idle
        reasoningText = ""
    }
}

@Observable
@MainActor
final class DiscoveryCoordinator {
    // MARK: - Stores

    let preferencesStore: SearchPreferencesStore
    let settingsStore: DiscoverySettingsStore
    let jobAppStore: JobAppStore
    let dailyTaskStore: DailyTaskStore
    let weeklyGoalStore: WeeklyGoalStore
    let eventStore: NetworkingEventStore
    let contactStore: NetworkingContactStore
    let interactionStore: NetworkingInteractionStore

    // MARK: - Services

    private(set) var calendarService: CalendarIntegrationService?

    // MARK: - Discovery State (persists across navigation)

    let eventsDiscovery = DiscoveryState()

    // MARK: - Job Scout

    /// The Job Scout engine (automatic sourcing + triage of new postings).
    /// Constructed with the coordinator's stores; LLM wiring lands in
    /// `configureLLMService`, and AppDependencies injects the LinkedIn MCP
    /// server via `jobScout.setLinkedInServerService`.
    let jobScout: JobScoutService

    // MARK: - Coaching

    private(set) var coachingSessionStore: CoachingSessionStore?
    private(set) var coachingService: CoachingService?
    /// The single daily-task generation path, shared by the coaching session,
    /// the Daily view refresh, and per-category regeneration.
    private(set) var dailyTaskGenerator: DailyTaskGenerator?
    private var coachingAutoStartTimer: Timer?

    // MARK: - Agent Service

    private var agentServiceStore: DiscoveryAgentService?

    // MARK: - Private Dependencies

    private let candidateDossierStore: CandidateDossierStore
    private let knowledgeCardStore: KnowledgeCardStore
    private let skillStore: SkillStore

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        jobAppStore: JobAppStore,
        candidateDossierStore: CandidateDossierStore,
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore
    ) {
        // Pipeline stores
        let preferencesStore = SearchPreferencesStore()
        self.preferencesStore = preferencesStore
        let settingsStore = DiscoverySettingsStore()
        self.settingsStore = settingsStore
        self.jobAppStore = jobAppStore
        self.dailyTaskStore = DailyTaskStore(context: modelContext)
        self.weeklyGoalStore = WeeklyGoalStore(
            context: modelContext,
            jobAppStore: jobAppStore,
            currentPreferences: { preferencesStore.current() }
        )
        self.calendarService = CalendarIntegrationService()
        // Networking stores
        self.eventStore = NetworkingEventStore(context: modelContext)
        self.contactStore = NetworkingContactStore(context: modelContext)
        self.interactionStore = NetworkingInteractionStore(context: modelContext)
        // Private dependencies
        self.candidateDossierStore = candidateDossierStore
        self.knowledgeCardStore = knowledgeCardStore
        self.skillStore = skillStore
        // Job Scout engine
        self.jobScout = JobScoutService(
            jobAppStore: jobAppStore,
            knowledgeCardStore: knowledgeCardStore,
            candidateDossierStore: candidateDossierStore,
            preferencesStore: preferencesStore,
            settingsStore: settingsStore
        )
    }

    /// Configure the Discovery LLM services. Must be called after initialization with LLMFacade.
    func configureLLMService(llmFacade: LLMFacade) {
        // Set up agent service with full context provider
        let contextProvider = DiscoveryContextProviderImpl(coordinator: self)
        let agentService = DiscoveryAgentService(
            llmFacade: llmFacade,
            contextProvider: contextProvider
        )
        self.agentServiceStore = agentService

        // Set up coaching service + the shared daily-task generator
        configureCoachingService(llmFacade: llmFacade, contextProvider: contextProvider)

        // Job Scout gets the same facade (its model resolves per run from
        // the shared Discovery Anthropic setting).
        jobScout.configure(llmFacade: llmFacade)

        // Coordinator startup is the weekly checkpoint for automatic
        // event discovery (the developer runs the app far more often
        // than weekly, so launch-time is a sufficient trigger).
        autoRunWeeklyEventDiscoveryIfNeeded()
        // …and the cadence checkpoint for the Job Scout auto-run.
        autoRunScoutIfNeeded()
    }

    /// Configure the coaching service and the shared daily-task generator
    private func configureCoachingService(
        llmFacade: LLMFacade,
        contextProvider: DiscoveryContextProviderImpl
    ) {
        let modelContext = dailyTaskStore.modelContext

        // Create coaching session store
        let sessionStore = CoachingSessionStore(context: modelContext)
        self.coachingSessionStore = sessionStore

        // Create activity report service
        let activityService = ActivityReportService(
            modelContext: modelContext,
            jobAppStore: jobAppStore,
            eventStore: eventStore,
            contactStore: contactStore,
            interactionStore: interactionStore
        )

        // The single daily-task generation path (coaching completion, Daily
        // view refresh, and per-category regenerate all funnel through it).
        let generator = DailyTaskGenerator(
            llmFacade: llmFacade,
            dailyTaskStore: dailyTaskStore,
            preferencesStore: preferencesStore,
            weeklyGoalStore: weeklyGoalStore,
            sessionStore: sessionStore,
            contextProvider: contextProvider
        )
        self.dailyTaskGenerator = generator

        // Create coaching service
        let coaching = CoachingService(
            modelContext: modelContext,
            llmFacade: llmFacade,
            activityReportService: activityService,
            sessionStore: sessionStore,
            dailyTaskStore: dailyTaskStore,
            preferencesStore: preferencesStore,
            jobAppStore: jobAppStore,
            weeklyGoalStore: weeklyGoalStore,
            candidateDossierStore: candidateDossierStore,
            knowledgeCardStore: knowledgeCardStore,
            taskGenerator: generator
        )

        // Set agent service reference for coaching tool workflows
        coaching.agentService = agentService

        self.coachingService = coaching
        Logger.info("Coaching service configured", category: .ai)
    }

    /// Check and auto-start coaching if discovery is complete and no recent session
    func autoStartCoachingIfNeeded() {
        guard !needsOnboarding else { return }

        // Start hourly timer to check for new sessions (only if discovery complete)
        startCoachingAutoCheckTimer()

        coachingService?.autoStartIfNeeded()
    }

    /// Start a timer to periodically check if new coaching session should start
    private func startCoachingAutoCheckTimer() {
        guard coachingAutoStartTimer == nil else { return }

        // Check every hour if we need to start a new session
        coachingAutoStartTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.needsOnboarding else { return }
                self.coachingService?.autoStartIfNeeded()
            }
        }
    }

    // MARK: - Module State Checks

    var needsOnboarding: Bool {
        !preferencesStore.isConfigured
    }

    // MARK: - Daily Summary (coordinated across sub-coordinators)

    struct DailySummary {
        let eventsToday: [NetworkingEventOpportunity]
        let contactsNeedingAttention: [NetworkingContact]
    }

    func todaysSummary() -> DailySummary {
        DailySummary(
            eventsToday: eventsToday(),
            contactsNeedingAttention: contactsNeedingAttention(limit: 5)
        )
    }

    // MARK: - Weekly Summary (coordinated across sub-coordinators)

    struct WeeklySummary {
        let goal: WeeklyGoal
        let eventsAttended: [NetworkingEventOpportunity]
        let newContacts: [NetworkingContact]
    }

    func thisWeeksSummary() -> WeeklySummary {
        WeeklySummary(
            goal: weeklyGoalStore.currentWeek(),
            eventsAttended: eventsAttendedThisWeek(),
            newContacts: newContactsThisWeek()
        )
    }

    // MARK: - Agent Service Access

    /// The Discovery agent service, available once `configureLLMService` has
    /// run. Exposed for UI flows (e.g. Choose Best) that call agent
    /// operations directly rather than through a coordinator wrapper.
    var agentService: DiscoveryAgentService? {
        agentServiceStore
    }

    /// Surface agent runs (event discovery, job scout, etc.) in the
    /// background-activity UI. Call after `configureLLMService`, which
    /// creates the agent service.
    func setActivityTracker(_ tracker: BackgroundActivityTracker) {
        agentServiceStore?.setActivityTracker(tracker)
        jobScout.setActivityTracker(tracker)
    }

    // MARK: - LLM Agent Operations (delegated to sub-coordinators)

    /// Refresh today's tasks through the shared daily-task generator.
    func generateDailyTasks() async throws {
        guard let generator = dailyTaskGenerator else {
            throw DiscoveryAgentError.toolExecutionFailed("Task generator not configured")
        }
        try await generator.generate(.refresh)
    }

    /// Regenerate one category of today's tasks from user feedback, through
    /// the shared daily-task generator.
    func regenerateDailyTasks(category: TaskCategory, feedback: String) async throws {
        guard let generator = dailyTaskGenerator else {
            throw DiscoveryAgentError.toolExecutionFailed("Task generator not configured")
        }
        try await generator.generate(.categoryFeedback(category: category, feedback: feedback))
    }

    /// Discover networking events using the Anthropic web-search agent loop.
    /// `guidance` is optional one-run operator steering, threaded into the
    /// agent's task message; empty means a plain run.
    func discoverNetworkingEvents(
        daysAhead: Int = 42,
        guidance: String = "",
        streamCallback: (@MainActor @Sendable (DiscoveryStatus, String?) async -> Void)? = nil
    ) async throws {
        guard let agent = agentService else {
            throw DiscoveryAgentError.toolExecutionFailed("Agent service not configured")
        }
        let prefs = preferencesStore.current()
        let candidateContext = buildCandidateContext()
        try await performNetworkingEventDiscovery(
            using: agent,
            sectors: prefs.targetSectors,
            location: prefs.primaryLocation,
            candidateContext: candidateContext,
            guidance: guidance,
            daysAhead: daysAhead,
            streamCallback: streamCallback
        )
    }

    /// Start event discovery with state managed by coordinator (persists across navigation)
    func startEventDiscovery(guidance: String = "") {
        eventsDiscovery.start { [weak self] callback in
            guard let self = self else { return }
            try await self.discoverNetworkingEvents(guidance: guidance) { status, reasoning in
                callback(status, reasoning)
            }
        }
    }

    // MARK: - Weekly Event-Discovery Auto-Run

    /// True when the process hosts the XCTest bundle. Mirrors the private
    /// `SprungApp.isRunningUnitTests` guard: the test suite launches the full
    /// app, so automatic LLM work must never fire under XCTest.
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Kick off a networking-event discovery run when the last successful one
    /// (see `DiscoverySettingsStore.lastSuccessfulEventDiscoveryAt`) is 7+ days
    /// old or has never happened. Gated on `settingsStore.eventDiscoveryAutoRunEnabled`
    /// (default off) — unattended LLM spend must be an explicit opt-in, so a
    /// first launch never fires a surprise run. Non-blocking — `startEventDiscovery`
    /// runs the loop in its own task. Skipped under XCTest, before Discovery
    /// onboarding, while a discovery is already active, and when no Discovery
    /// Anthropic model is configured (an automatic run at launch must not surface
    /// the model picker; a manual run does). When it does fire, it applies the
    /// user's standing guidance (`settingsStore.eventDiscoveryStandingGuidance`)
    /// rather than any per-run guidance, which only applies to manual runs.
    func autoRunWeeklyEventDiscoveryIfNeeded() {
        guard !Self.isRunningUnitTests else { return }
        guard settingsStore.eventDiscoveryAutoRunEnabled else { return }
        guard !needsOnboarding else { return }
        guard !eventsDiscovery.isActive else { return }
        guard (try? ModelConfigResolver.resolve(
            key: DiscoveryAgentService.anthropicModelSettingKey,
            operation: "Event Discovery"
        )) != nil else { return }
        if let last = settingsStore.lastSuccessfulEventDiscoveryAt {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            guard days >= 7 else { return }
        }
        Logger.info(
            "Weekly event-discovery auto-run starting (last success: "
            + "\(settingsStore.lastSuccessfulEventDiscoveryAt.map { "\($0)" } ?? "never"))",
            category: .ai
        )
        let guidance = settingsStore.eventDiscoveryStandingGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
        startEventDiscovery(guidance: guidance)
    }

    /// Cancel ongoing event discovery
    func cancelEventDiscovery() {
        eventsDiscovery.cancel()
    }

    // MARK: - Job-Scout Auto-Run

    /// Kick off a scout run when the configured cadence has elapsed since the
    /// last successful one (see `DiscoverySettingsStore.lastSuccessfulScoutRunAt`;
    /// daily = 1+ day, weekly = 7+ days, never-run counts as elapsed). Gated on
    /// `settingsStore.scoutAutoRunCadence` (default `.off`) — unattended LLM
    /// spend must be an explicit opt-in. Non-blocking — `JobScoutService.start`
    /// runs the loop in its own task. Skipped under XCTest, before Discovery
    /// onboarding (never auto-presents the wizard — the run is silently
    /// skipped until preferences exist), while a scout run is already active,
    /// and when no Discovery Anthropic model is configured (an automatic run
    /// at launch must not surface the model picker; a manual run does). Uses
    /// the persistent settings: enabled boards, target sectors as keywords,
    /// primary location, standing guidance, and the recommendation count.
    /// LinkedIn without accepted consent is dropped inside the service with a
    /// report note — an auto-run never prompts for consent.
    func autoRunScoutIfNeeded() {
        guard !Self.isRunningUnitTests else { return }
        let cadence = settingsStore.scoutAutoRunCadence
        guard cadence != .off else { return }
        guard !needsOnboarding else { return }
        guard (try? ModelConfigResolver.resolve(
            key: DiscoveryAgentService.anthropicModelSettingKey,
            operation: "Job Scout"
        )) != nil else { return }
        guard !jobScout.isActive else { return }
        guard cadence.hasElapsed(since: settingsStore.lastSuccessfulScoutRunAt) else { return }
        Logger.info(
            "Job-scout auto-run starting (\(cadence.rawValue); last success: "
            + "\(settingsStore.lastSuccessfulScoutRunAt.map { "\($0)" } ?? "never"))",
            category: .ai
        )
        let prefs = preferencesStore.current()
        jobScout.start(config: JobScoutService.ScoutRunConfig(
            boards: Set(settingsStore.scoutEnabledBoards),
            keywords: prefs.targetSectors,
            location: prefs.primaryLocation,
            guidance: settingsStore.scoutStandingGuidance.trimmingCharacters(in: .whitespacesAndNewlines),
            recommendationCount: settingsStore.scoutRecommendationCount
        ))
    }

    /// Build a concise candidate context summary from knowledge cards and skills bank
    private func buildCandidateContext() -> String {
        var parts: [String] = []

        // Knowledge cards: titles, organizations, and technologies
        let cards = knowledgeCardStore.approvedCards
        if !cards.isEmpty {
            var dossierLines: [String] = []
            for card in cards {
                var line = "- \(card.title)"
                if let org = card.organization, !org.isEmpty {
                    line += " (\(org))"
                }
                if let dateRange = card.dateRange, !dateRange.isEmpty {
                    line += " [\(dateRange)]"
                }
                dossierLines.append(line)

                let techs = card.technologies
                if !techs.isEmpty {
                    dossierLines.append("  Technologies: \(techs.joined(separator: ", "))")
                }
            }
            parts.append("## CANDIDATE DOSSIER\n\(dossierLines.joined(separator: "\n"))")
        }

        // Skills bank: grouped by category
        let skills = skillStore.approvedSkills
        if !skills.isEmpty {
            let grouped = Dictionary(grouping: skills, by: { $0.category })
            var skillLines: [String] = []
            for (category, categorySkills) in grouped.sorted(by: { $0.key < $1.key }) {
                let names = categorySkills.map { $0.canonical }.joined(separator: ", ")
                skillLines.append("- \(category): \(names)")
            }
            parts.append("## SKILLS BANK\n\(skillLines.joined(separator: "\n"))")
        }

        return parts.joined(separator: "\n\n")
    }

    /// Generate full event preparation (goal, pitch, talking points, target companies,
    /// conversation starters, things to avoid) using LLM agent and persist it on the event.
    func prepareEvent(_ event: NetworkingEventOpportunity) async throws {
        guard let agent = agentService else {
            throw DiscoveryAgentError.toolExecutionFailed("Agent service not configured")
        }
        try await performEventPrep(for: event, using: agent)
    }

    /// Generate debrief outcomes and suggested next steps using LLM agent
    func generateDebriefOutcomes(
        event: NetworkingEventOpportunity,
        keyInsights: String,
        contactsMade: [String],
        notes: String
    ) async throws -> DebriefOutcomesResult {
        guard let agent = agentService else {
            throw DiscoveryAgentError.toolExecutionFailed("Agent service not configured")
        }
        return try await agent.generateDebriefOutcomes(
            eventName: event.name,
            eventType: event.eventType.rawValue,
            keyInsights: keyInsights,
            contactsMade: contactsMade,
            notes: notes
        )
    }

    /// Generate weekly reflection using LLM agent
    func generateWeeklyReflection() async throws {
        guard let agent = agentService else {
            throw DiscoveryAgentError.toolExecutionFailed("Agent service not configured")
        }
        let reflection = try await agent.generateWeeklyReflection(
            previousWeekNotes: weeklyGoalStore.previousWeekUserNotes()
        )
        weeklyGoalStore.setReflection(reflection)
        Logger.info("✅ Generated weekly reflection", category: .ai)
    }

    // MARK: - Merged Sub-Coordinator Operations

    /// Discover networking events using the Anthropic web-search agent loop
    /// and persist new ones. The agent receives the currently known events so
    /// it never resubmits them; whatever slips through is still deduped by URL.
    private func performNetworkingEventDiscovery(
        using agentService: DiscoveryAgentService,
        sectors: [String],
        location: String,
        candidateContext: String = "",
        guidance: String = "",
        daysAhead: Int = 42,
        streamCallback: (@MainActor @Sendable (DiscoveryStatus, String?) async -> Void)? = nil
    ) async throws {
        let discovered = try await agentService.discoverNetworkingEvents(
            sectors: sectors,
            location: location,
            candidateContext: candidateContext,
            knownEventsContext: knownEventsContext(),
            attendedHistoryContext: DiscoveryAgentService.attendedHistoryContext(attendedEventHistory()),
            operatorGuidance: guidance,
            daysAhead: daysAhead,
            statusCallback: { status in
                await streamCallback?(status, nil)
            },
            reasoningCallback: { text in
                await streamCallback?(.webSearching(context: "networking events"), text)
            }
        )

        // Filter duplicates and add new events
        let newEvents = eventStore.filterNew(
            discovered.compactMap { $0.toNetworkingEventOpportunity() }
        )

        eventStore.addMultiple(newEvents)

        // Only a run that got this far counts for the weekly auto-run clock —
        // a thrown (failed/cancelled) run never reaches this line.
        settingsStore.recordSuccessfulEventDiscovery()

        await streamCallback?(.complete(added: newEvents.count, filtered: discovered.count - newEvents.count), nil)

        Logger.info("✅ Discovered \(newEvents.count) new events", category: .ai)
    }

    /// Current and future events already in the store, formatted for the
    /// discovery agent's "do not resubmit" context.
    private func knownEventsContext() -> String {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let known = eventStore.allEvents.filter { $0.date >= startOfToday }
        guard !known.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return known
            .map { "- \($0.name) — \(formatter.string(from: $0.date))" }
            .joined(separator: "\n")
    }

    /// Attended/debriefed events, most recent first, as taste-signal records
    /// for the discovery agent (capped and formatted by
    /// `DiscoveryAgentService.attendedHistoryContext`).
    private func attendedEventHistory() -> [AttendedEventRecord] {
        eventStore.allEvents
            .filter { $0.status == .attended || $0.status == .debriefed }
            .sorted { ($0.attendedAt ?? $0.date) > ($1.attendedAt ?? $1.date) }
            .map {
                AttendedEventRecord(
                    name: $0.name,
                    eventType: $0.eventType.rawValue,
                    organizer: $0.organizer,
                    rating: $0.eventRating?.rawValue
                )
            }
    }

    /// Run event preparation via the LLM agent and persist the full result —
    /// goal, pitch script, talking points, target companies, conversation
    /// starters, and things to avoid — on the event.
    private func performEventPrep(for event: NetworkingEventOpportunity, using agentService: DiscoveryAgentService) async throws {
        let result = try await agentService.prepareForEvent(
            eventId: event.id,
            focusCompanies: [],
            goals: nil
        )
        event.goal = result.goal
        event.pitchScript = result.pitchScript
        event.talkingPoints = result.talkingPoints.map { $0.toTalkingPoint() }
        event.targetCompanies = result.targetCompanies.map { $0.toTargetCompanyContext() }
        event.conversationStarters = result.conversationStarters
        event.thingsToAvoid = result.thingsToAvoid
        eventStore.update(event)
    }

    // MARK: - Summary Data Helpers (merged from networking sub-coordinator)

    private func eventsToday() -> [NetworkingEventOpportunity] {
        let calendar = Calendar.current
        return eventStore.upcomingEvents.filter {
            calendar.isDateInToday($0.date)
        }
    }

    private func contactsNeedingAttention(limit: Int = 5) -> [NetworkingContact] {
        Array(contactStore.needsAttention.prefix(limit))
    }

    private func eventsAttendedThisWeek() -> [NetworkingEventOpportunity] {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        return eventStore.attendedEvents.filter { event in
            guard let attendedAt = event.attendedAt else { return false }
            return attendedAt >= weekStart
        }
    }

    private func newContactsThisWeek() -> [NetworkingContact] {
        contactStore.thisWeeksNewContacts
    }

    // MARK: - Role Suggestion (Onboarding)

    /// Generate target role suggestions based on user's dossier (knowledge cards).
    /// Runs on the Discovery Anthropic model via DiscoveryAgentService.
    /// - Parameters:
    ///   - dossierSummary: Summary of user's background from ResRefs
    ///   - existingRoles: Any roles the user has already selected/added
    ///   - keywords: Optional keywords/topics the user wants to explore (e.g., "AI, healthcare, startups")
    /// - Returns: List of suggested role titles
    func suggestTargetRoles(
        dossierSummary: String,
        existingRoles: [String] = [],
        keywords: String? = nil
    ) async throws -> [String] {
        guard let agent = agentService else {
            throw DiscoveryAgentError.toolExecutionFailed("Agent service not configured")
        }
        return try await agent.suggestTargetRoles(
            dossierSummary: dossierSummary,
            existingRoles: existingRoles,
            keywords: keywords
        )
    }

    // MARK: - Location Preference Extraction (Onboarding)

    /// Extract location and work arrangement preferences from profile and dossier.
    /// Runs on the Discovery Anthropic model via DiscoveryAgentService.
    func extractLocationPreferences(
        profileInfo: String,
        dossierSummary: String
    ) async throws -> ExtractedLocationPreferences {
        guard let agent = agentService else {
            throw DiscoveryAgentError.toolExecutionFailed("Agent service not configured")
        }
        return try await agent.extractLocationPreferences(
            profileInfo: profileInfo,
            dossierSummary: dossierSummary
        )
    }
}
