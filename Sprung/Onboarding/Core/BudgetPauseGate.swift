//
//  BudgetPauseGate.swift
//  Sprung
//
//  Suspends the interview LLM loop when an API request fails because the
//  account balance/credits are exhausted, until the user either tops up
//  (resume — retry the same request) or aborts (cancel).
//
//  Mirrors `UIToolContinuationRegistry`: a single pending `CheckedContinuation`,
//  an observable flag the view binds a modal to, and an interrupt path for
//  global stop / session reset.
//

import Foundation
import Observation

/// Provider-neutral description of an exhausted-balance condition, surfaced to
/// the top-up modal. `topUpURL` is a `String` (converted with `if let` at the
/// open-URL site) so no force-unwrap is needed.
struct BudgetPauseInfo: Identifiable, Equatable {
    let id = UUID()
    let providerName: String
    let topUpURL: String
    /// Token counts when the provider reported them (OpenRouter-style 402).
    /// Nil for Anthropic's raw 400 "credit balance is too low" — the modal then
    /// shows generic copy.
    let requested: Int?
    let available: Int?

    /// The onboarding interview talks to Anthropic exclusively, so the top-up
    /// destination is the Anthropic Console billing page named in the API error
    /// ("Please go to Plans & Billing…").
    static func anthropic(requested: Int? = nil, available: Int? = nil) -> BudgetPauseInfo {
        BudgetPauseInfo(
            providerName: "Anthropic",
            topUpURL: "https://console.anthropic.com/settings/billing",
            requested: requested,
            available: available
        )
    }
}

/// How the user resolved a budget pause.
enum BudgetPauseResolution: Sendable {
    /// User topped up — retry the work that failed.
    case resume
    /// User declined — abort the current operation.
    case cancel
}

/// Gate that pauses the interview on an insufficient-balance error.
///
/// Two entry points set the modal:
/// - `awaitResolution(_:)` — the chat-loop choke point calls this and **suspends**
///   until the user acts, then retries or aborts based on the result.
/// - `surface(_:)` — fail-fast extraction passes call this to show the modal
///   **without** suspending (they record their failed work for re-run on resume).
@MainActor
@Observable
final class BudgetPauseGate {

    /// Non-nil while paused/awaiting the user. Drives the modal sheet.
    private(set) var pendingPause: BudgetPauseInfo?

    @ObservationIgnored
    private var continuation: CheckedContinuation<BudgetPauseResolution, Never>?

    /// Whether the modal is currently shown for any reason.
    var isPaused: Bool { pendingPause != nil }

    // MARK: - Suspend (chat loop)

    /// Show the modal and suspend until the user resolves it. Supersedes any
    /// prior suspended pause.
    func awaitResolution(_ info: BudgetPauseInfo) async -> BudgetPauseResolution {
        if let existing = continuation {
            existing.resume(returning: .cancel)
            continuation = nil
            Logger.warning("⚠️ Superseded existing budget pause continuation", category: .ai)
        }

        let resolution = await withCheckedContinuation { cont in
            continuation = cont
            pendingPause = info
            Logger.warning("💳 Interview paused — insufficient \(info.providerName) balance", category: .ai)
        }

        continuation = nil
        pendingPause = nil
        return resolution
    }

    // MARK: - Surface only (fail-fast extraction)

    /// Show the modal without suspending. No-op if a pause is already showing.
    func surface(_ info: BudgetPauseInfo) {
        guard pendingPause == nil else { return }
        pendingPause = info
        Logger.warning("💳 Budget modal surfaced by extraction failure (\(info.providerName))", category: .ai)
    }

    // MARK: - Resolve

    /// Resume a suspended pause (if any) and clear the modal. Called from the
    /// coordinator when the user picks Resume/Cancel.
    func resolve(_ resolution: BudgetPauseResolution) {
        Logger.info("💳 Budget pause resolved: \(resolution)", category: .ai)
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: resolution)
            // `awaitResolution` clears `pendingPause` after it resumes.
        } else {
            // Surfaced without a suspended chat loop — just clear the modal.
            pendingPause = nil
        }
    }

    /// Force-cancel a pending pause (global Stop / session reset).
    func interrupt() {
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: .cancel)
        }
        pendingPause = nil
    }

    /// Reset for a new session.
    func reset() { interrupt() }
}
