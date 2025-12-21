//
//  SearchOpsCoordinator.swift
//  Sprung
//
//  Main coordinator for SearchOps module. Provides unified access to all stores
//  and orchestrates cross-store operations.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class SearchOpsCoordinator {
    // MARK: - Stores

    let preferencesStore: SearchPreferencesStore
    let settingsStore: SearchOpsSettingsStore
    let jobSourceStore: JobSourceStore
    let dailyTaskStore: DailyTaskStore
    let timeEntryStore: TimeEntryStore
    let weeklyGoalStore: WeeklyGoalStore
    let eventStore: NetworkingEventStore
    let contactStore: NetworkingContactStore
    let interactionStore: NetworkingInteractionStore
    let feedbackStore: EventFeedbackStore

    // MARK: - Services

    let urlValidationService: URLValidationService
    private(set) var llmService: SearchOpsLLMService?

    // MARK: - State

    private(set) var isInitialized: Bool = false
    private(set) var currentTimeEntry: TimeEntry?

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.preferencesStore = SearchPreferencesStore(context: modelContext)
        self.settingsStore = SearchOpsSettingsStore(context: modelContext)
        self.jobSourceStore = JobSourceStore(context: modelContext)
        self.dailyTaskStore = DailyTaskStore(context: modelContext)
        self.timeEntryStore = TimeEntryStore(context: modelContext)
        self.weeklyGoalStore = WeeklyGoalStore(context: modelContext)
        self.eventStore = NetworkingEventStore(context: modelContext)
        self.contactStore = NetworkingContactStore(context: modelContext)
        self.interactionStore = NetworkingInteractionStore(context: modelContext)
        self.feedbackStore = EventFeedbackStore(context: modelContext)
        self.urlValidationService = URLValidationService()
    }

    /// Configure the LLM service. Must be called after initialization with LLMFacade.
    func configureLLMService(llmFacade: LLMFacade) {
        self.llmService = SearchOpsLLMService(
            llmFacade: llmFacade,
            settingsStore: settingsStore
        )
    }

    func initialize() {
        guard !isInitialized else { return }

        // Ensure preferences and settings exist
        _ = preferencesStore.current()
        _ = settingsStore.current()

        // Ensure current week's goal exists
        _ = weeklyGoalStore.currentWeek()

        // Clean up old tasks
        dailyTaskStore.clearOldTasks(olderThan: 14)

        // Update relationship warmth levels
        contactStore.updateAllWarmthLevels()

        isInitialized = true
        Logger.info("✅ SearchOps initialized", category: .appLifecycle)
    }

    // MARK: - Module State Checks

    var needsOnboarding: Bool {
        !preferencesStore.isConfigured
    }

    var hasActiveSources: Bool {
        !jobSourceStore.activeSources.isEmpty
    }

    // MARK: - Time Tracking

    func startTimeTracking(activity: ActivityType) {
        // End any existing entry
        endTimeTracking()

        let entry = TimeEntry(activityType: activity, startTime: Date())
        entry.isAutomatic = true
        entry.trackingSource = .appForeground
        timeEntryStore.add(entry)
        currentTimeEntry = entry
    }

    func endTimeTracking() {
        guard let entry = currentTimeEntry else { return }

        entry.endTime = Date()
        entry.durationSeconds = Int(entry.endTime!.timeIntervalSince(entry.startTime))
        currentTimeEntry = nil

        // Add to weekly goal
        weeklyGoalStore.addTimeMinutes(entry.durationMinutes)
    }

    func switchTimeTracking(to activity: ActivityType) {
        endTimeTracking()
        startTimeTracking(activity: activity)
    }

    // MARK: - Source Operations

    func visitSource(_ source: JobSource) {
        jobSourceStore.markVisited(source)
    }

    // MARK: - Source Validation

    func validateSources() async {
        let sourcesToValidate = jobSourceStore.sourcesNeedingRevalidation

        guard !sourcesToValidate.isEmpty else {
            Logger.debug("📋 No sources need revalidation", category: .networking)
            return
        }

        Logger.info("🔍 Validating \(sourcesToValidate.count) job sources", category: .networking)

        let urls = sourcesToValidate.map { $0.url }
        let results = await urlValidationService.validateBatch(urls)

        for result in results {
            if let source = jobSourceStore.source(byUrl: result.url) {
                jobSourceStore.updateValidation(source, valid: result.isValid)

                if !result.isValid {
                    Logger.warning("⚠️ Source validation failed: \(source.name) - \(result.error ?? "Unknown")", category: .networking)
                }
            }
        }

        Logger.info("✅ Source validation complete", category: .networking)
    }

    // MARK: - Daily Summary

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
        let tasks = dailyTaskStore.todaysTasks
        let completedTasks = tasks.filter { $0.isCompleted }

        let applicationsSubmitted = completedTasks.filter { $0.taskType == .submitApplication }.count
        let followUpsSent = completedTasks.filter { $0.taskType == .followUp }.count
        let sourcesVisited = completedTasks.filter { $0.taskType == .gatherLeads }.count

        let calendar = Calendar.current
        let todaysEvents = eventStore.upcomingEvents.filter {
            calendar.isDateInToday($0.date)
        }

        return DailySummary(
            tasksTotal: tasks.count,
            tasksCompleted: completedTasks.count,
            timeSpentMinutes: timeEntryStore.totalMinutesForDate(Date()),
            sourcesVisited: sourcesVisited,
            applicationsSubmitted: applicationsSubmitted,
            followUpsSent: followUpsSent,
            eventsToday: todaysEvents,
            contactsNeedingAttention: Array(contactStore.needsAttention.prefix(5))
        )
    }

    // MARK: - Weekly Summary

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
        let goal = weeklyGoalStore.currentWeek()

        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        let eventsAttended = eventStore.attendedEvents.filter { event in
            guard let attendedAt = event.attendedAt else { return false }
            return attendedAt >= weekStart
        }

        return WeeklySummary(
            goal: goal,
            applicationProgress: goal.applicationProgress,
            networkingProgress: goal.networkingProgress,
            timeProgress: goal.timeProgress,
            topSources: jobSourceStore.topSourcesByEffectiveness(limit: 3),
            eventsAttended: eventsAttended,
            newContacts: contactStore.thisWeeksNewContacts,
            reflectionNeeded: goal.llmReflection == nil && goal.applicationActual > 0
        )
    }

    // MARK: - Event Workflow Helpers

    func recordEventAttendance(_ event: NetworkingEventOpportunity) {
        eventStore.markAsAttended(event)
        weeklyGoalStore.incrementEventsAttended()
    }

    func recordEventDebrief(
        _ event: NetworkingEventOpportunity,
        contacts: [NetworkingContact],
        rating: EventRating,
        wouldRecommend: Bool,
        whatWorked: String?,
        whatDidntWork: String?
    ) {
        // Update event
        event.contactCount = contacts.count
        event.eventRating = rating
        event.wouldRecommend = wouldRecommend
        event.whatWorked = whatWorked
        event.whatDidntWork = whatDidntWork
        eventStore.markAsDebriefed(event)

        // Record feedback for learning
        let feedback = EventFeedback()
        feedback.eventOpportunityId = event.id
        feedback.eventType = event.eventType
        feedback.organizer = event.organizer
        feedback.attendanceSize = event.estimatedAttendance
        feedback.wasVirtual = event.isVirtual
        feedback.cost = event.cost
        feedback.rating = rating
        feedback.contactsMade = contacts.count
        feedback.qualityContactsMade = contacts.filter { $0.warmth == .hot }.count
        feedback.wouldRecommend = wouldRecommend
        feedback.whatWorked = whatWorked
        feedback.whatDidntWork = whatDidntWork
        feedbackStore.add(feedback)

        // Update weekly goal
        weeklyGoalStore.incrementNewContacts(count: contacts.count)

        Logger.info("📝 Event debrief recorded: \(event.name) - \(contacts.count) contacts", category: .ai)
    }

    // MARK: - Agent Service

    private var _agentService: SearchOpsAgentService?

    private var agentService: SearchOpsAgentService? {
        if let existing = _agentService {
            return existing
        }
        guard let llmService = llmService else { return nil }
        let contextProvider = SearchOpsContextProviderImpl(coordinator: self)
        let service = SearchOpsAgentService(
            llmFacade: llmService.llmFacade,
            contextProvider: contextProvider,
            settingsStore: settingsStore
        )
        _agentService = service
        return service
    }

    // MARK: - LLM Agent Operations

    /// Generate today's tasks using LLM agent
    func generateDailyTasks(focusArea: String = "balanced") async throws {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }

        let result = try await agent.generateDailyTasks(focusArea: focusArea)

        // Clear existing LLM-generated tasks for today
        for task in dailyTaskStore.todaysTasks where task.isLLMGenerated {
            dailyTaskStore.delete(task)
        }

        // Convert and add new tasks
        let tasks = result.tasks.map { $0.toDailyTask() }
        dailyTaskStore.addMultiple(tasks)

        Logger.info("✅ Generated \(tasks.count) daily tasks", category: .ai)
    }

    /// Discover new job sources using LLM agent
    func discoverJobSources() async throws {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }

        let prefs = preferencesStore.current()
        let result = try await agent.discoverJobSources(
            sectors: prefs.targetSectors,
            location: prefs.primaryLocation
        )

        // Filter duplicates and add new sources
        let newSources = result.sources.filter { generated in
            !jobSourceStore.exists(url: generated.url)
        }.map { $0.toJobSource() }

        jobSourceStore.addMultiple(newSources)

        Logger.info("✅ Discovered \(newSources.count) new job sources", category: .ai)
    }

    /// Discover networking events using LLM agent
    func discoverNetworkingEvents(daysAhead: Int = 14) async throws {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }

        let prefs = preferencesStore.current()
        let result = try await agent.discoverNetworkingEvents(
            sectors: prefs.targetSectors,
            location: prefs.primaryLocation,
            daysAhead: daysAhead
        )

        // Filter duplicates and add new events
        let newEvents = eventStore.filterNew(
            result.events.map { $0.toNetworkingEventOpportunity() }
        )

        eventStore.addMultiple(newEvents)

        Logger.info("✅ Discovered \(newEvents.count) new events", category: .ai)
    }

    /// Evaluate an event for attendance using LLM agent
    func evaluateEvent(_ event: NetworkingEventOpportunity) async throws -> EventEvaluationResult {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }

        let result = try await agent.evaluateEvent(eventId: event.id)

        // Update event with evaluation
        event.llmRecommendation = result.attendanceRecommendation
        event.llmRationale = result.rationale
        event.expectedValue = result.expectedValue
        event.concerns = result.concerns
        event.status = .evaluating
        eventStore.update(event)

        Logger.info("✅ Evaluated event: \(event.name) - \(result.recommendation)", category: .ai)

        return result
    }

    /// Prepare for an event using LLM agent
    func prepareForEvent(_ event: NetworkingEventOpportunity, focusCompanies: [String] = [], goals: String? = nil) async throws -> EventPrepResult {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }

        let result = try await agent.prepareForEvent(
            eventId: event.id,
            focusCompanies: focusCompanies,
            goals: goals
        )

        // Update event with prep materials
        event.goal = result.goal
        event.pitchScript = result.pitchScript

        // Encode talking points and target companies as JSON
        let encoder = JSONEncoder()
        if let talkingPointsData = try? encoder.encode(result.talkingPoints.map { $0.toTalkingPoint() }) {
            event.talkingPointsJSON = String(data: talkingPointsData, encoding: .utf8)
        }
        if let targetCompaniesData = try? encoder.encode(result.targetCompanies.map { $0.toTargetCompanyContext() }) {
            event.targetCompaniesJSON = String(data: targetCompaniesData, encoding: .utf8)
        }

        event.conversationStarters = result.conversationStarters
        event.thingsToAvoid = result.thingsToAvoid
        eventStore.update(event)

        Logger.info("✅ Prepared for event: \(event.name)", category: .ai)

        return result
    }

    /// Generate weekly reflection using LLM agent
    func generateWeeklyReflection() async throws {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }

        let reflection = try await agent.generateWeeklyReflection()

        weeklyGoalStore.setReflection(reflection)

        Logger.info("✅ Generated weekly reflection", category: .ai)
    }

    /// Suggest networking actions using LLM agent
    func suggestNetworkingActions(focus: String = "balanced") async throws -> NetworkingActionsResult {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }

        let result = try await agent.suggestNetworkingActions(focus: focus)

        Logger.info("✅ Suggested \(result.actions.count) networking actions", category: .ai)

        return result
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

        let result = try await agent.draftOutreachMessage(
            contactId: contact.id,
            purpose: purpose,
            channel: channel,
            tone: tone
        )

        Logger.info("✅ Drafted outreach message for: \(contact.displayName)", category: .ai)

        return result
    }

    /// Run a conversational agent with custom prompt
    func runAgent(systemPrompt: String, userMessage: String) async throws -> String {
        guard let agent = agentService else {
            throw SearchOpsLLMError.toolExecutionFailed("Agent service not configured")
        }

        return try await agent.runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )
    }

    // MARK: - Contact Workflow Helpers

    func recordContactInteraction(
        _ contact: NetworkingContact,
        type: InteractionType,
        notes: String = "",
        outcome: InteractionOutcome? = nil,
        followUpNeeded: Bool = false,
        followUpAction: String? = nil,
        followUpDate: Date? = nil
    ) {
        let interaction = NetworkingInteraction(contactId: contact.id, type: type)
        interaction.notes = notes
        interaction.outcome = outcome
        interaction.followUpNeeded = followUpNeeded
        interaction.followUpAction = followUpAction
        interaction.followUpDate = followUpDate
        interactionStore.add(interaction)

        // Update contact
        contactStore.recordInteraction(contact, type: type.rawValue)

        // Upgrade warmth if positive outcome
        if outcome == .positive || outcome == .referralOffered || outcome == .introOffered {
            if contact.warmth != .hot {
                contactStore.updateWarmth(contact, to: .hot)
            }
        }

        // Track follow-ups
        if type.isOutbound {
            weeklyGoalStore.incrementFollowUpsSent()
        }
    }
}
