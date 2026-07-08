//
//  TimeoutPauseGate.swift
//  Sprung
//
//  Suspends a single document's analysis when an LLM request times out (a large
//  PDF chunk whose time-to-first-byte exceeded the request timeout, or a pass that
//  stalled mid-stream), until the user either keeps waiting (retry the same work)
//  or aborts (keep the extracted text, skip AI analysis).
//
//  Mirrors `BudgetPauseGate`: a single pending `CheckedContinuation`, an observable
//  flag the view binds a modal to, and an interrupt path for global stop / session
//  reset. The two gates are deliberately separate — a timeout is recovered by
//  waiting, not by topping up — and the view prioritizes the budget gate when both
//  could fire.
//

import Foundation
import Observation

/// Describes the document whose analysis timed out, surfaced to the retry modal.
/// `attempt` is 1-based and increments each time the user chooses Keep Waiting, so
/// the modal can communicate the soft cap.
struct TimeoutPauseInfo: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let attempt: Int
}

/// How the user resolved a timeout pause.
enum TimeoutPauseResolution: Sendable {
    /// Keep waiting — retry the same analysis (cheap against a saved transcription;
    /// a full re-ingest when no intermediate representation exists yet).
    case keepWaiting
    /// Abort — keep the already-extracted text/transcription, skip AI analysis.
    case abort
}

/// Gate that pauses one document's analysis on a request-timeout.
///
/// The document-processing choke point calls `awaitResolution(_:)` and **suspends**
/// until the user acts, then retries or aborts based on the result. There is no
/// non-suspending `surface` path — a timeout is always resolved by an explicit user
/// choice at the point of failure.
@MainActor
@Observable
final class TimeoutPauseGate {

    /// Non-nil while paused/awaiting the user. Drives the modal sheet.
    private(set) var pendingPause: TimeoutPauseInfo?

    @ObservationIgnored
    private var continuation: CheckedContinuation<TimeoutPauseResolution, Never>?

    // MARK: - Suspend

    /// Show the modal and suspend until the user resolves it. Supersedes any prior
    /// suspended pause (resolving the old one as `.abort`).
    func awaitResolution(_ info: TimeoutPauseInfo) async -> TimeoutPauseResolution {
        if let existing = continuation {
            existing.resume(returning: .abort)
            continuation = nil
            Logger.warning("⚠️ Superseded existing timeout pause continuation", category: .ai)
        }

        let resolution = await withCheckedContinuation { cont in
            continuation = cont
            pendingPause = info
            Logger.warning("⏱️ Analysis paused — \(info.filename) timed out (attempt \(info.attempt))", category: .ai)
        }

        continuation = nil
        pendingPause = nil
        return resolution
    }

    // MARK: - Resolve

    /// Resume a suspended pause (if any) and clear the modal. Called from the
    /// coordinator when the user picks Keep Waiting / Abort.
    func resolve(_ resolution: TimeoutPauseResolution) {
        Logger.info("⏱️ Timeout pause resolved: \(resolution)", category: .ai)
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: resolution)
            // `awaitResolution` clears `pendingPause` after it resumes.
        } else {
            pendingPause = nil
        }
    }

    /// Force-abort a pending pause (global Stop / session reset).
    func interrupt() {
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: .abort)
        }
        pendingPause = nil
    }

    /// Reset for a new session.
    func reset() { interrupt() }
}
