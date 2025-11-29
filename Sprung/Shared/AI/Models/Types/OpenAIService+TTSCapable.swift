//
//  OpenAIService+TTSCapable.swift
//  Sprung
//
import Foundation
import SwiftOpenAI
/// Bridges the SwiftOpenAI fork to the `TTSCapable` protocol until the SDK
/// exposes native conformance. Remove this adapter when the upstream
/// dependency ships a direct implementation.
final class OpenAIServiceTTSWrapper: TTSCapable {
    private let service: OpenAIService
    init(service: OpenAIService) {
        self.service = service
    }
    func sendTTSRequest(
        text: String,
        voice: String,
        onComplete: @escaping (Result<Data, Error>) -> Void
    ) {
        Task {
            do {
                let parameters = AudioSpeechParameters(
                    model: .tts1,
                    input: text,
                    voice: .init(rawValue: voice) ?? .nova,
                    responseFormat: .mp3,
                    speed: 1.0
                )
                let audioObject = try await service.createSpeech(parameters: parameters)
                onComplete(.success(audioObject.output))
            } catch {
                onComplete(.failure(error))
            }
        }
    }
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        Task {
            do {
                let parameters = AudioSpeechParameters(
                    model: .tts1,
                    input: text,
                    voice: .init(rawValue: voice) ?? .nova,
                    responseFormat: .mp3,
                    speed: 1.0
                )
                let audioStream = try await service.createStreamingSpeech(parameters: parameters)
                for try await chunk in audioStream {
                    onChunk(.success(chunk.chunk))
                }
                onComplete(nil)
            } catch {
                onComplete(error)
            }
        }
    }
}
