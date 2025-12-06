//
//  DataPersistenceService.swift
//  Sprung
//
//  Service for managing data store reset and cleanup operations.
//  Extracted from OnboardingInterviewCoordinator to reduce complexity.
//
import Foundation
/// Service that handles data persistence operations
actor DataPersistenceService: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    private let state: StateCoordinator
    private let dataStore: InterviewDataStore
    private let toolRouter: ToolHandler
    private let wizardTracker: WizardProgressTracker
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        state: StateCoordinator,
        dataStore: InterviewDataStore,
        toolRouter: ToolHandler,
        wizardTracker: WizardProgressTracker
    ) {
        self.eventBus = eventBus
        self.state = state
        self.dataStore = dataStore
        self.toolRouter = toolRouter
        self.wizardTracker = wizardTracker
    }
    // MARK: - Store Management
    func clearArtifacts() async {
        await dataStore.reset()
    }
    func resetStore() async {
        await eventBus.publish(.processingStateChanged(false))
        await eventBus.publish(.waitingStateChanged(nil))
        await state.reset()
        await MainActor.run {
            toolRouter.reset()
            wizardTracker.reset()
        }
    }
}
