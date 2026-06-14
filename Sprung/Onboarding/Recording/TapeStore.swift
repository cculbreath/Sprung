//
//  TapeStore.swift
//  Sprung
//
//  The READ layer for recorded onboarding sessions.
//
//  Responsibilities split across the tape subsystem:
//    • The recorder (SessionTapeRecorder) WRITES tapes and PRUNES the ring buffer
//      on start — `TapeStore` does neither.
//    • `TapeStore` ENUMERATES, READS, and offers a MANUAL `delete(_:)` for the UI.
//    • The replay services consume the decoded events; the convenience loaders
//      here (`loadModelStreams` / `loadToolResults`) give them a ready index.
//
//  Tapes are append-only `tape.jsonl` files (one `TapeEvent` per line). All reads
//  here are line-oriented and fault-tolerant: a single malformed line is logged
//  and skipped, never aborting the whole load — a partially-flushed recording is
//  still useful up to its last good line.
//
//  Isolation: an `actor` so the SwiftUI layer can enumerate/read/delete tapes
//  off the main thread without contending with the recorder's writes (the two
//  touch the same directory tree, but only the recorder mutates a live session).
//

import Foundation

/// Lightweight, list-friendly description of one recorded session. Derived from
/// the tape's header + a cheap pass over its lines so a SwiftUI list can render
/// without loading every event into memory.
struct TapeSessionSummary: Identifiable, Sendable, Hashable {
    /// Stable list identity — the on-disk session directory name.
    var id: String { sessionId }

    let sessionId: String
    /// ISO-8601 string from the header, if a header was present and parseable.
    let recordedAt: String?
    /// The Anthropic model id the live session used (advisory), if recorded.
    let modelId: String?
    /// Number of model request turns (`.modelStream` events) in the tape.
    let turnCount: Int
    /// Number of user / system-generated messages in the tape.
    let userMessageCount: Int
    /// Number of recorded tool results in the tape.
    let toolResultCount: Int
}

/// One restorable step in the UI's "restore to step N" list. One entry per user
/// message and per model turn, in tape order.
struct TapeStep: Identifiable, Sendable, Hashable {
    /// Composite identity so user-message and model steps that share a
    /// `turnIndex` remain distinct in a SwiftUI `ForEach`.
    var id: String { "\(turnIndex)-\(kind)" }

    /// The `turnIndex` this step restores to (monotonic per model request).
    let turnIndex: Int
    /// Short machine-readable step kind, e.g. `"userMessage"` / `"modelTurn"`.
    let kind: String
    /// Human-facing label for the step row.
    let label: String
}

/// Errors surfaced by the tape read layer.
enum TapeStoreError: Error, LocalizedError {
    case tapeMissing(sessionId: String)
    case tapeUnreadable(sessionId: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .tapeMissing(let sessionId):
            return "No tape file found for session \(sessionId)."
        case .tapeUnreadable(let sessionId, let underlying):
            return "Failed to read tape for session \(sessionId): \(underlying.localizedDescription)"
        }
    }
}

