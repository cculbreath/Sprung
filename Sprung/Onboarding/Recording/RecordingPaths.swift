//
//  RecordingPaths.swift
//  Sprung
//
//  Filesystem layout shared by the tape recorder (writes) and the tape store
//  (enumerates / prunes / reads):
//
//    ~/Library/Application Support/Sprung/Recordings/<sessionId>/tape.jsonl
//
//  Tapes are FILES, not SwiftData — they embed full document text and raw SSE,
//  so they are large. A ring buffer keeps only the most recent `maxSessions`.
//

import Foundation

enum RecordingPaths {
    /// Filename for a session's append-only event log.
    static let tapeFileName = "tape.jsonl"

    /// Ring-buffer size: only the most recent N sessions are retained; older
    /// session directories are pruned when a new recording starts.
    static let maxSessions = 5

    /// Root directory for all recordings (created on demand by callers). Falls
    /// back to a temp directory if Application Support is unavailable, matching
    /// the existing `OnboardingUploadStorage` pattern.
    static var recordingsRoot: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Sprung/Recordings", isDirectory: true)
    }

    /// Per-session directory under an explicit root (injected for testing).
    static func sessionDirectory(_ sessionId: String, in root: URL) -> URL {
        root.appendingPathComponent(sessionId, isDirectory: true)
    }

    /// Per-session append-only tape file under an explicit root.
    static func tapeFile(_ sessionId: String, in root: URL) -> URL {
        sessionDirectory(sessionId, in: root).appendingPathComponent(tapeFileName, isDirectory: false)
    }
}
