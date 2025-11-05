import Foundation
import SwiftyJSON

/// Manages checkpoint scheduling, debounced save/restore logic.
/// Extracted from OnboardingInterviewCoordinator to improve maintainability.
@MainActor
final class CheckpointManager {
    // MARK: - Dependencies

    private let state: StateCoordinator
    private let checkpoints: Checkpoints
    private let applicantProfileStore: ApplicantProfileStore

    // MARK: - Debounce State

    private var checkpointDebounce: Task<Void, Never>?

    // MARK: - Initialization

    init(
        state: StateCoordinator,
        checkpoints: Checkpoints,
        applicantProfileStore: ApplicantProfileStore
    ) {
        self.state = state
        self.checkpoints = checkpoints
        self.applicantProfileStore = applicantProfileStore
    }

    // MARK: - Checkpoint Scheduling

    /// Schedule a debounced checkpoint save.
    /// Rapid edits don't spam disk; saves occur 300ms after last change.
    func scheduleCheckpoint() {
        checkpointDebounce?.cancel()
        checkpointDebounce = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                guard let self else { return }
                await self.saveCheckpoint()
            } catch {
                // Task was cancelled (new edit came in)
            }
        }
    }

    // MARK: - Checkpoint Operations

    func saveCheckpoint() async {
        let snapshot = await state.createSnapshot()
        let artifacts = await state.artifacts

        // Save to persistent storage - snapshot is used as-is
        checkpoints.save(
            snapshot: snapshot,
            profileJSON: artifacts.applicantProfile,
            timelineJSON: artifacts.skeletonTimeline,
            enabledSections: artifacts.enabledSections
        )
        Logger.debug("💾 Checkpoint saved", category: .ai)
    }

    func restoreFromCheckpointIfAvailable() async -> Bool {
        guard let checkpoint = checkpoints.restore() else { return false }

        await state.restoreFromSnapshot(checkpoint.snapshot)

        // Restore artifacts from checkpoint
        if let profile = checkpoint.profileJSON {
            await state.setApplicantProfile(profile)
            persistApplicantProfileToSwiftData(json: profile)
        }

        if let timeline = checkpoint.timelineJSON {
            await state.setSkeletonTimeline(timeline)
        }

        if !checkpoint.enabledSections.isEmpty {
            await state.setEnabledSections(checkpoint.enabledSections)
        }

        Logger.info("✅ Restored from checkpoint", category: .ai)
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
