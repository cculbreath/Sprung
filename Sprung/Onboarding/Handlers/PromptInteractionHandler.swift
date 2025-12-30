import Foundation
import Observation
import SwiftyJSON
/// Handles choice and validation prompts.
@MainActor
@Observable
final class PromptInteractionHandler {
    // MARK: - Observable State
    private(set) var pendingChoicePrompt: OnboardingChoicePrompt?
    private(set) var pendingValidationPrompt: OnboardingValidationPrompt?
    // MARK: - Choice Prompts
    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt) {
        pendingChoicePrompt = prompt
        Logger.info("📝 Choice prompt presented (id: \(prompt.id))", category: .ai)
    }
    func clearChoicePrompt() {
        pendingChoicePrompt = nil
    }
    /// Returns (payload, source) tuple. Source identifies special prompts like "skip_phase_approval".
    func resolveChoice(selectionIds: [String]) -> (payload: JSON, source: String?)? {
        guard let prompt = pendingChoicePrompt, !selectionIds.isEmpty else {
            Logger.warning("⚠️ Attempted to resolve choice prompt without selections", category: .ai)
            return nil
        }
        var payload = JSON()
        payload["selectedIds"] = JSON(selectionIds)
        let source = prompt.source
        pendingChoicePrompt = nil
        Logger.info("✅ Choice prompt resolved (ids: \(selectionIds.joined(separator: ", ")), source: \(source ?? "none"))", category: .ai)
        return (payload, source)
    }
    // MARK: - Validation Prompts
    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt) {
        pendingValidationPrompt = prompt
        Logger.info("🧾 Validation prompt presented (id: \(prompt.id))", category: .ai)
    }
    func clearValidationPrompt() {
        pendingValidationPrompt = nil
    }
    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) -> JSON? {
        guard pendingValidationPrompt != nil else { return nil }
        var payload = JSON()
        payload["status"].string = status
        if let updatedData, updatedData != .null {
            payload["data"] = updatedData
        }
        if let changes, changes != .null {
            payload["changes"] = changes
        }
        if let notes, !notes.isEmpty {
            payload["userNotes"].string = notes
        }
        pendingValidationPrompt = nil
        Logger.info("✅ Validation response submitted (status: \(status))", category: .ai)
        return payload
    }
    // MARK: - Lifecycle
    func reset() {
        pendingChoicePrompt = nil
        pendingValidationPrompt = nil
    }
}
