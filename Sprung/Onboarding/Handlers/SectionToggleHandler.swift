//
//  SectionToggleHandler.swift
//  Sprung
//
//  Handles resume section toggle requests (enabling/disabling optional sections).
//

import Foundation
import Observation
import SwiftyJSON

@MainActor
@Observable
final class SectionToggleHandler {
    // MARK: - Observable State

    private(set) var pendingSectionToggleRequest: OnboardingSectionToggleRequest?

    // MARK: - Presentation

    /// Presents a section toggle request to the user.
    func presentToggleRequest(_ request: OnboardingSectionToggleRequest) {
        pendingSectionToggleRequest = request
        Logger.debug("🔀 Section toggle request presented", category: .ai)
    }

    // MARK: - Resolution

    /// Resolves a section toggle with the user's enabled sections.
    func resolveToggle(enabled: [String]) -> JSON? {
        guard pendingSectionToggleRequest != nil else {
            Logger.warning("⚠️ No pending section toggle to resolve", category: .ai)
            return nil
        }

        var payload = JSON()
        payload["enabledSections"] = JSON(enabled)

        clear()
        Logger.debug("✅ Section toggle resolved (enabled: \(enabled.joined(separator: ", ")))", category: .ai)
        return payload
    }

    /// Rejects a section toggle request.
    func rejectToggle(reason: String) -> JSON? {
        guard pendingSectionToggleRequest != nil else {
            Logger.warning("⚠️ No pending section toggle to reject", category: .ai)
            return nil
        }

        var payload = JSON()
        payload["cancelled"].boolValue = true
        if !reason.isEmpty {
            payload["userNotes"].string = reason
        }

        clear()
        Logger.debug("❌ Section toggle rejected", category: .ai)
        return payload
    }

    // MARK: - Lifecycle

    private func clear() {
        pendingSectionToggleRequest = nil
    }

    /// Clears all pending section toggle state (for interview reset).
    func reset() {
        clear()
    }
}
