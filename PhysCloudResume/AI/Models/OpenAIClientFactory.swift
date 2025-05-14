//
//  OpenAIClientFactory.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/22/25.
//

import Foundation
import OpenAI

/// Factory for creating OpenAI clients
class OpenAIClientFactory {
    /// Creates an OpenAI client with the given configuration
    /// - Parameter configuration: The configuration to use for client setup
    /// - Returns: An instance conforming to OpenAIClientProtocol
    static func createClient(configuration: OpenAI.Configuration) -> OpenAIClientProtocol {
        return SystemFingerprintFixClient(configuration: configuration)
    }

    /// Creates an OpenAI client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An instance conforming to OpenAIClientProtocol
    static func createClient(apiKey: String) -> OpenAIClientProtocol {
        // Create configuration with default options
        let configuration = OpenAI.Configuration(token: apiKey)
        return SystemFingerprintFixClient(configuration: configuration)
    }
    
    /// Creates a TTS-capable client
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An OpenAIClientProtocol that supports TTS
    static func createTTSClient(apiKey: String) -> OpenAIClientProtocol {
        // TTS doesn't have system_fingerprint issues, so we can use the regular client
        // But for consistency, we'll still use our custom client
        return SystemFingerprintFixClient(apiKey: apiKey)
    }
}
