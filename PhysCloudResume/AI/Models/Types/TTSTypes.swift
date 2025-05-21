// 
//  TTSTypes.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/21/25.
//

import Foundation

/// Protocol that marks an LLM client as capable of handling Text-to-Speech requests
protocol TTSCapable {
    /// Sends a non-streaming TTS request and calls the completion handler with the result
    func sendTTSRequest(
        text: String,
        voice: String,
        instructions: String?,
        onComplete: @escaping (Result<Data, Error>) -> Void
    )
    
    /// Sends a streaming TTS request with callbacks for audio chunks and completion
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        instructions: String?,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    )
}

/// A placeholder implementation of TTSCapable that returns errors for all requests
class PlaceholderTTSClient: TTSCapable {
    private let errorMessage: String
    
    init(errorMessage: String = "TTS service unavailable") {
        self.errorMessage = errorMessage
    }
    
    func sendTTSRequest(
        text: String,
        voice: String,
        instructions: String?,
        onComplete: @escaping (Result<Data, Error>) -> Void
    ) {
        let error = NSError(
            domain: "TTSCapable",
            code: 4001,
            userInfo: [NSLocalizedDescriptionKey: errorMessage]
        )
        onComplete(.failure(error))
    }
    
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        instructions: String?,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        let error = NSError(
            domain: "TTSCapable",
            code: 4001,
            userInfo: [NSLocalizedDescriptionKey: errorMessage]
        )
        onComplete(error)
    }
}