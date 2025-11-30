import Foundation
import SwiftyJSON
/// Manages checkpoint scheduling, debounced save/restore logic.
/// Extracted from OnboardingInterviewCoordinator to improve maintainability.
@MainActor
final class CheckpointManager {
    // MARK: - Dependencies
    private let state: StateCoordinator
    private let eventBus: EventCoordinator
    private let checkpoints: Checkpoints
    private let applicantProfileStore: ApplicantProfileStore
    // MARK: - UI State Provider
    /// Closure to get current UI state for checkpointing (set by coordinator after init)
    var uiStateProvider: (() -> UIStateForCheckpoint)?
    /// Closure to restore UI state from checkpoint (set by coordinator after init)
    var uiStateRestorer: ((UIStateForCheckpoint) -> Void)?
    /// UI state data structure for checkpointing
    struct UIStateForCheckpoint {
        let knowledgeCardPlan: [KnowledgeCardPlanItem]
        let knowledgeCardPlanFocus: String?
        let knowledgeCardPlanMessage: String?
    }
    // MARK: - Debounce State
    private var checkpointDebounce: Task<Void, Never>?
    // MARK: - Initialization
    init(
        state: StateCoordinator,
        eventBus: EventCoordinator,
        checkpoints: Checkpoints,
        applicantProfileStore: ApplicantProfileStore
    ) {
        self.state = state
        self.eventBus = eventBus
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
        // Get UI state if provider is available
        let uiState = uiStateProvider?()
        // Save to persistent storage - snapshot is used as-is
        checkpoints.save(
            snapshot: snapshot,
            profileJSON: artifacts.applicantProfile,
            timelineJSON: artifacts.skeletonTimeline,
            enabledSections: artifacts.enabledSections,
            knowledgeCardPlan: uiState?.knowledgeCardPlan,
            knowledgeCardPlanFocus: uiState?.knowledgeCardPlanFocus,
            knowledgeCardPlanMessage: uiState?.knowledgeCardPlanMessage
        )
        Logger.debug("💾 Checkpoint saved", category: .ai)
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
        // Restore UI state if restorer is available
        if let knowledgeCardPlan = checkpoint.knowledgeCardPlan {
            let uiState = UIStateForCheckpoint(
                knowledgeCardPlan: knowledgeCardPlan,
                knowledgeCardPlanFocus: checkpoint.knowledgeCardPlanFocus,
                knowledgeCardPlanMessage: checkpoint.knowledgeCardPlanMessage
            )
            uiStateRestorer?(uiState)
            Logger.info("📋 Restored \(knowledgeCardPlan.count) knowledge card plan items", category: .ai)
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
        // Restore UI state if restorer is available
        if let knowledgeCardPlan = data.knowledgeCardPlan {
            let uiState = UIStateForCheckpoint(
                knowledgeCardPlan: knowledgeCardPlan,
                knowledgeCardPlanFocus: data.knowledgeCardPlanFocus,
                knowledgeCardPlanMessage: data.knowledgeCardPlanMessage
            )
            uiStateRestorer?(uiState)
            Logger.info("📋 Restored \(knowledgeCardPlan.count) knowledge card plan items", category: .ai)
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
