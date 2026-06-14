//
//  ReplayToolGateway.swift
//  Sprung
//
//  Holds the recorded tool results during replay and classifies, per tool, how the
//  replayed call is satisfied:
//
//    • SERVED VERBATIM (the default) — external / IO / LLM tools never re-run: PDF
//      ingestion does not re-parse, the git agent does not re-clone, no network
//      tool fires. The recorded output is handed back exactly as captured.
//    • RE-EXECUTED (see `shouldReExecute`) — pure-local, deterministic, args-derived
//      state-building tools (timeline / section / publication cards, web + writing-
//      sample artifacts, dossier notes, todo list) are re-run for their side effects
//      so the domain state WorkingMemoryBuilder injects into the model's context is
//      rebuilt for real. They mint through the determinism seam seeded with the
//      recorded ids, so re-execution is byte-identical to the original run; the
//      recorded output is still returned for conversation-history fidelity.
//
//  KEYING IS EXACT: tool-call ids come from the replayed assistant turn — that
//  turn is itself served verbatim by `ReplayAnthropicService`, so the callIds the
//  pipeline asks about are byte-for-byte the ones the recorder captured. No fuzzy
//  matching or reconciliation is needed; a plain dictionary lookup by callId is
//  exact and sufficient.
//
//  F1-2 INTEGRATION: the tool-dispatch path consults this gateway during replay
//  BEFORE executing any real tool. The integration calls `recordedResult(callId:)`
//  (or first checks `hasRecordedResult(callId:)`) and, when a recorded
//  `TapeToolResult` is present, returns it instead of invoking the live tool. A
//  missing entry means the replayed turn requested a tool the tape never recorded
//  — the integration decides how to surface that; this gateway only reports
//  presence and serves what it has.
//

import Foundation

/// Serves recorded tool results keyed by tool-call id during replay.
///
/// `@MainActor` because the onboarding tool-dispatch path it plugs into runs on
/// the main actor; isolating here keeps lookups free of cross-actor hops in that
/// path. The recorded results are immutable after init, so this is purely a
/// read-only lookup table.
@MainActor
final class ReplayToolGateway {
    /// Recorded tool results keyed by tool-call id.
    private let toolResults: [String: TapeToolResult]

    /// - Parameter toolResults: Recorded results keyed by callId.
    init(toolResults: [String: TapeToolResult]) {
        self.toolResults = toolResults
    }

    /// Returns the recorded result for `callId`, or `nil` if the tape captured no
    /// result for that call. Lookup is exact — see the file header on why no
    /// reconciliation is needed.
    func recordedResult(callId: String) -> TapeToolResult? {
        toolResults[callId]
    }

    /// Whether a recorded result exists for `callId`. Convenience for the
    /// dispatch path to branch on before deciding to short-circuit a live tool.
    func hasRecordedResult(callId: String) -> Bool {
        toolResults[callId] != nil
    }

    /// Whether a tool is RE-EXECUTED (rather than served verbatim) during replay.
    ///
    /// Re-executable tools are pure, deterministic, args-derived local state
    /// mutations (no network / LLM / file IO) — re-running them with the
    /// determinism seam rebuilds the domain state WorkingMemoryBuilder injects into
    /// the model's context, byte-identically to the original run. Everything else
    /// (PDF/LLM extraction, git agent, network, user-prompt tools) stays served
    /// verbatim so it never re-runs. `nonisolated` so the `ToolExecutor` actor can
    /// consult it synchronously — it is a pure function of the tool name.
    nonisolated static func shouldReExecute(toolName: String) -> Bool {
        OnboardingToolName.replayReExecutableTools.contains(toolName)
    }
}
