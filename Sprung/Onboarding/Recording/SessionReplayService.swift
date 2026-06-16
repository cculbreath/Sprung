//
//  SessionReplayService.swift
//  Sprung
//
//  Drives RESTORE-TO-N then GO-LIVE for a recorded onboarding session.
//
//  Strategy (record-replay, not snapshot): re-drive the REAL forward pipeline from
//  the tape so every stream-derived side effect is reproduced by construction.
//    1. Install ReplayAnthropicService (serves recorded model streams by turn
//       order) + ReplayToolGateway. The gateway serves external / IO / LLM tools
//       verbatim by callId (PDF ingestion / git agent / network never re-run) and
//       RE-EXECUTES the pure-local state-building tools so the domain state
//       WorkingMemoryBuilder injects into the model's context (timeline, artifact
//       summaries, dossier, todo) is rebuilt for real — not left empty at go-live.
//       Re-executed tools mint through the determinism seam seeded with the recorded
//       ids (DeterminismContext), so a later "update card X" still hits card X.
//    2. Start a fresh interview. The orchestrator auto-sends the opener, and the
//       recorded SYSTEM-GENERATED messages (phase transitions, etc.) re-fire on
//       their own as the replayed tool calls drive them — so the controller
//       injects ONLY the USER-TYPED messages, in order, and lets the pipeline
//       regenerate everything else. (This is why we never double-send the opener.)
//    3. Inject the first N user-typed messages, awaiting quiescence between each.
//    4. GO LIVE: swap the real Anthropic service back and clear the replay gateway.
//
//  ┌─ RUNTIME-VALIDATION BOUNDARY ─────────────────────────────────────────────┐
//  │ The DATA PATH below this controller (recorder → store → replay services →   │
//  │ stream mirror) is unit-tested. The LIVE RE-DRIVE here must be validated      │
//  │ against an actually-recorded session. Defenses against the known failure     │
//  │ modes found in adversarial review are in place: (a) only user-typed messages │
//  │ are injected; (b) a replay error (e.g. a turn-count desync surfacing as       │
//  │ llm.status(.error)) ABORTS + rolls back instead of silently going live onto   │
//  │ a corrupt session; (c) the quiescence gate waits for the turn to actually     │
//  │ START (busy) before waiting for it to settle (idle), and subscribes BEFORE    │
//  │ driving so no transition is missed; (d) recording is suppressed during        │
//  │ replay so the lifecycle doesn't stack a recording decorator over the replay   │
//  │ service. NOTE: the per-turn model-request COUNT is deterministic — the tool   │
//  │ batcher waits for ALL slots (count-based, not timed) and emits exactly one     │
//  │ follow-up per turn; late results tail-deliver with no extra request — so       │
//  │ zero-latency replay issues the same request sequence as the real run and the   │
//  │ turn counter cannot desync from batching. The error-abort (below) is           │
//  │ defense-in-depth against the rare residual (e.g. a stream-retry edge case).    │
//  └───────────────────────────────────────────────────────────────────────────┘
//
//  DOMAIN-STATE SETTLE: re-executed state-building tools rebuild domain state by
//  emitting events (cardCreated, …) that subscribers apply asynchronously. A single
//  AsyncStream delivers in yield order, so a create is always applied before the
//  update that references it (no intra-cascade id miss). The two-phase quiescence
//  gate (idle + no pending tools, held stable ~360ms) drains that fast in-memory
//  buffer before go-live; this is the same settle mechanism the rest of replay
//  relies on. If runtime validation surfaces a residual race, strengthen the gate
//  with an explicit domain-event fence rather than a longer fixed sleep.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

@MainActor
final class SessionReplayService {

    enum ReplayControllerError: Error, LocalizedError {
        case noUserMessages(sessionId: String)
        case alreadyReplaying
        case replayDesync

