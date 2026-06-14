//
//  SessionTapeRecorder.swift
//  Sprung
//
//  The RECORD side of the onboarding "tape recorder".
//
//  This is a PUSH-BASED recorder: it does NOT subscribe to the event bus.
//  Callers (the F1-2 integration layer) push events into it as the live
//  interview runs. The recorder owns the append-only `tape.jsonl` file, the
//  ring-buffer pruning of old sessions, and the monotonic per-model-request
//  turn index.
//
//  It is an `actor` so concurrent pushes from the streaming decorator, the
//  coordinator, the tool gateway, and the UI thread serialize safely onto a
//  single file handle. A recording failure must NEVER crash the live
//  interview — every append is best-effort and logged on failure.
//
//  TURN-INDEX OWNERSHIP: `nextModelTurnIndex()` is the single source of truth
//  for the monotonic assistant-turn counter (starts at 0). The streaming
//  decorator calls it once per model request to claim that turn's index, which
//  also advances `currentTurnIndex` so user / tool / coordinator / fingerprint
//  events that follow are stamped with the in-progress turn.
//

import Foundation

/// Append-only recorder for a single onboarding session's tape.
///
/// Lifecycle: `start(sessionId:modelId:)` → many `record*` pushes → `stop()`.
/// All `record*` methods are no-ops while not recording, so callers can wire
/// them unconditionally.
actor SessionTapeRecorder {

    // MARK: - State

    /// Whether recording is currently active. When `false`, every `record*`
    /// method returns immediately without touching the filesystem.
    private(set) var isRecording = false

    /// The session currently being recorded, if any.
    private var sessionId: String?

    /// The open append handle for the current session's tape file.
    private var fileHandle: FileHandle?

    /// Monotonic counter for the NEXT model-request turn index to hand out.
    /// `nextModelTurnIndex()` returns the current value then advances this.
    private var nextTurnIndex = 0

    /// The in-progress turn index used to stamp non-model events (user / tool /
    /// coordinator / fingerprint). `-1` until the first model turn is claimed.
    private var currentTurnIndex = -1

    /// Encoder for one-event-per-line JSONL. No pretty printing — each event
    /// must serialize to a single physical line.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Root directory recordings are written under. Defaults to the shared
    /// `RecordingPaths.recordingsRoot`; injected to a temp dir in tests so a test
    /// run never prunes the user's real recordings.
    private let recordingsRoot: URL

    init(recordingsRoot: URL = RecordingPaths.recordingsRoot) {
        self.recordingsRoot = recordingsRoot
    }

    // MARK: - Lifecycle

    /// Begin recording a new session.
    ///
    /// Creates the session directory, prunes old sessions down to
    /// `RecordingPaths.maxSessions` (oldest pruned first, by directory date),
    /// opens/creates the tape file, and writes the `.header` line.
    ///
    /// - Parameters:
    ///   - sessionId: Stable identifier for this onboarding session.
    ///   - modelId: The Anthropic model id the live session uses (advisory).
    func start(sessionId: String, modelId: String?) {
        // If a previous session is somehow still open, close it cleanly first.
        if isRecording {
            stop()
        }

        let fileManager = FileManager.default
        let sessionDirectory = RecordingPaths.sessionDirectory(sessionId, in: recordingsRoot)
        let tapeFile = RecordingPaths.tapeFile(sessionId, in: recordingsRoot)

        do {
            // Ensure the recordings root exists before pruning enumerates it.
            try fileManager.createDirectory(
                at: recordingsRoot,
                withIntermediateDirectories: true
            )

            // Prune older sessions so at most `maxSessions` remain once this new
            // one is added. We reserve a slot for the session about to start.
            pruneOldSessions(keeping: max(0, RecordingPaths.maxSessions - 1),
                             excluding: sessionId,
                             fileManager: fileManager)

            try fileManager.createDirectory(
                at: sessionDirectory,
                withIntermediateDirectories: true
            )

            // Create the tape file if it does not yet exist, then open for append.
            if !fileManager.fileExists(atPath: tapeFile.path) {
                fileManager.createFile(atPath: tapeFile.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: tapeFile)
            try handle.seekToEnd()

            self.fileHandle = handle
            self.sessionId = sessionId
            self.nextTurnIndex = 0
            self.currentTurnIndex = -1
            self.isRecording = true

            let header = TapeHeader(
                sessionId: sessionId,
                schemaVersion: TapeSchema.version,
                recordedAt: SessionTapeRecorder.iso8601Now(),
                modelId: modelId
            )
            append(.header(header))

            Logger.info("🎙️ Tape recording started for session \(sessionId)", category: .ai)
        } catch {
            // Failure to start recording must not affect the live interview.
            self.fileHandle = nil
            self.sessionId = nil
            self.isRecording = false
            Logger.warning(
                "Failed to start tape recording for session \(sessionId): \(error.localizedDescription)",
                category: .ai
            )
        }
    }

    /// Stop recording: flush and close the tape file. Idempotent.
    func stop() {
        guard isRecording || fileHandle != nil else { return }
        isRecording = false
        if let handle = fileHandle {
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                Logger.warning(
                    "Failed to close tape file cleanly: \(error.localizedDescription)",
                    category: .ai
                )
            }
        }
        fileHandle = nil
        let endedSession = sessionId
        sessionId = nil
        if let endedSession {
            Logger.info("🛑 Tape recording stopped for session \(endedSession)", category: .ai)
        }
    }

    // MARK: - Turn-index ownership

    /// Claim and return the next monotonic model-request turn index.
    ///
    /// The streaming decorator calls this once per model request. It both
    /// returns the turn's index AND advances `currentTurnIndex` so subsequent
    /// non-model events are stamped with this in-progress turn.
    func nextModelTurnIndex() -> Int {
        let index = nextTurnIndex
        nextTurnIndex += 1
        currentTurnIndex = index
        return index
    }

    /// Roll back a claimed-but-unused turn index (the stream failed before it
    /// produced a recordable turn). Only rolls back when no later turn has been
    /// claimed (onboarding model requests are sequential), so a retry reuses the
    /// same contiguous index and the recorded turn space matches the SUCCESSFUL
    /// requests the live pipeline issued.
    func discardClaimedModelTurn(_ index: Int) {
        guard nextTurnIndex == index + 1 else { return }
        nextTurnIndex = index
        currentTurnIndex = index - 1
    }

    // MARK: - Append methods

    /// Record a user (or system-generated) message advancing the conversation.
    func recordUserMessage(
        entryId: String,
        wireText: String,
        attachmentBase64: String?,
        attachmentMediaType: String?,
        isSystemGenerated: Bool
    ) {
        guard isRecording else { return }
        append(.userMessage(TapeUserMessage(
            turnIndex: currentTurnIndex,
            entryId: entryId,
            wireText: wireText,
            attachmentBase64: attachmentBase64,
            attachmentMediaType: attachmentMediaType,
            isSystemGenerated: isSystemGenerated
        )))
    }

    /// Record the request a model turn was built from (advisory only).
    func recordRequest(turnIndex: Int, prefixHash: String?, requestJSON: String?) {
        guard isRecording else { return }
        append(.request(TapeRequest(
            turnIndex: turnIndex,
            prefixHash: prefixHash,
            requestJSON: requestJSON
        )))
    }

    /// Record the exact ordered SSE stream a model turn produced.
    func recordModelStream(turnIndex: Int, events: [RecordedStreamEvent]) {
        guard isRecording else { return }
        append(.modelStream(TapeModelStream(
            turnIndex: turnIndex,
            events: events
        )))
    }

    /// Record a tool result, served verbatim by callId on replay. `mintedIds` are
    /// the determinism-seam ids captured during execution (replayed back when a
    /// re-executable tool is re-run during replay); empty is normalized to nil so
    /// no-mint tools keep a clean tape line.
    func recordToolResult(
        callId: String,
        name: String,
        argumentsJSON: String?,
        output: String,
        status: String,
        mintedIds: [String]
    ) {
        guard isRecording else { return }
        append(.toolResult(TapeToolResult(
            turnIndex: currentTurnIndex,
            callId: callId,
            name: name,
            argumentsJSON: argumentsJSON,
            output: output,
            status: status,
            mintedIds: mintedIds.isEmpty ? nil : mintedIds
        )))
    }

    /// Record a wire-only coordinator turn (never shown in the UI transcript).
    func recordCoordinatorTurn(text: String, anchorEntryId: String?) {
        guard isRecording else { return }
        append(.coordinatorTurn(TapeCoordinatorTurn(
            turnIndex: currentTurnIndex,
            text: text,
            anchorEntryId: anchorEntryId
        )))
    }

    /// Record an end-of-step structural fingerprint (advisory tripwire).
    func recordFingerprint(hash: String) {
        guard isRecording else { return }
        append(.stateFingerprint(TapeStateFingerprint(
            turnIndex: currentTurnIndex,
            hash: hash
        )))
    }

    // MARK: - Private helpers

    /// Encode one event and append it as a single `<json>\n` line. Best-effort:
    /// on any failure, warn and continue — never throw into the live pipeline.
    private func append(_ event: TapeEvent) {
        guard let handle = fileHandle else {
            Logger.warning("Tape append skipped: no open tape file handle", category: .ai)
            return
        }
        do {
            var data = try encoder.encode(event)
            data.append(0x0A) // newline
            try handle.write(contentsOf: data)
        } catch {
            Logger.warning(
                "Failed to append tape event: \(error.localizedDescription)",
                category: .ai
            )
        }
    }

    /// Prune old session directories so that at most `keeping` remain after the
    /// excluded (about-to-start) session is added back. Oldest first, ranked by
    /// directory modification date (falling back to creation date).
    private func pruneOldSessions(
        keeping: Int,
        excluding excludedSessionId: String,
        fileManager: FileManager
    ) {
        let root = recordingsRoot
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentModificationDateKey,
            .creationDateKey
        ]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        // Existing session directories, excluding the one about to start.
        let sessions = contents.filter { url in
            guard url.lastPathComponent != excludedSessionId else { return false }
            let values = try? url.resourceValues(forKeys: resourceKeys)
            return values?.isDirectory == true
        }

        guard sessions.count > keeping else { return }

        // Sort oldest → newest so the oldest are dropped first.
        let sorted = sessions.sorted { lhs, rhs in
            date(for: lhs, fileManager: fileManager) < date(for: rhs, fileManager: fileManager)
        }

        let removeCount = sorted.count - keeping
        for directory in sorted.prefix(removeCount) {
            do {
                try fileManager.removeItem(at: directory)
                Logger.info(
                    "🧹 Pruned old recording session \(directory.lastPathComponent)",
                    category: .ai
                )
            } catch {
                Logger.warning(
                    "Failed to prune recording session \(directory.lastPathComponent): \(error.localizedDescription)",
                    category: .ai
                )
            }
        }
    }

    /// Best-effort ranking date for a session directory: modification date,
    /// falling back to creation date, falling back to the distant past so an
    /// undated directory sorts as oldest (and is pruned first).
    private func date(for url: URL, fileManager: FileManager) -> Date {
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey
        ])
        return values?.contentModificationDate ?? values?.creationDate ?? .distantPast
    }

    /// Current time as an ISO-8601 string (stored as a string so the tape never
    /// depends on a JSONDecoder date strategy).
    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
