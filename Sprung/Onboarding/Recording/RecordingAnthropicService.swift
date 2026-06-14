//
//  RecordingAnthropicService.swift
//  Sprung
//
//  The RECORD-side decorator for the onboarding "tape recorder".
//
//  Wraps a real `AnthropicService` and tees the model stream into a
//  `SessionTapeRecorder` while passing every event downstream UNCHANGED. The
//  downstream pipeline must observe EXACTLY the same events, in the same order,
//  as it would without the decorator — recording is a pure side effect.
//
//  Only `messagesStream` is intercepted (that is the conversational, replayable
//  path). The other eight `AnthropicService` requirements delegate straight to
//  the wrapped service; the tool side of the tape is captured elsewhere.
//
//  F1-2 installs this via `registerAnthropicService`. The class itself is
//  uninstalled by design but compiles standalone.
//

import Foundation
import SwiftOpenAI

/// A transparent recording decorator over an `AnthropicService`.
final class RecordingAnthropicService: AnthropicService {

    /// The real service all calls ultimately delegate to.
    private let wrapped: AnthropicService

    /// The push-based tape recorder this decorator tees the stream into.
    private let recorder: SessionTapeRecorder

    /// JSON encoder for the advisory request dump. Best-effort only — failure
    /// to encode simply yields `nil` request JSON.
    private let requestEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// - Parameters:
    ///   - wrapping: The real `AnthropicService` to delegate to.
    ///   - recorder: The recorder that captures the teed model stream.
    init(wrapping wrapped: AnthropicService, recorder: SessionTapeRecorder) {
        self.wrapped = wrapped
        self.recorder = recorder
    }

    // MARK: - Streaming (intercepted)

    func messagesStream(
        parameters: AnthropicMessageParameter
    ) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        // Claim this model request's monotonic turn index up front so the tape's
        // request + modelStream events agree, and so non-model events that follow
        // are stamped with this turn.
        let turnIndex = await recorder.nextModelTurnIndex()

        // Advisory request dump — never consumed by replay, used only as a
        // divergence tripwire / debugging aid. Best-effort; nil on failure.
        let requestJSON = encodeRequest(parameters)
        await recorder.recordRequest(turnIndex: turnIndex, prefixHash: nil, requestJSON: requestJSON)

        // Open the real upstream stream. Any error here propagates to the caller
        // exactly as without the decorator (nothing to record yet).
        let upstream = try await wrapped.messagesStream(parameters: parameters)

        let recorder = self.recorder
        return AsyncThrowingStream<AnthropicStreamEvent, Error> { continuation in
            let task = Task {
                var collected: [RecordedStreamEvent] = []
                do {
                    for try await event in upstream {
                        // Capture, then forward UNCHANGED — order preserved.
                        collected.append(RecordedStreamEvent(capturing: event))
                        continuation.yield(event)
                    }
                    // Normal completion: persist the full turn, then finish.
                    await recorder.recordModelStream(turnIndex: turnIndex, events: collected)
                    continuation.finish()
                } catch {
                    // A FAILED stream must NOT consume a turn index: the live
                    // pipeline retries with a fresh messagesStream call, and a
                    // recorded failed/partial turn would shift every subsequent
                    // index on replay (the retry re-issues only one request). Roll
                    // the claimed index back so the retry reuses it, and do NOT
                    // record the partial. The error still propagates downstream.
                    await recorder.discardClaimedModelTurn(turnIndex)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Delegated (no recording)

    func messages(parameters: AnthropicMessageParameter) async throws -> AnthropicMessageResponse {
        try await wrapped.messages(parameters: parameters)
    }

    func listModels() async throws -> AnthropicModelsResponse {
        try await wrapped.listModels()
    }

    func retrieveModel(id: String) async throws -> AnthropicModel {
        try await wrapped.retrieveModel(id: id)
    }

    func countTokens(parameters: AnthropicTokenCountParameter) async throws -> AnthropicTokenCountResponse {
        try await wrapped.countTokens(parameters: parameters)
    }

    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> AnthropicFileMetadata {
        try await wrapped.uploadFile(data: data, filename: filename, mimeType: mimeType)
    }

    func retrieveFileMetadata(id: String) async throws -> AnthropicFileMetadata {
        try await wrapped.retrieveFileMetadata(id: id)
    }

    func listFiles() async throws -> AnthropicFileListResponse {
        try await wrapped.listFiles()
    }

    func deleteFile(id: String) async throws -> AnthropicFileDeletedResponse {
        try await wrapped.deleteFile(id: id)
    }

    // MARK: - Private helpers

    /// Best-effort JSON dump of the request parameters for the advisory tape
    /// record. Returns `nil` (rather than throwing) if encoding fails, since the
    /// value is purely informational.
    private func encodeRequest(_ parameters: AnthropicMessageParameter) -> String? {
        guard let data = try? requestEncoder.encode(parameters) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