        var errorDescription: String? {
            switch self {
            case .noUserMessages(let sessionId):
                return "Recorded session \(sessionId) has no user-typed messages to replay."
            case .alreadyReplaying:
                return "A replay is already in progress."
            case .replayDesync:
                return "Replay diverged from the recording (the pipeline issued a turn the tape did not contain) — aborted before going live."
            }
        }
    }

    // MARK: - Dependencies

    private let state: StateCoordinator
    private let eventBus: EventBus
    private let llmFacade: LLMFacade?
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    private let tapeStore: TapeStore
    private let startFreshInterview: () async -> Bool

    // MARK: - State

    private var isReplaying = false
    private var savedAnthropicService: AnthropicService?
    private var monitoredStatus: LLMStatus = .idle
    private var monitoredProcessing = false
    /// Set by the monitor when the replay pipeline emits an error — meaning the
    /// re-drive diverged from the tape. Aborts the restore before go-live.
    private var replayDidError = false
    private var monitorTasks: [Task<Void, Never>] = []

    init(
        state: StateCoordinator,
        eventBus: EventBus,
        llmFacade: LLMFacade?,
        toolExecutionCoordinator: ToolExecutionCoordinator,
        tapeStore: TapeStore = TapeStore(),
        startFreshInterview: @escaping () async -> Bool
    ) {
        self.state = state
        self.eventBus = eventBus
        self.llmFacade = llmFacade
        self.toolExecutionCoordinator = toolExecutionCoordinator
        self.tapeStore = tapeStore
        self.startFreshInterview = startFreshInterview
    }

    // MARK: - Public API

    /// Restore the recorded session by re-driving the first `throughUserMessageOrdinal`
    /// USER-TYPED messages (their full turn-chains served from the tape), then
    /// optionally go live. Aborts + rolls back if the re-drive diverges from the tape.
    func restore(sessionId: String, throughUserMessageOrdinal ordinal: Int, goLive: Bool) async throws {
        guard !isReplaying else { throw ReplayControllerError.alreadyReplaying }
        isReplaying = true
        defer { isReplaying = false }

        // 1. Load the tape (model streams UNCAPPED — we stop by ceasing injection,
        //    not by capping the server, so a turn is never refused mid-chain).
        let events = try await tapeStore.loadEvents(sessionId: sessionId)
        let modelStreams = try await tapeStore.loadModelStreams(sessionId: sessionId)
        let toolResults = try await tapeStore.loadToolResults(sessionId: sessionId)

        // Inject ONLY user-typed messages; system-generated ones (opener, phase
        // transitions) re-fire on their own during replay.
        let userTyped: [TapeUserMessage] = events.compactMap {
            if case .userMessage(let message) = $0, !message.isSystemGenerated { return message }
            return nil
        }
        guard !userTyped.isEmpty else {
            throw ReplayControllerError.noUserMessages(sessionId: sessionId)
        }

        // 2. Install replay services BEFORE starting the interview so the opener
        //    turn is served from the tape. Recording is suppressed by the caller.
        let replayService = ReplayAnthropicService(modelStreams: modelStreams)
        let gateway = ReplayToolGateway(toolResults: toolResults)
        savedAnthropicService = llmFacade?.currentAnthropicService()
        llmFacade?.registerAnthropicService(replayService)
        await toolExecutionCoordinator.setReplayToolGateway(gateway)
        Logger.info("⏪ Replay: restoring \(sessionId) through user message \(ordinal) (goLive: \(goLive))", category: .ai)

        // 3. Start the monitors BEFORE driving so no busy/idle/error transition is
        //    missed (the event streams are future-only).
        startMonitors()
        defer { stopMonitors() }

        // 4. Start a fresh interview — the orchestrator sends the opener, served
        //    from the tape — then drive the user-typed messages in order.
        _ = await startFreshInterview()
        await awaitTurnQuiescence()

        for message in userTyped.prefix(max(0, ordinal)) {
            if replayDidError { break }
            await injectUserMessage(message)
            await awaitTurnQuiescence()
        }

        // 5. Hand off — or abort + roll back on divergence.
        if replayDidError {
            await swapToLiveService()   // restore the real service so the session is usable
            throw ReplayControllerError.replayDesync
        }
        if goLive {
            await swapToLiveService()
        } else {
            Logger.info("⏪ Replay complete (watch mode) for \(sessionId) — replay services remain installed", category: .ai)
        }
    }

