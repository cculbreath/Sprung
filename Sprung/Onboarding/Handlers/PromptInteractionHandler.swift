import Foundation
import Observation
import SwiftyJSON

/// Handles choice and validation prompts, managing continuation IDs and payload construction.
@MainActor
@Observable
final class PromptInteractionHandler {
    // MARK: - Observable State

    private(set) var pendingChoicePrompt: OnboardingChoicePrompt?
    private(set) var pendingValidationPrompt: OnboardingValidationPrompt?

    // MARK: - Private State

    private var choiceContinuationId: UUID?
    private var validationContinuationId: UUID?

    // MARK: - Choice Prompts

    func presentChoicePrompt(_ prompt: OnboardingChoicePrompt, continuationId: UUID) {
        pendingChoicePrompt = prompt
        choiceContinuationId = continuationId
        Logger.info("📝 Choice prompt presented (id: \(prompt.id))", category: .ai)
    }

    func clearChoicePrompt(continuationId: UUID) {
        guard choiceContinuationId == continuationId else { return }
        pendingChoicePrompt = nil
        choiceContinuationId = nil
    }

    func resolveChoice(selectionIds: [String]) -> (UUID, JSON)? {
        guard let continuationId = choiceContinuationId, !selectionIds.isEmpty else {
            Logger.warning("⚠️ Attempted to resolve choice prompt without selections", category: .ai)
            return nil
        }

        var payload = JSON()
        payload["selectedIds"] = JSON(selectionIds)

        pendingChoicePrompt = nil
        choiceContinuationId = nil

        Logger.info("✅ Choice prompt resolved (ids: \(selectionIds.joined(separator: ", ")))", category: .ai)
        return (continuationId, payload)
    }

    func cancelChoicePrompt(reason: String) -> (UUID, JSON)? {
        guard let continuationId = choiceContinuationId else { return nil }

        var payload = JSON()
        payload["cancelled"].boolValue = true
        if !reason.isEmpty {
            payload["userNotes"].string = reason
        }

        pendingChoicePrompt = nil
        choiceContinuationId = nil

        Logger.info("❌ Choice prompt cancelled: \(reason)", category: .ai)
        return (continuationId, payload)
    }

    // MARK: - Validation Prompts

    func presentValidationPrompt(_ prompt: OnboardingValidationPrompt, continuationId: UUID) {
        pendingValidationPrompt = prompt
        validationContinuationId = continuationId
        Logger.info("🧾 Validation prompt presented (id: \(prompt.id))", category: .ai)
    }

    func clearValidationPrompt(continuationId: UUID) {
        guard validationContinuationId == continuationId else { return }
        pendingValidationPrompt = nil
        validationContinuationId = nil
    }

    func submitValidationResponse(
        status: String,
        updatedData: JSON?,
        changes: JSON?,
        notes: String?
    ) -> (UUID, JSON)? {
        guard let continuationId = validationContinuationId else { return nil }

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
        validationContinuationId = nil

        Logger.info("✅ Validation response submitted (status: \(status))", category: .ai)
        return (continuationId, payload)
    }

    func cancelValidation(reason: String) -> (UUID, JSON)? {
        guard let continuationId = validationContinuationId else { return nil }

        Logger.info("❌ Validation prompt cancelled: \(reason)", category: .ai)

        var payload = JSON()
        payload["cancelled"].boolValue = true
        if !reason.isEmpty {
            payload["userNotes"].string = reason
        }

        pendingValidationPrompt = nil
        validationContinuationId = nil

        return (continuationId, payload)
    }

    // MARK: - Lifecycle

    func reset() {
        pendingChoicePrompt = nil
        pendingValidationPrompt = nil
        choiceContinuationId = nil
        validationContinuationId = nil
    }
}
