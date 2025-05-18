//
//  OpenAIClientFactory.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/22/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI
import OpenAI

/// Factory for creating OpenAI clients
class OpenAIClientFactory {
    /// Creates an OpenAI client with the given custom configuration
    /// - Parameter configuration: The custom configuration to use for client setup
    /// - Returns: An instance conforming to OpenAIClientProtocol
    static func createClient(configuration: OpenAIConfiguration) -> OpenAIClientProtocol {
        return SystemFingerprintFixClient(configuration: configuration)
    }

    /// Creates an OpenAI client with the given OpenAI SDK configuration (legacy support)
    /// - Parameter configuration: The OpenAI SDK configuration to use for client setup
    /// - Returns: An instance conforming to OpenAIClientProtocol
    static func createClient(openAIConfiguration: OpenAI.Configuration) -> OpenAIClientProtocol {
        return SystemFingerprintFixClient(openAIConfiguration: openAIConfiguration)
    }

    /// Creates an OpenAI client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An instance conforming to OpenAIClientProtocol
    static func createClient(apiKey: String) -> OpenAIClientProtocol {
        // Create custom configuration and use the new method
        let configuration = OpenAIConfiguration(apiKey: apiKey)
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
    
    /// Creates a Gemini client with the given API key
    /// - Parameter apiKey: The Gemini API key to use for requests
    /// - Returns: An instance conforming to OpenAIClientProtocol configured for Gemini API
    static func createGeminiClient(apiKey: String) -> OpenAIClientProtocol {
        // Use our custom Gemini configuration
        let configuration = OpenAIConfiguration.gemini(apiKey: apiKey)
        return SystemFingerprintFixClient(configuration: configuration)
    }
    
    /// Creates the appropriate client based on the selected model
    /// - Parameters:
    ///   - openAiApiKey: The OpenAI API key
    ///   - geminiApiKey: The Gemini API key
    ///   - modelName: The selected model name
    /// - Returns: An instance conforming to OpenAIClientProtocol
    static func createClientForModel(openAiApiKey: String, geminiApiKey: String, modelName: String) -> OpenAIClientProtocol {
        // Check if the model is a Gemini model
        if modelName.starts(with: "gemini-") && geminiApiKey != "none" {
            return createGeminiClient(apiKey: geminiApiKey)
        } else {
            // Default to OpenAI client
            return createClient(apiKey: openAiApiKey)
        }
    }
}
