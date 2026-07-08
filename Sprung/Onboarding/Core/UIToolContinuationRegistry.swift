//
//  UIToolContinuationRegistry.swift
//  Sprung
//
//  Manages continuations for UI tools that block until user action.
//  Enables single-turn tool responses instead of double-turn await/result pattern.
//

import Foundation
import SwiftyJSON

/// Result of a UI tool that was awaiting user input
struct UIToolCompletionResult {
    let status: String
    let message: String
    let data: JSON?

    /// Build a JSON response suitable for tool result
    func toJSON() -> JSON {
        var result = JSON()
        result["status"].string = status
        result["message"].string = message
        if let data = data {
            result["data"] = data
        }
        return result
    }

    /// Standard cancelled result
    static func cancelled(reason: String = "User interrupted this operation. Ask them in chat if they want to try again.") -> UIToolCompletionResult {
        UIToolCompletionResult(status: "cancelled", message: reason, data: nil)
    }
}

/// Manages continuations for UI tools that need to block until user action.
///
/// Usage:
/// 1. Tool calls `awaitUserAction(toolName:)` which suspends until resumed
/// 2. UIResponseCoordinator calls `complete(toolName:result:)` when user acts
/// 3. Tool receives result and returns it as tool response (single API turn)
@MainActor
final class UIToolContinuationRegistry {

    /// Pending continuation for a UI tool
    private struct PendingContinuation {
        let continuation: CheckedContinuation<UIToolCompletionResult, Never>
        let startTime: Date
    }

    /// Active continuations keyed by tool name
    /// Only one continuation per tool type is allowed at a time
    private var pendingContinuations: [String: PendingContinuation] = [:]

    /// Callback when pending count changes (for UI updates)
    var onPendingCountChanged: ((Int) -> Void)?

    // MARK: - Await User Action

    /// Block until user completes the UI action for this tool.
    /// Returns the result from user action, or cancelled if interrupted.
    ///
    /// - Parameter toolName: The name of the tool presenting UI
    /// - Returns: The completion result from user action
    func awaitUserAction(toolName: String) async -> UIToolCompletionResult {
        // If there's already a pending continuation for this tool, cancel it first
        if let existing = pendingContinuations[toolName] {
            existing.continuation.resume(returning: .cancelled(reason: "Superseded by new \(toolName) call"))
            pendingContinuations.removeValue(forKey: toolName)
            Logger.warning("⚠️ Superseded existing \(toolName) continuation", category: .ai)
        }

        let result = await withCheckedContinuation { continuation in
            pendingContinuations[toolName] = PendingContinuation(
                continuation: continuation,
                startTime: Date()
            )
            onPendingCountChanged?(pendingContinuations.count)
            Logger.info("⏳ UI tool blocked awaiting user action: \(toolName)", category: .ai)
        }

        // Continuation was resumed - clean up
        pendingContinuations.removeValue(forKey: toolName)
        onPendingCountChanged?(pendingContinuations.count)

        return result
    }

    // MARK: - Complete User Action

    /// Resume the pending continuation for a tool with the user's result.
    /// Called by UIResponseCoordinator when user completes an action.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that presented UI
    ///   - result: The result from user action
    /// - Returns: True if a pending continuation was found and resumed
    @discardableResult
    func complete(toolName: String, result: UIToolCompletionResult) -> Bool {
        guard let pending = pendingContinuations[toolName] else {
            Logger.warning("⚠️ No pending continuation for \(toolName) - already completed or not blocking", category: .ai)
            return false
        }

        let duration = Date().timeIntervalSince(pending.startTime)
        pending.continuation.resume(returning: result)
        Logger.info("✅ UI tool completed: \(toolName) (blocked for \(String(format: "%.1f", duration))s)", category: .ai)

        // Note: Cleanup happens in awaitUserAction after resume
        return true
    }

}
