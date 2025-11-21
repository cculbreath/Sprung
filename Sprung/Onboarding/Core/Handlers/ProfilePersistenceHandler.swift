import Foundation
import SwiftyJSON
/// Handler responsible for persisting applicant profile data to SwiftData.
/// Listens to `.applicantProfileStored` events and syncs with SwiftData storage.
@MainActor
final class ProfilePersistenceHandler {
    private let applicantProfileStore: ApplicantProfileStore
    private let toolRouter: ToolHandler
    private let checkpointManager: CheckpointManager
    private let eventBus: EventCoordinator
    
    private var subscriptionTask: Task<Void, Never>?
    
    init(
        applicantProfileStore: ApplicantProfileStore,
        toolRouter: ToolHandler,
        checkpointManager: CheckpointManager,
        eventBus: EventCoordinator
    ) {
        self.applicantProfileStore = applicantProfileStore
        self.toolRouter = toolRouter
        self.checkpointManager = checkpointManager
        self.eventBus = eventBus
    }
    
    /// Start listening to applicant profile events
    func start() async {
        subscriptionTask?.cancel()
        
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            
            for await event in await self.eventBus.stream(topic: .state) {
                await self.handleEvent(event)
            }
        }
        
        Logger.info("📋 ProfilePersistenceHandler started", category: .ai)
    }
    
    func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }
    
    private func handleEvent(_ event: OnboardingEvent) async {
        switch event {
        case .applicantProfileStored(let json):
            await persistProfileToSwiftData(json)
            await checkpointManager.saveCheckpoint()
            
        default:
            break
        }
    }
    
    private func persistProfileToSwiftData(_ json: JSON) async {
        let draft = ApplicantProfileDraft(json: json)
        let profile = applicantProfileStore.currentProfile()
        draft.apply(to: profile, replaceMissing: false)
        applicantProfileStore.save(profile)
        Logger.info("💾 Applicant profile persisted to SwiftData", category: .ai)
        
        // Update summary card if showing (e.g., when photo is added)
        if toolRouter.profileHandler.pendingApplicantProfileSummary != nil {
            let updatedDraft = ApplicantProfileDraft(profile: profile)
            let updatedJSON = updatedDraft.toSafeJSON()
            toolRouter.profileHandler.updateProfileSummary(profile: updatedJSON)
        }
    }
}
