//
//  UnifiedJobFocusState.swift
//  Sprung
//
//  Shared state for job focus across modules.
//  Pure state container - NO NotificationCenter posts.
//

import Foundation
import SwiftUI

/// Shared state for job focus across modules.
/// Enables seamless handoff between modules without notifications.
/// Injected via @Environment - views observe changes reactively.
@Observable
@MainActor
final class UnifiedJobFocusState {

    // MARK: - Focus State

    /// The currently focused job (set from any module)
    var focusedJob: JobApp? {
        didSet {
            if let job = focusedJob {
                lastFocusedJobId = job.id
                UserDefaults.standard.set(job.id.uuidString, forKey: "unifiedFocusedJobId")
            }
        }
    }

    /// Last focused job ID for restoration
    private(set) var lastFocusedJobId: UUID?

    /// The tab to show when navigating to Resume Editor
    var focusedTab: TabList = .listing

    // MARK: - Computed Properties

    /// Returns true if there's a focused job
    var hasFocusedJob: Bool {
        focusedJob != nil
    }

    // MARK: - Initialization

    init() {
        // Restore last focused job ID from UserDefaults
        if let idString = UserDefaults.standard.string(forKey: "unifiedFocusedJobId"),
           let id = UUID(uuidString: idString) {
            lastFocusedJobId = id
        }
    }

    // MARK: - Restoration

    /// Restore focus from last session using available job apps
    func restoreFocus(from jobApps: [JobApp]) {
        guard focusedJob == nil,
              let savedId = lastFocusedJobId,
              let job = jobApps.first(where: { $0.id == savedId }) else {
            return
        }
        focusedJob = job
        Logger.info("Restored focus to: \(job.jobPosition)", category: .appLifecycle)
    }

}
