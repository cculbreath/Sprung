//
//  ReplayAnthropicService.swift
//  Sprung
//
//  A record/replay stand-in for the live `AnthropicService` (SwiftOpenAI). During
//  replay of a recorded onboarding session, this conformer serves the EXACT model
//  streams captured on the tape so steps 0..N re-run for $0 — no API calls, no
//  network, no token counting, no file uploads.
//
//  HOW IT SERVES TURNS: model streams are served strictly by turn ORDER, not by
//  matching a reconstructed request. The live pipeline issues one model request
//  per assistant turn; this service hands back the recorded stream for the next
//  turn index each time `messagesStream(parameters:)` is called. Byte-stable
//  request reconstruction is therefore NOT required — only that the replayed
//  pipeline drives the same number of model requests in the same order, which the
//  recorder guarantees by construction.
//
//  DIVERGENCE TRIPWIRE: if the F1-2 integration supplies recorded request prefix
//  hashes, this service compares them advisory-only and logs a mismatch. It NEVER
//  throws on a hash mismatch — a divergent prefix is a debugging signal, not a
//  replay-fatal condition.
//
//  THE OTHER EIGHT METHODS: messages / listModels / retrieveModel / countTokens /
//  uploadFile / retrieveFileMetadata / listFiles / deleteFile all throw
//  `ReplayError.unsupported`. Replay must never touch the network, the Files API,
//  or token counting; reaching any of these during replay is a wiring bug that
//  should surface loudly rather than silently hit a live endpoint.
//

import Foundation
import SwiftOpenAI

/// Errors surfaced while replaying a recorded Anthropic session.
enum ReplayError: Error, LocalizedError {
    /// No recorded model stream exists for the requested turn index — the replay
    /// pipeline issued more model requests than the tape captured.
    case noRecordedTurn(Int)
    /// An operation that must never run during replay was invoked (any non-stream
    /// endpoint: messages, models, token counting, or files).
    case unsupported(operation: String)

    var errorDescription: String? {
        switch self {
        case .noRecordedTurn(let index):
            return "Replay has no recorded model stream for turn index \(index); "
                + "the replayed pipeline issued more model requests than were recorded."
        case .unsupported(let operation):
            return "Replay does not support '\(operation)'; this operation must never "
                + "run during replay (no network, no Files API, no token counting)."
        }
    }
}

/// Replays recorded model streams in place of the live `AnthropicService`.
///
/// An `actor` so the monotonic turn counter is mutated safely from any context the
/// replayed pipeline calls in on.
actor ReplayAnthropicService: AnthropicService {
    /// Recorded model streams keyed by turn index (monotonic per model request,
    /// starting at 0).
    private let modelStreams: [Int: TapeModelStream]

    /// Optional advisory map of recorded request prefix hashes, keyed by turn
    /// index. Used for divergence logging only — never to gate replay.
    private let recordedRequestHashes: [Int: String]

    /// Next turn index to serve. Incremented on every `messagesStream` call.
    private var nextTurnIndex = 0

    /// - Parameters:
    ///   - modelStreams: Recorded turns keyed by monotonic turn index.
    ///   - recordedRequestHashes: Advisory prefix hashes for divergence logging.
    init(modelStreams: [Int: TapeModelStream], recordedRequestHashes: [Int: String] = [:]) {
        self.modelStreams = modelStreams
        self.recordedRequestHashes = recordedRequestHashes
    }

    // MARK: - Messages (Streaming) — the only replayed path

    func messagesStream(
        parameters: AnthropicMessageParameter
    ) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        // Take the next turn index by ORDER and advance the counter.
        let index = nextTurnIndex
        nextTurnIndex += 1

        guard let recordedTurn = modelStreams[index] else {
            Logger.error(
                "Replay: no recorded model stream for turn index \(index)",
                category: .ai
            )
            throw ReplayError.noRecordedTurn(index)
        }

        // Advisory divergence tripwire — compare prefix hashes if both available,
        // but NEVER throw on mismatch.
        if let recordedHash = recordedRequestHashes[index] {
            let liveHash = Self.advisoryPrefixHash(for: parameters)
            if liveHash != recordedHash {
                Logger.info(
                    "Replay: request prefix hash mismatch at turn \(index) "
                        + "(recorded=\(recordedHash) live=\(liveHash)) — advisory only, replay continues",
                    category: .ai
                )
            }
        }

        let events = recordedTurn.events
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for recorded in events {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        // Decode through the REAL library decoder — the same path a
                        // live response takes — so there is no second reconstruction
                        // path to drift from production.
                        let event = try recorded.decoded()
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    Logger.error(
                        "Replay: failed to decode recorded stream event at turn \(index): "
                            + "\(error.localizedDescription)",
                        category: .ai
                    )
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Unsupported operations (must never run during replay)

    func messages(parameters: AnthropicMessageParameter) async throws -> AnthropicMessageResponse {
        throw ReplayError.unsupported(operation: "messages")
    }

    func listModels() async throws -> AnthropicModelsResponse {
        throw ReplayError.unsupported(operation: "listModels")
    }

    func retrieveModel(id: String) async throws -> AnthropicModel {
        throw ReplayError.unsupported(operation: "retrieveModel")
    }

    func countTokens(parameters: AnthropicTokenCountParameter) async throws -> AnthropicTokenCountResponse {
        throw ReplayError.unsupported(operation: "countTokens")
    }

    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> AnthropicFileMetadata {
        throw ReplayError.unsupported(operation: "uploadFile")
    }

    func retrieveFileMetadata(id: String) async throws -> AnthropicFileMetadata {
        throw ReplayError.unsupported(operation: "retrieveFileMetadata")
    }

    func listFiles() async throws -> AnthropicFileListResponse {
        throw ReplayError.unsupported(operation: "listFiles")
    }

    func deleteFile(id: String) async throws -> AnthropicFileDeletedResponse {
        throw ReplayError.unsupported(operation: "deleteFile")
    }

    // MARK: - Helpers

    /// Cheap, stable advisory hash of a request's salient prefix for divergence
    /// logging. NOT a security hash and NOT a replay gate — it only needs to be
    /// deterministic for the same inputs so a drift between record and replay is
    /// visible in the logs. Captures the model id plus the wire text of every
    /// message block, which is the part of the request the recorder anchors on.
    private static func advisoryPrefixHash(for parameters: AnthropicMessageParameter) -> String {
        var hasher = Hasher()
        hasher.combine(parameters.model)
        for message in parameters.messages {
            hasher.combine(message.role)
            switch message.content {
            case .text(let text):
                hasher.combine(text)
            case .blocks(let blocks):
                for block in blocks {
                    hasher.combine(String(describing: block))
                }
            }
        }
        return String(hasher.finalize())
    }
}
