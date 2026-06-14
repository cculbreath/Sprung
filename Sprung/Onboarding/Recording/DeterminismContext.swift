//
//  DeterminismContext.swift
//  Sprung
//
//  The id seam that makes onboarding record-replay deterministic.
//
//  WHY THIS EXISTS
//  Replay re-drives the REAL forward pipeline from the tape. Most tool results are
//  served verbatim (PDF ingestion, git agent, network/LLM tools must never re-run),
//  but the pure-local state-building tools (timeline / section / publication cards,
//  web + writing-sample artifacts, dossier notes, todo list) are RE-EXECUTED during
//  replay so they rebuild the domain state WorkingMemoryBuilder injects into the
//  model's context (an empty timeline at go-live would be a divergent context).
//
//  Those tools are pure functions of (tool-call args, minted UUIDs): the args come
//  from the recorded stream, so the ONLY nondeterministic input is the UUID each
//  mints. A handful of those minted ids are returned to the model AND referenced by
//  a LATER recorded tool call ("update card X"). If re-execution minted a fresh id,
//  that later "update X" would miss. This seam removes that one nondeterminism:
//  during a recording run it MINTS real UUIDs and buffers them; during replay it
//  SERVES the buffered sequence back, so re-created entities keep the exact ids the
//  recording produced — making re-execution byte-identical to the original run.
//
//  SCOPE: only mint sites whose id is (a) returned to the model and (b) referenced
//  by a later recorded tool call must route through `DeterminismIDProvider`. See its
//  call sites (timeline / section / publication card services + the two artifact
//  tools). Everything else (internal-only ids, Date()s that never reach the model)
//  is irrelevant to context fidelity and is left alone.
//

import Foundation

/// Per-tool-call id source. Bound as a task-local for the dynamic extent of a
/// single `tool.execute()` so mints anywhere in that call tree (the tool itself or
/// the actor services it awaits) flow through the same scope.
///
/// `@unchecked Sendable`: the mutable buffer is guarded by `lock`. Within one tool
/// call mints are effectively sequential, but the lock keeps it correct even if a
/// service hops actors mid-call.
final class DeterminismContext: @unchecked Sendable {
    enum Mode {
        /// Live or recording run: mint real UUIDs and remember them in order.
        case recording
        /// Replay run: hand back the recorded sequence in order.
        case replaying([String])
    }

    private let lock = NSLock()
    private let mode: Mode
    private var minted: [String] = []
    private var cursor = 0
    private var exhausted = false

    init(mode: Mode) { self.mode = mode }

    /// Produce the next id for this scope.
    func nextUUID() -> String {
        lock.lock(); defer { lock.unlock() }
        switch mode {
        case .recording:
            let id = UUID().uuidString
            minted.append(id)
            return id
        case .replaying(let sequence):
            guard cursor < sequence.count else {
                // Re-execution asked for MORE ids than the recording produced — a
                // divergence (e.g. a new mint site not yet routed through the seam,
                // or changed tool behavior). Mint fresh so execution proceeds, but
                // flag it so the caller can emit the advisory tripwire.
                exhausted = true
                return UUID().uuidString
            }
            let id = sequence[cursor]
            cursor += 1
            return id
        }
    }

    /// Ids minted during a `.recording` scope, in order. Empty for a replay scope.
    var mintedIds: [String] {
        lock.lock(); defer { lock.unlock() }
        return minted
    }

    /// True if a `.replaying` scope ran out of recorded ids — advisory divergence
    /// signal, never gates replay.
    var didExhaust: Bool {
        lock.lock(); defer { lock.unlock() }
        return exhausted
    }
}

/// Task-local binding for the active determinism scope.
enum DeterminismScope {
    @TaskLocal static var current: DeterminismContext?
}

/// The single id seam the onboarding state-building tools mint through.
///
/// When a determinism scope is active (any tool executing under record or replay)
/// ids flow through it; otherwise a plain UUID is minted. Centralizing the
/// "is a scope active?" decision here keeps every call site a drop-in replacement
/// for `UUID().uuidString` (no per-site branching). The plain-mint path is the
/// genuine default for code paths outside tool execution — not a record/replay
/// fallback.
enum DeterminismIDProvider {
    static func nextUUID() -> String {
        DeterminismScope.current?.nextUUID() ?? UUID().uuidString
    }
}
