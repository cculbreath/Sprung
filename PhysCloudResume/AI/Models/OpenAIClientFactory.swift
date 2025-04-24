//
//  OpenAIClientFactory.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/22/25.
//

import Foundation

/// Factory for creating OpenAI clients
class OpenAIClientFactory {
    /// Creates an OpenAI client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An instance conforming to OpenAIClientProtocol
    static func createClient(apiKey: String) -> OpenAIClientProtocol {
        return MacPawOpenAIClient(apiKey: apiKey)
    }

    /// Creates a TTS-capable client
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An OpenAIClientProtocol that supports TTS
    static func createTTSClient(apiKey: String) -> OpenAIClientProtocol {
        return MacPawOpenAIClient(apiKey: apiKey)
    }
}
