import Foundation
import SwiftyJSON
/// Manages checkpoint save/restore at phase transitions only.
/// Checkpoints are saved when phases transition - UI state is deterministic at these points.
@MainActor
final class CheckpointManager {
    // MARK: - Dependencies
    private let state: StateCoordinator
    private let checkpoints: Checkpoints
    private let applicantProfileStore: ApplicantProfileStore
    // MARK: - Initialization
    init(
        state: StateCoordinator,
        eventBus: EventCoordinator,
        checkpoints: Checkpoints,
        applicantProfileStore: ApplicantProfileStore
    ) {
        self.state = state
        self.checkpoints = checkpoints
        self.applicantProfileStore = applicantProfileStore
    }
    // MARK: - Checkpoint Operations
    /// Save checkpoint at phase transition
    func saveCheckpoint() async {
        let snapshot = await state.createSnapshot()
        let artifacts = await state.artifacts
        checkpoints.save(
            snapshot: snapshot,
            profileJSON: artifacts.applicantProfile,
            timelineJSON: artifacts.skeletonTimeline,
            enabledSections: artifacts.enabledSections
        )
        Logger.info("💾 Checkpoint saved at phase transition", category: .ai)
    }
    func restoreFromCheckpointIfAvailable() async -> Bool {
        guard let checkpoint = checkpoints.restore() else { return false }
        await state.restoreFromSnapshot(checkpoint.snapshot)
        // Restore artifacts from checkpoint via StateCoordinator
        if let profile = checkpoint.profileJSON {
            await state.storeApplicantProfile(profile)
            persistApplicantProfileToSwiftData(json: profile)
        }
        if let timeline = checkpoint.timelineJSON {
            await state.storeSkeletonTimeline(timeline)
        }
        if !checkpoint.enabledSections.isEmpty {
            await state.storeEnabledSections(checkpoint.enabledSections)
        }
        Logger.info("✅ Restored from checkpoint", category: .ai)
        return true
    }
    func restoreFromSpecificCheckpoint(_ checkpoint: OnboardingCheckpoint) async -> Bool {
        let data = checkpoints.restore(checkpoint: checkpoint)
        await state.restoreFromSnapshot(data.snapshot)
        // Restore artifacts from checkpoint via StateCoordinator
        if let profile = data.profileJSON {
            await state.storeApplicantProfile(profile)
            persistApplicantProfileToSwiftData(json: profile)
        }
        if let timeline = data.timelineJSON {
            await state.storeSkeletonTimeline(timeline)
        }
        if !data.enabledSections.isEmpty {
            await state.storeEnabledSections(data.enabledSections)
        }
        Logger.info("✅ Restored from specific checkpoint (\(checkpoint.timestamp))", category: .ai)
        return true
    }
    func clearCheckpoints() {
        checkpoints.clear()
    }
    // MARK: - Persistence Helpers
    private func persistApplicantProfileToSwiftData(json: JSON) {
        let draft = ApplicantProfileDraft(json: json)
        let profile = applicantProfileStore.currentProfile()
        draft.apply(to: profile, replaceMissing: false)
        applicantProfileStore.save(profile)
        Logger.info("💾 Applicant profile persisted to SwiftData", category: .ai)
    }
}
