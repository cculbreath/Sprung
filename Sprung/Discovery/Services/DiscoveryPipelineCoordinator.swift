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

    // MARK: - Module State Checks

    var needsOnboarding: Bool {
        !preferencesStore.isConfigured
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

}
