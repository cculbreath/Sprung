//
//  SectionToggleHandler.swift
//  Sprung
//
//  Handles resume section toggle requests (enabling/disabling optional sections).
//  Produces JSON payloads for tool continuations.
//

import Foundation
import Observation
import SwiftyJSON

@MainActor
@Observable
final class SectionToggleHandler {
    // MARK: - Observable State

    private(set) var pendingSectionToggleRequest: OnboardingSectionToggleRequest?

    // MARK: - Private State

    private var sectionToggleContinuationId: UUID?

    // MARK: - Presentation

    /// Presents a section toggle request to the user.
    func presentToggleRequest(_ request: OnboardingSectionToggleRequest, continuationId: UUID) {
        pendingSectionToggleRequest = request
        sectionToggleContinuationId = continuationId
        Logger.debug("🔀 Section toggle request presented", category: .ai)
    }

    // MARK: - Resolution

    /// Resolves a section toggle with the user's enabled sections.
    func resolveToggle(enabled: [String]) -> (continuationId: UUID, payload: JSON)? {
        guard let continuationId = sectionToggleContinuationId.guardContinuation(operation: "section toggle to resolve") else { return nil }

        var payload = JSON()
        payload["enabledSections"] = JSON(enabled)

        clear()
        Logger.debug("✅ Section toggle resolved (enabled: \(enabled.joined(separator: ", ")))", category: .ai)
        return (continuationId, payload)
    }

    /// Rejects a section toggle request.
    func rejectToggle(reason: String) -> (continuationId: UUID, payload: JSON)? {
        guard let continuationId = sectionToggleContinuationId.guardContinuation(operation: "section toggle to reject") else { return nil }

        var payload = JSON()
        payload["cancelled"].boolValue = true
        if !reason.isEmpty {
            payload["userNotes"].string = reason
        }

        clear()
        Logger.debug("❌ Section toggle rejected", category: .ai)
        return (continuationId, payload)
    }

    // MARK: - Lifecycle

    private func clear() {
        pendingSectionToggleRequest = nil
        sectionToggleContinuationId = nil
    }

    /// Clears all pending section toggle state (for interview reset).
    func reset() {
        clear()
    }
}
