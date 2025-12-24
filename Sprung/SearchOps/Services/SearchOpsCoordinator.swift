//
//  SearchOpsCoordinator.swift
//  Sprung
//
//  Main coordinator for SearchOps module. Composes pipeline and networking
//  sub-coordinators and orchestrates cross-concern operations.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class SearchOpsCoordinator {
    // MARK: - Sub-Coordinators

    let pipelineCoordinator: SearchOpsPipelineCoordinator
    let networkingCoordinator: SearchOpsNetworkingCoordinator

    // MARK: - Convenience Store Access (delegated to sub-coordinators)

    var preferencesStore: SearchPreferencesStore { pipelineCoordinator.preferencesStore }
    var settingsStore: SearchOpsSettingsStore { pipelineCoordinator.settingsStore }
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

    var urlValidationService: URLValidationService { networkingCoordinator.urlValidationService }
    var llmService: SearchOpsLLMService? { pipelineCoordinator.llmService }
    var calendarService: CalendarIntegrationService? { pipelineCoordinator.calendarService }

    // MARK: - State

    private(set) var isInitialized: Bool = false
    var currentTimeEntry: TimeEntry? { pipelineCoordinator.currentTimeEntry }

    // MARK: - Initialization

    init(modelContext: ModelContext, jobAppStore: JobAppStore) {
        self.pipelineCoordinator = SearchOpsPipelineCoordinator(modelContext: modelContext, jobAppStore: jobAppStore)
        self.networkingCoordinator = SearchOpsNetworkingCoordinator(modelContext: modelContext)
    }

    /// Configure the LLM service. Must be called after initialization with LLMFacade.
    func configureLLMService(llmFacade: LLMFacade) {
        pipelineCoordinator.configureLLMService(llmFacade: llmFacade)

        // Set up agent service with full context provider
        if let llmService = pipelineCoordinator.llmService {
            let contextProvider = SearchOpsContextProviderImpl(coordinator: self)
            let agentService = SearchOpsAgentService(
                llmFacade: llmService.llmFacade,
                contextProvider: contextProvider,
                settingsStore: settingsStore
            )
            pipelineCoordinator.setAgentService(agentService)
        }
    }

    func initialize() {
        guard !isInitialized else { return }

        pipelineCoordinator.initialize()
        networkingCoordinator.initialize()

        isInitialized = true
        Logger.info("✅ SearchOps initialized", category: .appLifecycle)
    }

    // MARK: - Module State Checks

    var needsOnboarding: Bool {
        pipelineCoordinator.needsOnboarding
    }

    var hasActiveSources: Bool {
        networkingCoordinator.hasActiveSources
    }

    // MARK: - Time Tracking (delegated to pipeline coordinator)

    func startTimeTracking(activity: ActivityType) {
        pipelineCoordinator.startTimeTracking(activity: activity)
    }

    func endTimeTracking() {
        pipelineCoordinator.endTimeTracking()
    }

    func switchTimeTracking(to activity: ActivityType) {
        pipelineCoordinator.switchTimeTracking(to: activity)
    }

    // MARK: - Source Operations (delegated to networking coordinator)

    func visitSource(_ source: JobSource) {
        networkingCoordinator.visitSource(source)
    }

    // MARK: - Source Validation (delegated to networking coordinator)

    func validateSources() async {
        await networkingCoordinator.validateSources()
    }

    // MARK: - Daily Summary (coordinated across sub-coordinators)

    struct DailySummary {
        let tasksTotal: Int
        let tasksCompleted: Int
        let timeSpentMinutes: Int
        let sourcesVisited: Int
        let applicationsSubmitted: Int
        let followUpsSent: Int
        let eventsToday: [NetworkingEventOpportunity]
        let contactsNeedingAttention: [NetworkingContact]
    }

    func todaysSummary() -> DailySummary {
        let eventsToday = networkingCoordinator.eventsToday()
        let contactsNeedingAttention = networkingCoordinator.contactsNeedingAttention(limit: 5)

        return pipelineCoordinator.todaysSummary(
            eventsToday: eventsToday,
            contactsNeedingAttention: contactsNeedingAttention
        )
    }

    // MARK: - Weekly Summary (coordinated across sub-coordinators)

    struct WeeklySummary {
        let goal: WeeklyGoal
        let applicationProgress: Double
        let networkingProgress: Double
        let timeProgress: Double
        let topSources: [JobSource]
        let eventsAttended: [NetworkingEventOpportunity]
        let newContacts: [NetworkingContact]
        let reflectionNeeded: Bool
    }

    func thisWeeksSummary() -> WeeklySummary {
        let topSources = jobSourceStore.topSourcesByEffectiveness(limit: 3)
        let eventsAttended = networkingCoordinator.eventsAttendedThisWeek()
        let newContacts = networkingCoordinator.newContactsThisWeek()

        return pipelineCoordinator.thisWeeksSummary(
            topSources: topSources,
            eventsAttended: eventsAttended,
            newContacts: newContacts
        )
    }

    // MARK: - Event Workflow Helpers (delegated to networking coordinator)

    func recordEventAttendance(_ event: NetworkingEventOpportunity) {
        networkingCoordinator.recordEventAttendance(event, weeklyGoalStore: weeklyGoalStore)
    }

    func recordEventDebrief(
        _ event: NetworkingEventOpportunity,
        contacts: [NetworkingContact],
        rating: EventRating,
        wouldRecommend: Bool,
        whatWorked: String?,
        whatDidntWork: String?
    ) {
        networkingCoordinator.recordEventDebrief(
            event,
            contacts: contacts,
            rating: rating,
            wouldRecommend: wouldRecommend,
            whatWorked: whatWorked,
            whatDidntWork: whatDidntWork,
            weeklyGoalStore: weeklyGoalStore
        )
    }

    // MARK: - Agent Service Access

    private var agentService: SearchOpsAgentService? {
        pipelineCoordinator.getOrCreateAgentService()
    }

    // MARK: - LLM Agent Operations (delegated to sub-coordinators)

    /// Generate today's tasks using LLM agent
    func generateDailyTasks(focusArea: String = "balanced") async throws {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }
        try await pipelineCoordinator.generateDailyTasks(using: agent, focusArea: focusArea)
    }

    /// Discover new job sources using LLM agent
    func discoverJobSources() async throws {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }
        let prefs = preferencesStore.current()
        try await networkingCoordinator.discoverJobSources(
            using: agent,
            sectors: prefs.targetSectors,
            location: prefs.primaryLocation
        )
    }

    /// Discover networking events using LLM agent
    func discoverNetworkingEvents(daysAhead: Int = 14) async throws {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }
        let prefs = preferencesStore.current()
        try await networkingCoordinator.discoverNetworkingEvents(
            using: agent,
            sectors: prefs.targetSectors,
            location: prefs.primaryLocation,
            daysAhead: daysAhead
        )
    }

    /// Evaluate an event for attendance using LLM agent
    func evaluateEvent(_ event: NetworkingEventOpportunity) async throws -> EventEvaluationResult {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }
        return try await networkingCoordinator.evaluateEvent(event, using: agent)
    }

    /// Generate an elevator pitch for an event using LLM agent
    func generateEventPitch(for event: NetworkingEventOpportunity) async throws -> String? {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }
        return try await networkingCoordinator.generateEventPitch(for: event, using: agent)
    }

    /// Prepare for an event using LLM agent
    func prepareForEvent(_ event: NetworkingEventOpportunity, focusCompanies: [String] = [], goals: String? = nil) async throws -> EventPrepResult {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }
        return try await networkingCoordinator.prepareForEvent(
            event,
            focusCompanies: focusCompanies,
            goals: goals,
            using: agent
        )
    }

    /// Generate weekly reflection using LLM agent
    func generateWeeklyReflection() async throws {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }
        try await pipelineCoordinator.generateWeeklyReflection(using: agent)
    }

    /// Suggest networking actions using LLM agent
    func suggestNetworkingActions(focus: String = "balanced") async throws -> NetworkingActionsResult {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }
        return try await networkingCoordinator.suggestNetworkingActions(focus: focus, using: agent)
    }

    /// Draft an outreach message using LLM agent
    func draftOutreachMessage(
        contact: NetworkingContact,
        purpose: String,
        channel: String,
        tone: String = "professional"
    ) async throws -> OutreachMessageResult {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }
        return try await networkingCoordinator.draftOutreachMessage(
            contact: contact,
            purpose: purpose,
            channel: channel,
            tone: tone,
            using: agent
        )
    }

    /// Run a conversational agent with custom prompt
    func runAgent(systemPrompt: String, userMessage: String) async throws -> String {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }
        return try await pipelineCoordinator.runAgent(
            using: agent,
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )
    }

    // MARK: - Contact Workflow Helpers (delegated to networking coordinator)

    func recordContactInteraction(
        _ contact: NetworkingContact,
        type: InteractionType,
        notes: String = "",
        outcome: InteractionOutcome? = nil,
        followUpNeeded: Bool = false,
        followUpAction: String? = nil,
        followUpDate: Date? = nil
    ) {
        networkingCoordinator.recordContactInteraction(
            contact,
            type: type,
            notes: notes,
            outcome: outcome,
            followUpNeeded: followUpNeeded,
            followUpAction: followUpAction,
            followUpDate: followUpDate,
            weeklyGoalStore: weeklyGoalStore
        )
    }
}
