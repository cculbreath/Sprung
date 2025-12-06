import Foundation
import SwiftyJSON
/// Handler responsible for persisting applicant profile data to SwiftData.
/// Listens to `.applicantProfileStored` events and syncs with SwiftData storage.
@MainActor
final class ProfilePersistenceHandler {
    private let applicantProfileStore: ApplicantProfileStore
    private let toolRouter: ToolHandler
    private let eventBus: EventCoordinator
    private let ui: OnboardingUIState
    private var subscriptionTask: Task<Void, Never>?
    init(
        applicantProfileStore: ApplicantProfileStore,
        toolRouter: ToolHandler,
        eventBus: EventCoordinator,
        ui: OnboardingUIState
    ) {
        self.applicantProfileStore = applicantProfileStore
        self.toolRouter = toolRouter
        self.eventBus = eventBus
        self.ui = ui
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

        // Regenerate JSON from persisted profile to ensure image is included
        let updatedDraft = ApplicantProfileDraft(profile: profile)
        let updatedJSON = updatedDraft.toSafeJSON()

        // Update summary card if showing via pendingApplicantProfileSummary
        if toolRouter.profileHandler.pendingApplicantProfileSummary != nil {
            toolRouter.profileHandler.updateProfileSummary(profile: updatedJSON)
        }

        // Also update fallback UI state (used after profile objective completes)
        // This ensures photo uploads after profile completion still show in the card
        if ui.lastApplicantProfileSummary != nil {
            ui.lastApplicantProfileSummary = updatedJSON
            Logger.debug("📸 Updated lastApplicantProfileSummary with new profile data", category: .ai)
        }
    }
}
