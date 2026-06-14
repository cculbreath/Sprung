//
//  TapeEvent.swift
//  Sprung
//
//  The on-disk schema for a recorded onboarding session — the contract shared by
//  the recorder (SessionTapeRecorder) and the replay services
//  (ReplayAnthropicService / ReplayToolGateway).
//
//  A session is an append-only `tape.jsonl`: ONE `TapeEvent` per line, in capture
//  order. The first line is always a `.header`. Replay reads lines in order and
//  re-drives the REAL pipeline from them, so steps 0..N are reproduced for $0
//  (no API calls, no PDF parsing, no git agent) and the live API resumes only
//  after the restore point.
//
//  `turnIndex` is monotonic per MODEL REQUEST (assistant turn), starting at 0. It
//  is the strict key the replay services serve by — byte-stable request
//  reconstruction is NOT required, only ordering.
//

import Foundation

/// Tape format version — bump on any breaking schema change so old tapes can be
/// rejected rather than mis-replayed.
enum TapeSchema {
    static let version = 1
}

/// One line of a `tape.jsonl`.
enum TapeEvent: Codable, Sendable {
    /// First line of every tape: session identity + format version.
    case header(TapeHeader)
    /// A user (or system-generated) message that advances the conversation.
    case userMessage(TapeUserMessage)
    /// The request the live pipeline built for a model turn. ADVISORY ONLY —
    /// replay rebuilds the request itself; this is the divergence tripwire source.
    case request(TapeRequest)
    /// The exact ordered SSE the model produced for a turn — served verbatim by
    /// `ReplayAnthropicService` so the real forward path re-runs unchanged.
    case modelStream(TapeModelStream)
    /// A tool result, served verbatim by callId so PDF ingestion / git agent /
    /// network tools never re-run during replay.
    case toolResult(TapeToolResult)
    /// A wire-only coordinator turn (never shown in the UI transcript).
    case coordinatorTurn(TapeCoordinatorTurn)
    /// End-of-step structural fingerprint — ADVISORY tripwire only, never gates.
    case stateFingerprint(TapeStateFingerprint)

    // MARK: Codable (explicit discriminator for stable, inspectable JSONL)

    private enum CodingKeys: String, CodingKey {
        case kind, header, userMessage, request, modelStream, toolResult, coordinatorTurn, stateFingerprint
    }
    private enum Kind: String, Codable {
        case header, userMessage, request, modelStream, toolResult, coordinatorTurn, stateFingerprint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .header: self = .header(try c.decode(TapeHeader.self, forKey: .header))
        case .userMessage: self = .userMessage(try c.decode(TapeUserMessage.self, forKey: .userMessage))
        case .request: self = .request(try c.decode(TapeRequest.self, forKey: .request))
        case .modelStream: self = .modelStream(try c.decode(TapeModelStream.self, forKey: .modelStream))
        case .toolResult: self = .toolResult(try c.decode(TapeToolResult.self, forKey: .toolResult))
        case .coordinatorTurn: self = .coordinatorTurn(try c.decode(TapeCoordinatorTurn.self, forKey: .coordinatorTurn))
        case .stateFingerprint: self = .stateFingerprint(try c.decode(TapeStateFingerprint.self, forKey: .stateFingerprint))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .header(let v): try c.encode(Kind.header, forKey: .kind); try c.encode(v, forKey: .header)
        case .userMessage(let v): try c.encode(Kind.userMessage, forKey: .kind); try c.encode(v, forKey: .userMessage)
        case .request(let v): try c.encode(Kind.request, forKey: .kind); try c.encode(v, forKey: .request)
        case .modelStream(let v): try c.encode(Kind.modelStream, forKey: .kind); try c.encode(v, forKey: .modelStream)
        case .toolResult(let v): try c.encode(Kind.toolResult, forKey: .kind); try c.encode(v, forKey: .toolResult)
        case .coordinatorTurn(let v): try c.encode(Kind.coordinatorTurn, forKey: .kind); try c.encode(v, forKey: .coordinatorTurn)
        case .stateFingerprint(let v): try c.encode(Kind.stateFingerprint, forKey: .kind); try c.encode(v, forKey: .stateFingerprint)
        }
    }
}

// MARK: - Payloads

struct TapeHeader: Codable, Sendable {
    var sessionId: String
    var schemaVersion: Int
    /// ISO-8601 string (kept as a string so the tape never depends on a
    /// JSONDecoder date strategy).
    var recordedAt: String
    /// The Anthropic model id the live session used (advisory / informational).
    var modelId: String?
}

struct TapeUserMessage: Codable, Sendable {
    var turnIndex: Int
    var entryId: String
    var wireText: String
    var attachmentBase64: String?
    var attachmentMediaType: String?
    var isSystemGenerated: Bool
}

struct TapeRequest: Codable, Sendable {
    var turnIndex: Int
    /// CachePrefixAuditor-style prefix hash — advisory divergence tripwire.
    var prefixHash: String?
    /// Best-effort JSON dump of the request parameters (advisory / debugging only;
    /// never consumed by replay).
    var requestJSON: String?
}

struct TapeModelStream: Codable, Sendable {
    var turnIndex: Int
    /// The exact ordered SSE events for the turn, re-emitted verbatim on replay.
    var events: [RecordedStreamEvent]
}

struct TapeToolResult: Codable, Sendable {
    var turnIndex: Int
    var callId: String
    var name: String
    var argumentsJSON: String?
    /// The exact recorded tool output, served verbatim by `ReplayToolGateway`.
    var output: String
    /// `ToolCallStatus` raw value (e.g. "completed", "error").
    var status: String
}

struct TapeCoordinatorTurn: Codable, Sendable {
    var turnIndex: Int
    var text: String
    var anchorEntryId: String?
}

struct TapeStateFingerprint: Codable, Sendable {
    var turnIndex: Int
    /// Structural hash of the normalized ConversationLog wire snapshot + domain
    /// stores. Advisory only — the 📉 tripwire compares it, never gates replay.
    var hash: String
}
