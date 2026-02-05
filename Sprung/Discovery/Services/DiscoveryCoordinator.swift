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
    case webSearching(context: String = "job sources")
    case webSearchComplete
    case validatingURLs(count: Int)
    case complete(added: Int, filtered: Int)
    case error(String)

    var message: String {
        switch self {
        case .idle: return ""
        case .starting: return "Starting discovery..."
        case .webSearching(let context): return "Searching the web for \(context)..."
        case .webSearchComplete: return "Processing search results..."
        case .validatingURLs(let count): return "Validating \(count) URLs..."
        case .complete(let added, let filtered):
            if added == 0 && filtered == 0 {
                return "No new sources found"
            } else if filtered > 0 {
                return "Added \(added) sources (\(filtered) invalid filtered)"
            } else {
                return "Added \(added) sources"
            }
        case .error(let msg): return msg
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .complete, .error: return false
        default: return true
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
    // MARK: - Sub-Coordinators

    let pipelineCoordinator: DiscoveryPipelineCoordinator
    let networkingCoordinator: DiscoveryNetworkingCoordinator

    // MARK: - Discovery Status

    private(set) var discoveryStatus: DiscoveryStatus = .idle

    // MARK: - Discovery State (persists across navigation)

    let sourcesDiscovery = DiscoveryState()
    let eventsDiscovery = DiscoveryState()

    // MARK: - Coaching

    private(set) var coachingSessionStore: CoachingSessionStore?
    private(set) var coachingService: CoachingService?
    private var coachingAutoStartTimer: Timer?

    // MARK: - Convenience Store Access (delegated to sub-coordinators)

    var preferencesStore: SearchPreferencesStore { pipelineCoordinator.preferencesStore }
    var settingsStore: DiscoverySettingsStore { pipelineCoordinator.settingsStore }
    var jobSourceStore: JobSourceStore { networkingCoordinator.jobSourceStore }
    var jobAppStore: JobAppStore { pipelineCoordinator.jobAppStore }
    var dailyTaskStore: DailyTaskStore { pipelineCoordinator.dailyTaskStore }
    var timeEntryStore: TimeEntryStore { pipelineCoordinator.timeEntryStore }
    var weeklyGoalStore: WeeklyGoalStore { pipelineCoordinator.weeklyGoalStore }
    var eventStore: NetworkingEventStore { networkingCoordinator.eventStore }
    var contactStore: NetworkingContactStore { networkingCoordinator.contactStore }
    var interactionStore: NetworkingInteractionStore { networkingCoordinator.interactionStore }
    var feedbackStore: EventFeedbackStore { networkingCoordinator.feedbackStore }

    // MARK: - Convenience Service Access (delegated to sub-coordinators)

    var llmService: DiscoveryLLMService? { pipelineCoordinator.llmService }
    var calendarService: CalendarIntegrationService? { pipelineCoordinator.calendarService }

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
        self.pipelineCoordinator = DiscoveryPipelineCoordinator(modelContext: modelContext, jobAppStore: jobAppStore)
        self.networkingCoordinator = DiscoveryNetworkingCoordinator(modelContext: modelContext)
        self.candidateDossierStore = candidateDossierStore
        self.knowledgeCardStore = knowledgeCardStore
        self.skillStore = skillStore
    }

    /// Configure the LLM service. Must be called after initialization with LLMFacade.
    func configureLLMService(llmFacade: LLMFacade) {
        pipelineCoordinator.configureLLMService(llmFacade: llmFacade)

        // Set up agent service with full context provider
        if let llmService = pipelineCoordinator.llmService {
            let contextProvider = DiscoveryContextProviderImpl(coordinator: self)
            let agentService = DiscoveryAgentService(
                llmFacade: llmService.llmFacade,
                contextProvider: contextProvider,
                settingsStore: settingsStore
            )
            pipelineCoordinator.setAgentService(agentService)

            // Set up coaching service
            configureCoachingService(llmService: llmService)
        }
    }

    /// Configure the coaching service
    private func configureCoachingService(llmService: DiscoveryLLMService) {
        // Get model context and daily task store from pipeline coordinator
        let dailyTaskStore = pipelineCoordinator.dailyTaskStore
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
            interactionStore: interactionStore,
            timeEntryStore: timeEntryStore
        )

        // Create coaching service
        let coaching = CoachingService(
            modelContext: modelContext,
            llmService: llmService,
            activityReportService: activityService,
            sessionStore: sessionStore,
            dailyTaskStore: dailyTaskStore,
            preferencesStore: preferencesStore,
            jobAppStore: jobAppStore,
            candidateDossierStore: candidateDossierStore,
            knowledgeCardStore: knowledgeCardStore
        )

        // Set agent service reference for workflows like chooseBestJobs
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
        pipelineCoordinator.needsOnboarding
    }

    // MARK: - Daily Summary (coordinated across sub-coordinators)

    struct DailySummary {
        let eventsToday: [NetworkingEventOpportunity]
        let contactsNeedingAttention: [NetworkingContact]
    }

    func todaysSummary() -> DailySummary {
        DailySummary(
            eventsToday: networkingCoordinator.eventsToday(),
            contactsNeedingAttention: networkingCoordinator.contactsNeedingAttention(limit: 5)
        )
    }

    // MARK: - Weekly Summary (coordinated across sub-coordinators)

    struct WeeklySummary {
        let goal: WeeklyGoal
        let topSources: [JobSource]
        let eventsAttended: [NetworkingEventOpportunity]
        let newContacts: [NetworkingContact]
    }

    func thisWeeksSummary() -> WeeklySummary {
        WeeklySummary(
            goal: weeklyGoalStore.currentWeek(),
            topSources: jobSourceStore.topSourcesByEffectiveness(limit: 3),
            eventsAttended: networkingCoordinator.eventsAttendedThisWeek(),
            newContacts: networkingCoordinator.newContactsThisWeek()
        )
    }

    // MARK: - Agent Service Access

    private var agentService: DiscoveryAgentService? {
        pipelineCoordinator.getOrCreateAgentService()
    }

    // MARK: - LLM Agent Operations (delegated to sub-coordinators)

    /// Generate today's tasks using LLM agent
    func generateDailyTasks(focusArea: String = "balanced") async throws {
        guard let agent = agentService else {
            throw DiscoveryLLMError.toolExecutionFailed("Agent service not configured")
        }
        try await pipelineCoordinator.generateDailyTasks(using: agent, focusArea: focusArea)
    }

    /// Discover new job sources using LLM agent
    func discoverJobSources() async throws {
        guard let agent = agentService else {
            throw DiscoveryLLMError.toolExecutionFailed("Agent service not configured")
        }

        discoveryStatus = .starting

        do {
            let prefs = preferencesStore.current()
            let candidateContext = buildCandidateContext()
            try await networkingCoordinator.discoverJobSources(
                using: agent,
                sectors: prefs.targetSectors,
                location: prefs.primaryLocation,
                candidateContext: candidateContext,
                statusCallback: { @MainActor [weak self] status in
                    self?.discoveryStatus = status
                }
            )
        } catch {
            discoveryStatus = .error(error.localizedDescription)
            throw error
        }
    }

    /// Discover networking events using LLM agent
    func discoverNetworkingEvents(
        daysAhead: Int = 14,
        streamCallback: (@MainActor @Sendable (DiscoveryStatus, String?) async -> Void)? = nil
    ) async throws {
        guard let agent = agentService else {
            throw DiscoveryLLMError.toolExecutionFailed("Agent service not configured")
        }
        let prefs = preferencesStore.current()
        try await networkingCoordinator.discoverNetworkingEvents(
            using: agent,
            sectors: prefs.targetSectors,
            location: prefs.primaryLocation,
            daysAhead: daysAhead,
            streamCallback: streamCallback
        )
    }

    /// Start event discovery with state managed by coordinator (persists across navigation)
    func startEventDiscovery() {
        eventsDiscovery.start { [weak self] callback in
            guard let self = self else { return }
            try await self.discoverNetworkingEvents { status, reasoning in
                callback(status, reasoning)
            }
        }
    }

    /// Cancel ongoing event discovery
    func cancelEventDiscovery() {
        eventsDiscovery.cancel()
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

    /// Start sources discovery with state managed by coordinator (persists across navigation)
    func startSourcesDiscovery() {
        sourcesDiscovery.start { [weak self] callback in
            guard let self = self else { return }
            guard let agent = self.agentService else {
                throw DiscoveryLLMError.toolExecutionFailed("Agent service not configured")
            }

            let prefs = self.preferencesStore.current()
            let candidateContext = self.buildCandidateContext()
            try await self.networkingCoordinator.discoverJobSources(
                using: agent,
                sectors: prefs.targetSectors,
                location: prefs.primaryLocation,
                candidateContext: candidateContext,
                statusCallback: { status in
                    callback(status, nil)
                }
            )
        }
    }

    /// Cancel ongoing sources discovery
    func cancelSourcesDiscovery() {
        sourcesDiscovery.cancel()
    }

    /// Choose best jobs from identified pool using LLM agent
    /// - Parameters:
    ///   - knowledgeContext: User's knowledge cards as text
    ///   - dossierContext: User's dossier entries as text
    ///   - count: Number of jobs to select (default 5)
    /// - Returns: Selection result with reasoning, and advances selected jobs to researching
    // TODO: Context source choice - may revisit (currently using knowledge cards + dossier)
    func chooseBestJobs(
        knowledgeContext: String,
        dossierContext: String,
        count: Int = 5
    ) async throws -> JobSelectionsResult {
        guard let agent = agentService else {
            throw DiscoveryLLMError.toolExecutionFailed("Agent service not configured")
        }

        // Get all jobs in new (identified) status
        let identifiedJobs = jobAppStore.jobApps(forStatus: .new)
        guard !identifiedJobs.isEmpty else {
            throw DiscoveryLLMError.toolExecutionFailed("No jobs in Identified status to choose from")
        }

        // Build job tuples for agent
        let jobTuples = identifiedJobs.map { job in
            (
                id: job.id,
                company: job.companyName,
                role: job.jobPosition,
                description: job.jobDescription
            )
        }

        Logger.info("🎯 Choosing best \(count) jobs from \(identifiedJobs.count) identified", category: .ai)

        // Call agent to select best jobs
        let result = try await agent.chooseBestJobs(
            jobs: jobTuples,
            knowledgeContext: knowledgeContext,
            dossierContext: dossierContext,
            count: count
        )

        // Advance selected jobs to queued status
        for selection in result.selections {
            if let job = identifiedJobs.first(where: { $0.id == selection.jobId }) {
                jobAppStore.setStatus(job, to: .queued)
                Logger.info("📋 Advanced '\(job.jobPosition)' at \(job.companyName) to Queued", category: .ai)
            }
        }

        Logger.info("✅ Selected \(result.selections.count) jobs for application", category: .ai)
        return result
    }

    /// Generate an elevator pitch for an event using LLM agent
    func generateEventPitch(for event: NetworkingEventOpportunity) async throws -> String? {
        guard let agent = agentService else {
            throw DiscoveryLLMError.toolExecutionFailed("Agent service not configured")
        }
        return try await networkingCoordinator.generateEventPitch(for: event, using: agent)
    }

    /// Generate debrief outcomes and suggested next steps using LLM agent
    func generateDebriefOutcomes(
        event: NetworkingEventOpportunity,
        keyInsights: String,
        contactsMade: [String],
        notes: String
    ) async throws -> DebriefOutcomesResult {
        guard let agent = agentService else {
            throw DiscoveryLLMError.toolExecutionFailed("Agent service not configured")
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
            throw DiscoveryLLMError.toolExecutionFailed("Agent service not configured")
        }
        try await pipelineCoordinator.generateWeeklyReflection(using: agent)
    }

    // MARK: - Role Suggestion (Onboarding)

    /// Response structure for role suggestions
    struct RoleSuggestionsResult: Codable {
        let suggestedRoles: [String]
        let reasoning: String?
    }

    /// Generate target role suggestions based on user's dossier (knowledge cards)
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
        guard let llm = llmService else {
            throw DiscoveryLLMError.toolExecutionFailed("LLM service not configured")
        }

        let existingContext = existingRoles.isEmpty
            ? ""
            : "\n\nThe user has already indicated interest in: \(existingRoles.joined(separator: ", ")). Suggest additional complementary roles they might not have considered."

        let keywordsContext: String
        if let keywords = keywords, !keywords.isEmpty {
            keywordsContext = "\n\nKEYWORDS TO EXPLORE:\nThe user is particularly interested in roles related to: \(keywords). Prioritize suggestions that connect their background to these areas, industries, or themes."
        } else {
            keywordsContext = ""
        }

        let prompt = """
            Based on the following professional background, suggest 5-8 specific job roles/titles this person should target in their job search.

            BACKGROUND:
            \(dossierSummary)
            \(existingContext)\(keywordsContext)

            Return a JSON object with:
            - suggestedRoles: array of specific job title strings (e.g., "Senior Software Engineer", "Engineering Manager", "Staff Developer")
            - reasoning: brief explanation of why these roles fit (optional)

            Focus on:
            1. Roles that match their experience level
            2. Both obvious fits and adjacent opportunities they might not have considered
            3. Specific titles, not broad categories
            \(keywords != nil ? "4. Roles that connect to the specified keywords/interests" : "")
            """

        // Build JSON schema for OpenAI structured output
        // Note: OpenAI requires ALL properties in 'required' - use nullable types for optional fields
        let schema = JSONSchema(
            type: .object,
            properties: [
                "suggestedRoles": JSONSchema(
                    type: .array,
                    description: "List of specific job titles to target",
                    items: JSONSchema(type: .string)
                ),
                "reasoning": JSONSchema(
                    type: .optional(.string),
                    description: "Brief explanation of why these roles fit"
                )
            ],
            required: ["suggestedRoles", "reasoning"],
            additionalProperties: false
        )

        // Use discovery model via OpenAI backend
        let result = try await llm.executeStructured(
            prompt: prompt,
            systemPrompt: "You are a career advisor helping someone identify job roles to target. Be specific with job titles.",
            as: RoleSuggestionsResult.self,
            temperature: 0.7,
            backend: .openAI,
            schema: schema,
            schemaName: "role_suggestions"
        )

        return result.suggestedRoles
    }

    // MARK: - Location Preference Extraction (Onboarding)

    /// Response structure for location preferences extraction
    struct LocationPreferencesResult: Codable {
        let location: String?
        let workArrangement: String?
        let remoteAcceptable: Bool?
        let companySize: String?
    }

    /// Extracted location preferences with parsed enums
    struct ExtractedLocationPreferences {
        let location: String?
        let workArrangement: WorkArrangement?
        let remoteAcceptable: Bool?
        let companySize: CompanySizePreference?
    }

    /// Extract location and work arrangement preferences from profile and dossier
    func extractLocationPreferences(
        profileInfo: String,
        dossierSummary: String
    ) async throws -> ExtractedLocationPreferences {
        guard let llm = llmService else {
            throw DiscoveryLLMError.toolExecutionFailed("LLM service not configured")
        }

        let prompt = """
            Extract job search preferences from the following sources.

            APPLICANT PROFILE:
            \(profileInfo)

            BACKGROUND/DOSSIER:
            \(dossierSummary)

            Infer from context clues like mentions of relocating, working from home, commuting preferences, company culture preferences, etc.
            """

        // Build JSON schema for strict structured output
        // Use .optional() to allow null values for fields that can't be determined
        let schema = JSONSchema(
            type: .object,
            properties: [
                "location": JSONSchema(
                    type: .optional(.string),
                    description: "Primary job search location (e.g., 'San Francisco Bay Area', 'Austin, TX'). Null if not determinable."
                ),
                "workArrangement": JSONSchema(
                    type: .optional(.string),
                    description: "Work arrangement preference: remote, hybrid, or onsite",
                    enum: ["remote", "hybrid", "onsite"]
                ),
                "remoteAcceptable": JSONSchema(
                    type: .optional(.boolean),
                    description: "True if open to remote work, false if prefers in-person"
                ),
                "companySize": JSONSchema(
                    type: .optional(.string),
                    description: "Preferred company size",
                    enum: ["startup", "small", "mid", "enterprise", "any"]
                )
            ],
            required: ["location", "workArrangement", "remoteAcceptable", "companySize"],
            additionalProperties: false
        )

        // Use discovery model via OpenAI backend
        let result = try await llm.executeFlexibleJSON(
            prompt: prompt,
            systemPrompt: "Extract job search preferences from the provided profile and background. Return null for fields that cannot be determined.",
            as: LocationPreferencesResult.self,
            jsonSchema: schema,
            temperature: 0.3,
            backend: .openAI,
            schemaName: "location_preferences"
        )

        // Parse work arrangement string to enum
        let arrangement: WorkArrangement?
        if let arrangementStr = result.workArrangement?.lowercased() {
            switch arrangementStr {
            case "remote": arrangement = .remote
            case "hybrid": arrangement = .hybrid
            case "onsite", "on-site", "in-office": arrangement = .onsite
            default: arrangement = nil
            }
        } else {
            arrangement = nil
        }

        // Parse company size string to enum
        let companySize: CompanySizePreference?
        if let sizeStr = result.companySize?.lowercased() {
            switch sizeStr {
            case "startup": companySize = .startup
            case "small": companySize = .small
            case "mid", "mid-size", "midsize": companySize = .mid
            case "enterprise", "large": companySize = .enterprise
            case "any": companySize = .any
            default: companySize = nil
            }
        } else {
            companySize = nil
        }

        return ExtractedLocationPreferences(
            location: result.location,
            workArrangement: arrangement,
            remoteAcceptable: result.remoteAcceptable,
            companySize: companySize
        )
    }
}
