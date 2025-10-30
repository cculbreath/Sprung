//
//  OnboardingCheckpointManager.swift
//  Sprung
//
//  Manages checkpoint persistence and restoration for interview sessions.
//  Wraps the Checkpoints actor with a MainActor-friendly interface.
//

import Foundation
import SwiftyJSON

typealias CheckpointSnapshot = (
    session: InterviewSession,
    applicantProfile: JSON?,
    skeletonTimeline: JSON?,
    enabledSections: [String]?,
    ledger: [ObjectiveEntry]
)

@MainActor
final class OnboardingCheckpointManager {
    // MARK: - Dependencies

    private let checkpoints: Checkpoints
    private let interviewState: InterviewState

    // MARK: - Init

    init(checkpoints: Checkpoints, interviewState: InterviewState) {
        self.checkpoints = checkpoints
        self.interviewState = interviewState
    }

    // MARK: - Public API

    /// Checks if a restorable checkpoint exists.
    func hasRestorableCheckpoint() async -> Bool {
        await checkpoints.hasCheckpoint()
    }

    /// Restores the latest checkpoint if available.
    /// - Returns: Checkpoint snapshot containing session, profile, timeline, and enabled sections, or nil if no checkpoint exists.
    func restoreLatest() async -> CheckpointSnapshot? {
        await checkpoints.restoreLatest()
    }

    /// Saves a checkpoint with the current interview state.
    func save(
        applicantProfile: JSON?,
        skeletonTimeline: JSON?,
        enabledSections: [String]?
    ) async {
        let session = await interviewState.currentSession()
        await checkpoints.save(
            from: session,
            applicantProfile: applicantProfile,
            skeletonTimeline: skeletonTimeline,
            enabledSections: enabledSections.flatMap { $0.isEmpty ? nil : $0 }
        )
        Logger.debug("💾 Checkpoint saved (phase: \(session.phase.rawValue))", category: .ai)
    }

    /// Clears all saved checkpoints.
    func clear() async {
        await checkpoints.clear()
        Logger.debug("🗑️ Checkpoints cleared", category: .ai)
    }
}