    /// Swap the live Anthropic service back and clear the replay tool gateway, so
    /// subsequent turns hit the real API and real tools. Safe to call repeatedly.
    func swapToLiveService() async {
        if let real = savedAnthropicService {
            llmFacade?.registerAnthropicService(real)
        }
        savedAnthropicService = nil
        await toolExecutionCoordinator.setReplayToolGateway(nil)
        Logger.info("⏩ Replay go-live: real Anthropic service + tools restored", category: .ai)
    }

    // MARK: - Drive

    private func injectUserMessage(_ message: TapeUserMessage) async {
        var payload = JSON()
        payload["text"].string = message.wireText
        await eventBus.publish(.llm(.sendUserMessage(payload: payload, isSystemGenerated: false)))
    }

    // MARK: - Monitors

    private func startMonitors() {
        monitoredStatus = .idle
        monitoredProcessing = false
        replayDidError = false
        let llmTask = Task { @MainActor [weak self, eventBus] in
            for await event in await eventBus.stream(topic: .llm) {
                guard let self else { return }
                if case .llm(.status(let status)) = event {
                    self.monitoredStatus = status
                    if status == .error { self.replayDidError = true }
                }
            }
        }
        let procTask = Task { @MainActor [weak self, eventBus] in
            for await event in await eventBus.stream(topic: .processing) {
                guard let self else { return }
                switch event {
                case .processing(.stateChanged(let isProcessing, _)):
                    self.monitoredProcessing = isProcessing
                case .processing(.errorOccurred):
                    self.replayDidError = true
                default:
                    break
                }
            }
        }
        monitorTasks = [llmTask, procTask]
    }

    private func stopMonitors() {
        for task in monitorTasks { task.cancel() }
        monitorTasks = []
    }

    // MARK: - Quiescence

    /// Two-phase wait for one turn's cascade. Phase 1: wait until the turn has
    /// actually STARTED (busy / processing / pending tools) so we never mistake the
    /// PREVIOUS turn's trailing idle for "settled". Phase 2: wait until it settles
    /// (idle + not processing + no pending tools, held stable). Both bounded — on
    /// timeout we proceed (degrade to "continue", never hang). Returns early if the
    /// replay has diverged (the caller then aborts).
    private func awaitTurnQuiescence(startTimeout: Duration = .seconds(10),
                                     settleTimeout: Duration = .seconds(120)) async {
        let clock = ContinuousClock()

        // Phase 1: turn start.
        let startDeadline = clock.now.advanced(by: startTimeout)
        while clock.now < startDeadline {
            if replayDidError { return }
            if monitoredStatus == .busy || monitoredProcessing { break }
            let pending = await pendingToolCalls()
            if pending { break }
            try? await Task.sleep(for: .milliseconds(80))
        }

        // Phase 2: settle.
        let settleDeadline = clock.now.advanced(by: settleTimeout)
        var stableTicks = 0
        let requiredStableTicks = 3   // ~360ms continuous settle
        while clock.now < settleDeadline {
            if replayDidError { return }
            try? await Task.sleep(for: .milliseconds(120))
            let pending = await pendingToolCalls()
            if monitoredStatus == .idle, !monitoredProcessing, !pending {
                stableTicks += 1
                if stableTicks >= requiredStableTicks { return }
            } else {
                stableTicks = 0
            }
        }
        Logger.warning("⏱️ Replay quiescence wait timed out — proceeding", category: .ai)
    }

    private func pendingToolCalls() async -> Bool {
        let log = await state.getConversationLog()
        return await log.hasPendingToolCalls
    }
}