/// Reads, enumerates, and manually deletes recorded onboarding sessions on disk.
actor TapeStore {

    private let fileManager: FileManager
    private let decoder: JSONDecoder

    /// - Parameter fileManager: injected for testability; defaults to `.default`.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
    }

    // MARK: - Enumeration

    /// Enumerate every session directory under `RecordingPaths.recordingsRoot`
    /// that contains a tape file, sorted MOST RECENT FIRST.
    ///
    /// Recency uses the header's `recordedAt` when it parses as ISO-8601; sessions
    /// lacking a parseable header fall back to the tape file's modification date.
    /// Header-dated sessions always sort ahead of fallback-dated ones at equal
    /// timestamps, so a freshly written, fully-headered tape is never buried.
    func listSessions() -> [TapeSessionSummary] {
        let root = RecordingPaths.recordingsRoot
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            // Missing root simply means nothing has been recorded yet.
            return []
        }

        let iso = ISO8601DateFormatter()

        // Decorate each candidate with a sort key, then sort + project.
        var decorated: [(summary: TapeSessionSummary, sortDate: Date)] = []
        for directory in entries {
            let isDirectory = (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory else { continue }

            let sessionId = directory.lastPathComponent
            let tapeURL = RecordingPaths.tapeFile(sessionId)
            guard fileManager.fileExists(atPath: tapeURL.path) else { continue }

            let summary = summarize(sessionId: sessionId)

            let sortDate: Date
            if let recordedAt = summary.recordedAt, let parsed = iso.date(from: recordedAt) {
                sortDate = parsed
            } else {
                sortDate = (try? tapeURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
            }
            decorated.append((summary, sortDate))
        }

        return decorated
            .sorted { $0.sortDate > $1.sortDate }
            .map(\.summary)
    }

    // MARK: - Loading

    /// Read and decode every event in a session's tape, in tape order.
    ///
    /// Malformed lines are logged (`Logger.warning`) and skipped so a corrupt or
    /// partially-flushed line never discards the events that decoded cleanly.
    /// Throws only when the tape file itself cannot be located or read.
    func loadEvents(sessionId: String) throws -> [TapeEvent] {
        let tapeURL = RecordingPaths.tapeFile(sessionId)
        guard fileManager.fileExists(atPath: tapeURL.path) else {
            throw TapeStoreError.tapeMissing(sessionId: sessionId)
        }

        let contents: String
        do {
            contents = try String(contentsOf: tapeURL, encoding: .utf8)
        } catch {
            throw TapeStoreError.tapeUnreadable(sessionId: sessionId, underlying: error)
        }

        return decodeEvents(from: contents, sessionId: sessionId)
    }

    /// Index of model streams keyed by `turnIndex` — the replay request server's
    /// primary lookup. A later turn with a duplicate index (should not happen on a
    /// well-formed tape) overwrites the earlier one and is logged.
    func loadModelStreams(sessionId: String) throws -> [Int: TapeModelStream] {
        let events = try loadEvents(sessionId: sessionId)
        var streams: [Int: TapeModelStream] = [:]
        for case .modelStream(let stream) in events {
            if streams[stream.turnIndex] != nil {
                Logger.warning(
                    "Duplicate modelStream turnIndex \(stream.turnIndex) in tape; keeping the later one",
                    category: .ai,
                    metadata: ["sessionId": sessionId]
                )
            }
            streams[stream.turnIndex] = stream
        }
        return streams
    }

    /// Index of tool results keyed by `callId` — how `ReplayToolGateway` serves
    /// recorded tool output verbatim. A duplicate `callId` (should not happen)
    /// overwrites the earlier one and is logged.
    func loadToolResults(sessionId: String) throws -> [String: TapeToolResult] {
        let events = try loadEvents(sessionId: sessionId)
        var results: [String: TapeToolResult] = [:]
        for case .toolResult(let result) in events {
            if results[result.callId] != nil {
                Logger.warning(
                    "Duplicate toolResult callId \(result.callId) in tape; keeping the later one",
                    category: .ai,
                    metadata: ["sessionId": sessionId]
                )
            }
            results[result.callId] = result
        }
        return results
    }

    // MARK: - Step list

    /// Build the per-session restore step list — one entry per user message and
    /// per model turn, in tape order. Deterministic: it is a straight projection
    /// of `loadEvents`, no sorting or dedup.
    func steps(sessionId: String) throws -> [TapeStep] {
        let events = try loadEvents(sessionId: sessionId)
        var steps: [TapeStep] = []

        for event in events {
            switch event {
            case .userMessage(let message):
                let origin = message.isSystemGenerated ? "System message" : "You"
                let preview = Self.previewText(message.wireText)
                let label = preview.isEmpty ? origin : "\(origin): \(preview)"
                steps.append(TapeStep(turnIndex: message.turnIndex, kind: "userMessage", label: label))

            case .modelStream(let stream):
                steps.append(TapeStep(
                    turnIndex: stream.turnIndex,
                    kind: "modelTurn",
                    label: "Model turn \(stream.turnIndex)"
                ))

            case .header, .request, .toolResult, .coordinatorTurn, .stateFingerprint:
                // Not user-restorable steps; the UI restores to message / model
                // boundaries only.
                continue
            }
        }

        return steps
    }

    // MARK: - Deletion (manual, UI-driven)

    /// Remove a session directory and everything under it. Intended for an
    /// explicit UI delete action — the recorder owns scheduled ring-buffer
    /// pruning. Logs (never throws) on failure so a UI delete is best-effort.
    func delete(sessionId: String) {
        let directory = RecordingPaths.sessionDirectory(sessionId)
        guard fileManager.fileExists(atPath: directory.path) else {
            Logger.warning(
                "Requested delete of nonexistent session directory",
                category: .ai,
                metadata: ["sessionId": sessionId]
            )
            return
        }
        do {
            try fileManager.removeItem(at: directory)
            Logger.info(
                "Deleted recorded session",
                category: .ai,
                metadata: ["sessionId": sessionId]
            )
        } catch {
            Logger.error(
                "Failed to delete recorded session: \(error.localizedDescription)",
                category: .ai,
                metadata: ["sessionId": sessionId]
            )
        }
    }

    // MARK: - Private helpers

    /// Cheap single-pass summary: read the tape, decode the header (if any), and
    /// tally the event kinds the list needs. On read failure, returns an empty
    /// summary for the session so a broken tape still appears (and is deletable)
    /// in the UI rather than vanishing.
    private func summarize(sessionId: String) -> TapeSessionSummary {
        let events: [TapeEvent]
        do {
            events = try loadEvents(sessionId: sessionId)
        } catch {
            Logger.warning(
                "Failed to summarize tape; surfacing empty summary: \(error.localizedDescription)",
                category: .ai,
                metadata: ["sessionId": sessionId]
            )
            return TapeSessionSummary(
                sessionId: sessionId,
                recordedAt: nil,
                modelId: nil,
                turnCount: 0,
                userMessageCount: 0,
                toolResultCount: 0
            )
        }

        var recordedAt: String?
        var modelId: String?
        var turnCount = 0
        var userMessageCount = 0
        var toolResultCount = 0

        for event in events {
            switch event {
            case .header(let header):
                recordedAt = header.recordedAt
                modelId = header.modelId
            case .modelStream:
                turnCount += 1
            case .userMessage:
                userMessageCount += 1
            case .toolResult:
                toolResultCount += 1
            case .request, .coordinatorTurn, .stateFingerprint:
                continue
            }
        }

        return TapeSessionSummary(
            sessionId: sessionId,
            recordedAt: recordedAt,
            modelId: modelId,
            turnCount: turnCount,
            userMessageCount: userMessageCount,
            toolResultCount: toolResultCount
        )
    }

    /// Decode each non-empty line as a `TapeEvent`, skipping (with a warning) any
    /// line that fails to decode.
    private func decodeEvents(from contents: String, sessionId: String) -> [TapeEvent] {
        var events: [TapeEvent] = []
        var lineNumber = 0

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else {
                Logger.warning(
                    "Skipping tape line \(lineNumber): not valid UTF-8",
                    category: .ai,
                    metadata: ["sessionId": sessionId]
                )
                continue
            }
            do {
                events.append(try decoder.decode(TapeEvent.self, from: data))
            } catch {
                Logger.warning(
                    "Skipping malformed tape line \(lineNumber): \(error.localizedDescription)",
                    category: .ai,
                    metadata: ["sessionId": sessionId]
                )
            }
        }

        return events
    }

    /// Single-line, length-capped preview of a user message for the step label.
    private static func previewText(_ text: String, limit: Int = 60) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }
}
