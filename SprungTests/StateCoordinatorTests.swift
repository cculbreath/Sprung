import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class StateCoordinatorTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var eventBus: EventCoordinator!
    var objectiveStore: ObjectiveStore!
    var stateCoordinator: StateCoordinator!
    
    // Dependencies
    var artifactRepo: ArtifactRepository!
    var chatStore: ChatTranscriptStore!
    var uiState: SessionUIState!

    override func setUpWithError() throws {
        // Setup SwiftData
        let schema = Schema([
            // Add all models required by ArtifactRepository/ChatStore
            OnboardingSession.self,
            OnboardingArtifactRecord.self,
            OnboardingMessageRecord.self,
            OnboardingObjectiveRecord.self,
            OnboardingPlanItemRecord.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: config)
        modelContext = modelContainer.mainContext
        
        // Setup Event Bus
        eventBus = EventCoordinator()
        
        // Setup Policy
        let policy = PhasePolicy(
            requiredObjectives: [
                .phase1CoreFacts: ["profile_completed", "timeline_created"]
            ],
            allowedTools: [
                .phase1CoreFacts: ["tool_a"]
            ]
        )
        
        // Setup Services
        // Note: ArtifactRepository and ChatTranscriptStore initializers might need checking
        // Assuming they take context and eventBus
        let sessionStore = OnboardingSessionStore(modelContext: modelContext)
        let persistenceHandler = SwiftDataSessionPersistenceHandler(sessionStore: sessionStore, eventBus: eventBus)
        
        artifactRepo = ArtifactRepository(eventBus: eventBus, sessionPersistenceHandler: persistenceHandler)
        chatStore = ChatTranscriptStore(eventBus: eventBus, sessionPersistenceHandler: persistenceHandler)
        uiState = SessionUIState(eventBus: eventBus)
        
        // Objective Store
        objectiveStore = ObjectiveStore(eventBus: eventBus, phasePolicy: policy, initialPhase: .phase1CoreFacts)
        
        // State Coordinator
        stateCoordinator = StateCoordinator(
            eventBus: eventBus,
            phasePolicy: policy,
            objectives: objectiveStore,
            artifacts: artifactRepo,
            chat: chatStore,
            uiState: uiState
        )
    }

    func testUpdateWizardProgress_Phase1Completion() async {
        // Given we are in Phase 1
        await stateCoordinator.setPhase(.phase1CoreFacts)
        
        // When we complete the required objectives
        // Note: "applicant_profile" etc are hardcoded in StateCoordinator's updateWizardProgress logic,
        // so we must use those specific IDs, not the dummy ones in my policy above.
        // Let's register them first if they aren't default.
        await objectiveStore.registerObjective("applicant_profile", label: "Profile", phase: .phase1CoreFacts)
        await objectiveStore.registerObjective("skeleton_timeline", label: "Timeline", phase: .phase1CoreFacts)
        await objectiveStore.registerObjective("enabled_sections", label: "Sections", phase: .phase1CoreFacts)
        
        // Complete them
        await objectiveStore.setObjectiveStatus("applicant_profile", status: .completed)
        await objectiveStore.setObjectiveStatus("skeleton_timeline", status: .completed)
        await objectiveStore.setObjectiveStatus("enabled_sections", status: .completed)
        
        // Trigger update (usually happens via event, but we can manually trigger or wait)
        // StateCoordinator listens to events. We can publish an event or call private method via reflection?
        // Actually, StateCoordinator.handleObjectiveEvent calls updateWizardProgress.
        // And setObjectiveStatus emits .objectiveStatusChanged.
        // So waiting a bit should trigger it via the event bus.
        
        // Wait for async event propagation
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Then verify wizard step
        let steps = await stateCoordinator.completedWizardSteps
        XCTAssertTrue(steps.contains(.resumeIntake), "Resume intake should be marked complete")
    }
    
    func testAdvancePhase_Guard() async {
        // Given required objectives are NOT met
        await stateCoordinator.setPhase(.phase1CoreFacts)
        
        // When trying to advance
        let result = await stateCoordinator.advanceToNextPhase()
        
        // Then it should fail
        XCTAssertNil(result, "Should not advance when objectives are incomplete")
        let phase = await stateCoordinator.phase
        XCTAssertEqual(phase, .phase1CoreFacts)
    }
}
