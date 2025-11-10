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

    func resolveChoice(selectionIds: [String]) -> JSON? {
        guard pendingChoicePrompt != nil, !selectionIds.isEmpty else {
            Logger.warning("⚠️ Attempted to resolve choice prompt without selections", category: .ai)
            return nil
        }

        var payload = JSON()
        payload["selectedIds"] = JSON(selectionIds)

        pendingChoicePrompt = nil

        Logger.info("✅ Choice prompt resolved (ids: \(selectionIds.joined(separator: ", ")))", category: .ai)
        return payload
    }

    func cancelChoicePrompt(reason: String) -> JSON? {
        guard pendingChoicePrompt != nil else { return nil }

        var payload = JSON()
        payload["cancelled"].boolValue = true
        if !reason.isEmpty {
            payload["userNotes"].string = reason
        }

        pendingChoicePrompt = nil

        Logger.info("❌ Choice prompt cancelled: \(reason)", category: .ai)
        return payload
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

    func cancelValidation(reason: String) -> JSON? {
        guard pendingValidationPrompt != nil else { return nil }

        Logger.info("❌ Validation prompt cancelled: \(reason)", category: .ai)

        var payload = JSON()
        payload["cancelled"].boolValue = true
        if !reason.isEmpty {
            payload["userNotes"].string = reason
        }

        pendingValidationPrompt = nil

        return payload
    }

    // MARK: - Lifecycle

    func reset() {
        pendingChoicePrompt = nil
        pendingValidationPrompt = nil
    }
}
