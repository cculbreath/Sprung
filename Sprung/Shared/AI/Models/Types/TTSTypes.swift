// 
//  TTSTypes.swift
//  Sprung
//
//
import Foundation
/// Protocol that marks an LLM client as capable of handling Text-to-Speech requests
protocol TTSCapable {
    /// Sends a non-streaming TTS request and calls the completion handler with the result
    /// Sends a non-streaming TTS request and calls the completion handler with the result
    func sendTTSRequest(
        text: String,
        voice: String,
        onComplete: @escaping (Result<Data, Error>) -> Void
    )
    /// Sends a streaming TTS request with callbacks for audio chunks and completion
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    )
}
/// A fallback implementation used when no TTS provider is configured.
/// Logs a warning and surfaces a consistent error to the caller.
final class UnavailableTTSClient: TTSCapable {
    private let errorMessage: String
    init(errorMessage: String = "TTS service unavailable") {
        self.errorMessage = errorMessage
    }
    func sendTTSRequest(
        text: String,
        voice: String,
        onComplete: @escaping (Result<Data, Error>) -> Void
    ) {
        Logger.warning(
            "UnavailableTTSClient dropping request for voice \(voice): \(errorMessage)",
            category: .ai
        )
        onComplete(.failure(makeError()))
    }
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        Logger.warning(
            "UnavailableTTSClient dropping streaming request for voice \(voice): \(errorMessage)",
            category: .ai
        )
        onComplete(makeError())
    }
    private func makeError() -> NSError {
        NSError(
            domain: "TTSCapable.Unavailable",
            code: 4001,
            userInfo: [NSLocalizedDescriptionKey: errorMessage]
        )
    }
}
