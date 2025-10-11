//
//  OpenAIService+TTSCapable.swift
//  Sprung
//

import Foundation
import SwiftOpenAI

/// Wrapper to make OpenAIService conform to TTSCapable protocol
/// Since OpenAIService in our fork already has createSpeech and createStreamingSpeech methods,
/// we just need to bridge them to the TTSCapable interface
class OpenAIServiceTTSWrapper: TTSCapable {
    private let service: OpenAIService
    
    init(service: OpenAIService) {
        self.service = service
    }
    
    func sendTTSRequest(
        text: String,
        voice: String,
        instructions: String?,
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
        instructions: String?,
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

