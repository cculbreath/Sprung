//
//  ExperienceDefaultsAgentService.swift
//  Sprung
//
//  Orchestrates the ExperienceDefaults agent workflow:
//  1. Sets up workspace with KCs, skills, timeline, config
//  2. Runs the agent to generate experience defaults
//  3. Imports output to ExperienceDefaultsStore
//  4. Cleans up workspace
//

import Foundation
import Observation
import SwiftyJSON

// MARK: - Service Status

enum ExperienceDefaultsServiceStatus: Equatable {
    case idle
    case preparingWorkspace
    case runningAgent
    case importingResults
    case completed
    case failed(String)
}

// MARK: - Service

@Observable
@MainActor
final class ExperienceDefaultsAgentService {
    // Dependencies
    private weak var coordinator: OnboardingInterviewCoordinator?
    private let workspaceService: ExperienceDefaultsWorkspaceService

    // Tracking
    private let tracker: AgentActivityTracker?
    private var agentId: String?

    // State
    private(set) var status: ExperienceDefaultsServiceStatus = .idle
    private(set) var currentMessage: String = ""
    private(set) var agent: ExperienceDefaultsAgent?

    // Selected titles (from orchestrator LLM selection)
    private let selectedTitles: [String]?

    // Configuration - uses same model as card merge (agentic OpenRouter model)
    private var modelId: String {
        UserDefaults.standard.string(forKey: "onboardingCardMergeModelId") ?? DefaultModels.openRouter
    }

    init(
        coordinator: OnboardingInterviewCoordinator,
        tracker: AgentActivityTracker? = nil,
        selectedTitles: [String]? = nil
    ) {
        self.coordinator = coordinator
        self.tracker = tracker
        self.selectedTitles = selectedTitles
        self.workspaceService = ExperienceDefaultsWorkspaceService(guidanceStore: coordinator.guidanceStore)
        Logger.info("🗂️ ExperienceDefaultsAgentService initialized\(selectedTitles != nil ? " with selected titles" : "")", category: .ai)
    }

    // MARK: - Public API

    /// Run the experience defaults generation workflow
    func run() async throws -> ExperienceDefaultsResult {
        guard let coordinator = coordinator else {
            throw ExperienceDefaultsServiceError.coordinatorNotAvailable
        }

        guard let facade = coordinator.llmFacade else {
            throw ExperienceDefaultsServiceError.llmNotAvailable
        }

        // Register with tracker
        if let tracker = tracker {
            agentId = tracker.trackAgent(
                type: .experienceDefaults,
                name: "Experience Defaults",
                task: nil as Task<Void, Never>?
            )
            if let agentId = agentId {
                tracker.appendTranscript(
                    agentId: agentId,
                    entryType: .system,
                    content: "Starting experience defaults agent",
                    details: "Generating resume content from knowledge cards"
                )
            }
        }

        do {
            // Step 1: Prepare workspace
            status = .preparingWorkspace
            currentMessage = "Preparing workspace..."
            updateTrackerStatus("Preparing workspace")

            let workspacePath = try workspaceService.createWorkspace()

            // Gather data
            let knowledgeCards = coordinator.getKnowledgeCardStore().onboardingCards
            let skills = coordinator.skillStore.skills
            let timelineEntries = getTimelineEntries()
            let enabledSections = await coordinator.state.getEnabledSections()
            let customFields = await coordinator.state.getCustomFieldDefinitions()

            // Export to workspace
            try workspaceService.exportData(
                knowledgeCards: knowledgeCards,
                skills: skills,
                timelineEntries: timelineEntries,
                enabledSections: enabledSections.sorted(),
                customFields: customFields,
                selectedTitles: selectedTitles
            )

            Logger.info("🗂️ Workspace prepared with \(knowledgeCards.count) KCs, \(skills.count) skills, \(timelineEntries.count) timeline entries", category: .ai)

            // Step 2: Run agent
            status = .runningAgent
            currentMessage = "Running agent..."
            updateTrackerStatus("Generating content")

            let agent = ExperienceDefaultsAgent(
                workspacePath: workspacePath,
                modelId: modelId,
                facade: facade,
                agentId: agentId,
                tracker: tracker
            )
            self.agent = agent

            let result = try await agent.run()

            // Step 3: Import results
            status = .importingResults
            currentMessage = "Importing results..."
            updateTrackerStatus("Importing results")

            // Publish event - the event handler in OnboardingPersistenceService handles:
            // 1. Persisting to ExperienceDefaultsStore
            // 2. Persisting to InterviewDataStore for phase completion gating
            // 3. Marking the experienceDefaultsSet objective as completed
            await coordinator.eventBus.publish(.artifact(.experienceDefaultsGenerated(defaults: result.defaults)))

            // Step 4: Cleanup
            try? workspaceService.deleteWorkspace()

            status = .completed
            currentMessage = "Complete: \(result.summary)"
            updateTrackerStatus("Complete")

            if let agentId = agentId {
                tracker?.appendTranscript(
                    agentId: agentId,
                    entryType: .assistant,
                    content: "Complete",
                    details: result.summary
                )
                tracker?.markCompleted(agentId: agentId)
            }

            Logger.info("🗂️ ExperienceDefaults generation complete: \(result.sectionsGenerated.joined(separator: ", "))", category: .ai)

            return result

        } catch {
            status = .failed(error.localizedDescription)
            currentMessage = "Failed: \(error.localizedDescription)"

            if let agentId = agentId {
                tracker?.markFailed(agentId: agentId, error: error.localizedDescription)
            }

            // Cleanup on failure
            try? workspaceService.deleteWorkspace()

            throw error
        }
    }

    // MARK: - Helpers

    private func getTimelineEntries() -> [JSON] {
        guard let coordinator = coordinator else { return [] }

        // Get timeline from UI state
        guard let timeline = coordinator.ui.skeletonTimeline,
              let experiences = timeline["experiences"].array else {
            return []
        }

        // Filter to entries marked for inclusion
        return experiences.filter { entry in
            entry["includeInResume"].boolValue
        }
    }

    private func updateTrackerStatus(_ message: String) {
        if let agentId = agentId {
            tracker?.updateStatusMessage(agentId: agentId, message: message)
        }
    }
}

// MARK: - Errors

enum ExperienceDefaultsServiceError: LocalizedError {
    case coordinatorNotAvailable
    case llmNotAvailable

    var errorDescription: String? {
        switch self {
        case .coordinatorNotAvailable:
            return "Interview coordinator is not available"
        case .llmNotAvailable:
            return "LLM service is not available"
        }
    }
}
