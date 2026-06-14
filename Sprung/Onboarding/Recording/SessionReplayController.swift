//
//  SessionReplayController.swift
//  Sprung
//
//  Drives RESTORE-TO-N then GO-LIVE for a recorded onboarding session.
//
//  Strategy (record-replay, not snapshot): re-drive the REAL forward pipeline from
//  the tape so every stream-derived side effect is reproduced by construction.
//    1. Install ReplayAnthropicService (serves recorded model streams by turn
//       order) + ReplayToolGateway (serves recorded tool results by callId, so
//       PDF ingestion / git agent / network tools never re-run).
//    2. Start a fresh interview — the orchestrator auto-sends the initial
//       "I'm ready to proceed" (turn 0), which the replay service serves.
//    3. Inject the remaining recorded user messages in TAPE ORDER, awaiting
//       quiescence between each, until the restore point (turn N).
//    4. GO LIVE: quiesce, then swap the real Anthropic service back and clear the
//       replay tool gateway. Steps after N hit the real API normally.
//
//  ┌─ RUNTIME-VALIDATION BOUNDARY ─────────────────────────────────────────────┐
//  │ The DATA PATH below this controller (recorder → store → replay services →   │
//  │ stream mirror) is unit-tested (RecordingReplayTests). The LIVE RE-DRIVE     │
//  │ here — injecting messages into the real turn loop + detecting quiescence    │
//  │ across the ~14 async transitions per turn — must be validated against an    │
//  │ actually-recorded session at runtime. The quiescence wait is BOUNDED by a   │
//  │ timeout so a mis-detection degrades to "continue/finish", never a hang.     │
//  │ Residual shared risk: the go-live handoff shares exposure with the          │
//  │ resumeSession restore path (re-subscribed streams, tool_choice, streaming   │
//  │ flags) — validate against those symptoms.                                   │
//  └───────────────────────────────────────────────────────────────────────────┘
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

@MainActor
final class SessionReplayController {

    enum ReplayControllerError: Error, LocalizedError {
        case noUserMessages(sessionId: String)
        case alreadyReplaying

        var errorDescription: String? {
            switch self {
            case .noUserMessages(let sessionId):
                return "Recorded session \(sessionId) has no user messages to replay."
            case .alreadyReplaying:
                return "A replay is already in progress."
            }
        }
    }

    // MARK: - Dependencies

    private let state: StateCoordinator
    private let eventBus: EventCoordinator
    private let llmFacade: LLMFacade?
    private let toolExecutionCoordinator: ToolExecutionCoordinator
    private let tapeStore: TapeStore
    /// Starts a fresh interview (the orchestrator sends the opening turn). Returns
    /// success. Injected as a closure so the controller doesn't depend on the
    /// lifecycle controller's private surface.
    private let startFreshInterview: () async -> Bool

    // MARK: - State

    private var isReplaying = false
    private var savedAnthropicService: AnthropicService?
    /// Latest observed LLM status / processing flag, maintained by the monitor
    /// tasks during a quiescence wait (MainActor-isolated, so reads are consistent).
    private var monitoredStatus: LLMStatus = .idle
    private var monitoredProcessing = false

    init(
        state: StateCoordinator,
        eventBus: EventCoordinator,
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

    /// Restore the recorded session up to and including model turn `targetTurnIndex`,
    /// then optionally go live. `goLive == false` is "replay/watch up to N" — the
    /// replay services stay installed so the next steps would also serve recorded
    /// data (used for inspection, not iteration).
    func restore(sessionId: String, throughTurnIndex targetTurnIndex: Int, goLive: Bool) async throws {
        guard !isReplaying else { throw ReplayControllerError.alreadyReplaying }
        isReplaying = true
        defer { isReplaying = false }

        // 1. Load the tape.
        let events = try await tapeStore.loadEvents(sessionId: sessionId)
        let modelStreams = try await tapeStore.loadModelStreams(sessionId: sessionId)
        let toolResults = try await tapeStore.loadToolResults(sessionId: sessionId)

        let userMessages: [TapeUserMessage] = events.compactMap {
            if case .userMessage(let message) = $0 { return message }
            return nil
        }
        guard !userMessages.isEmpty else {
            throw ReplayControllerError.noUserMessages(sessionId: sessionId)
        }

        // 2. Install replay services. Cap model streams to 0...N so a request past
        //    the restore point can't be served from the tape (it would mean we
        //    should already have gone live).
        let cappedStreams = modelStreams.filter { $0.key <= targetTurnIndex }
        let replayService = ReplayAnthropicService(modelStreams: cappedStreams)
        let gateway = ReplayToolGateway(toolResults: toolResults)
        savedAnthropicService = llmFacade?.currentAnthropicService()
        llmFacade?.registerAnthropicService(replayService)
        await toolExecutionCoordinator.setReplayToolGateway(gateway)
        Logger.info("⏪ Replay: restoring \(sessionId) through turn \(targetTurnIndex) (goLive: \(goLive))", category: .ai)

        // 3. Start a fresh interview — the orchestrator sends the opening turn,
        //    served by the replay service.
        _ = await startFreshInterview()
        await awaitQuiescence()

        // 4. Inject the remaining recorded user messages in order. The first is the
        //    system-generated opener the orchestrator already re-sent — skip it.
        //    Stop once a message belongs to a turn beyond the restore point.
        for message in userMessages.dropFirst() {
            if message.turnIndex > targetTurnIndex { break }
            await injectUserMessage(message)
            await awaitQuiescence()
        }

        // 5. Hand off.
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
        await eventBus.publish(.llm(.sendUserMessage(
            payload: payload,
            isSystemGenerated: message.isSystemGenerated
        )))
    }

    /// Wait until the current turn's async cascade settles — LLM idle, not
    /// processing, and no pending tool calls — held STABLE briefly so we don't
    /// catch the gap between a stream ending and its tool batch firing the next
    /// request. BOUNDED by `timeout`: on timeout we log and proceed (degrade to
    /// "continue", never hang).
    private func awaitQuiescence(timeout: Duration = .seconds(120)) async {
        monitoredStatus = .busy
        monitoredProcessing = true

        let statusTask = Task { @MainActor [weak self, eventBus] in
            for await event in await eventBus.stream(topic: .llm) {
                if case .llm(.status(let status)) = event { self?.monitoredStatus = status }
            }
        }
        let processingTask = Task { @MainActor [weak self, eventBus] in
            for await event in await eventBus.stream(topic: .processing) {
                if case .processing(.stateChanged(let isProcessing, _)) = event {
                    self?.monitoredProcessing = isProcessing
                }
            }
        }
        defer { statusTask.cancel(); processingTask.cancel() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var stableTicks = 0
        // Require ~360ms of continuous settle (3 ticks) before declaring quiescent.
        let requiredStableTicks = 3

        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(120))
            let log = await state.getConversationLog()
            let pendingTools = await log.hasPendingToolCalls
            if monitoredStatus == .idle, !monitoredProcessing, !pendingTools {
                stableTicks += 1
                if stableTicks >= requiredStableTicks { return }
            } else {
                stableTicks = 0
            }
        }
        Logger.warning("⏱️ Replay quiescence wait timed out after \(timeout) — proceeding", category: .ai)
    }
}
