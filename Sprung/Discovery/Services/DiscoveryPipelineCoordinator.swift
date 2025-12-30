//
//  DiscoveryPipelineCoordinator.swift
//  Sprung
//
//  Coordinator for pipeline and stage management concerns.
//  Handles job application pipeline, task management, goals, and time tracking.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class DiscoveryPipelineCoordinator {
    // MARK: - Stores

    let preferencesStore: SearchPreferencesStore
    let settingsStore: DiscoverySettingsStore
    let jobAppStore: JobAppStore
    let dailyTaskStore: DailyTaskStore
    let timeEntryStore: TimeEntryStore
    let weeklyGoalStore: WeeklyGoalStore

    // MARK: - Services

    private(set) var calendarService: CalendarIntegrationService?
    private(set) var llmService: DiscoveryLLMService?

    // MARK: - State

    private(set) var currentTimeEntry: TimeEntry?

    // MARK: - Initialization

    init(modelContext: ModelContext, jobAppStore: JobAppStore) {
        self.preferencesStore = SearchPreferencesStore()
        self.settingsStore = DiscoverySettingsStore()
        self.jobAppStore = jobAppStore
        self.dailyTaskStore = DailyTaskStore(context: modelContext)
        self.timeEntryStore = TimeEntryStore(context: modelContext)
        self.weeklyGoalStore = WeeklyGoalStore(context: modelContext)
        self.calendarService = CalendarIntegrationService()
    }

    /// Configure the LLM service. Must be called after initialization with LLMFacade.
    func configureLLMService(llmFacade: LLMFacade) {
        self.llmService = DiscoveryLLMService(
            llmFacade: llmFacade,
            settingsStore: settingsStore
        )
    }

    func initialize() {
        // Ensure preferences and settings exist
        _ = preferencesStore.current()
        _ = settingsStore.current()

        // Ensure current week's goal exists
        _ = weeklyGoalStore.currentWeek()

        // Clean up old tasks
        dailyTaskStore.clearOldTasks(olderThan: 14)
    }

    // MARK: - Module State Checks

    var needsOnboarding: Bool {
        !preferencesStore.isConfigured
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

    // MARK: - Daily Summary

    func todaysSummary(eventsToday: [NetworkingEventOpportunity], contactsNeedingAttention: [NetworkingContact]) -> DiscoveryCoordinator.DailySummary {
        let tasks = dailyTaskStore.todaysTasks
        let completedTasks = tasks.filter { $0.isCompleted }

        let applicationsSubmitted = completedTasks.filter { $0.taskType == .submitApplication }.count
        let followUpsSent = completedTasks.filter { $0.taskType == .followUp }.count
        let sourcesVisited = completedTasks.filter { $0.taskType == .gatherLeads }.count

        return DiscoveryCoordinator.DailySummary(
            tasksTotal: tasks.count,
            tasksCompleted: completedTasks.count,
            timeSpentMinutes: timeEntryStore.totalMinutesForDate(Date()),
            sourcesVisited: sourcesVisited,
            applicationsSubmitted: applicationsSubmitted,
            followUpsSent: followUpsSent,
            eventsToday: eventsToday,
            contactsNeedingAttention: contactsNeedingAttention
        )
    }

    // MARK: - Weekly Summary

    func thisWeeksSummary(topSources: [JobSource], eventsAttended: [NetworkingEventOpportunity], newContacts: [NetworkingContact]) -> DiscoveryCoordinator.WeeklySummary {
        let goal = weeklyGoalStore.currentWeek()

        return DiscoveryCoordinator.WeeklySummary(
            goal: goal,
            applicationProgress: goal.applicationProgress,
            networkingProgress: goal.networkingProgress,
            timeProgress: goal.timeProgress,
            topSources: topSources,
            eventsAttended: eventsAttended,
            newContacts: newContacts,
            reflectionNeeded: goal.llmReflection == nil && goal.applicationActual > 0
        )
    }

    // MARK: - Agent Service (shared with networking)

    private var _agentService: DiscoveryAgentService?

    func getOrCreateAgentService() -> DiscoveryAgentService? {
        return _agentService
    }

    func setAgentService(_ service: DiscoveryAgentService) {
        _agentService = service
    }

    // MARK: - LLM Agent Operations

    /// Generate today's tasks using LLM agent
    func generateDailyTasks(using agentService: DiscoveryAgentService, focusArea: String = "balanced") async throws {
        let result = try await agentService.generateDailyTasks(focusArea: focusArea)

        // Clear existing LLM-generated tasks for today
        for task in dailyTaskStore.todaysTasks where task.isLLMGenerated {
            dailyTaskStore.delete(task)
        }

        // Convert and add new tasks
        let tasks = result.tasks.map { $0.toDailyTask() }
        dailyTaskStore.addMultiple(tasks)

        Logger.info("✅ Generated \(tasks.count) daily tasks", category: .ai)
    }

    /// Generate weekly reflection using LLM agent
    func generateWeeklyReflection(using agentService: DiscoveryAgentService) async throws {
        let reflection = try await agentService.generateWeeklyReflection()

        weeklyGoalStore.setReflection(reflection)

        Logger.info("✅ Generated weekly reflection", category: .ai)
    }

    /// Run a conversational agent with custom prompt
    func runAgent(using agentService: DiscoveryAgentService, systemPrompt: String, userMessage: String) async throws -> String {
        return try await agentService.runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )
    }
}
