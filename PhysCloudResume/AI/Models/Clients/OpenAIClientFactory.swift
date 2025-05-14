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
    
    /// Creates a Gemini client with the given API key
    /// - Parameter apiKey: The Gemini API key to use for requests
    /// - Returns: An instance conforming to OpenAIClientProtocol configured for Gemini API
    static func createGeminiClient(apiKey: String) -> OpenAIClientProtocol {
        // Configure for Gemini API
        // Gemini API requires different host and path settings
        let configuration = OpenAI.Configuration(
            token: apiKey,
            host: "generativelanguage.googleapis.com",  // Gemini API host
            basePath: "/v1/models",                   // Gemini API path with models prefix
            customHeaders: ["x-goog-api-key": apiKey]  // Gemini uses API key in header instead of Bearer token
        )
        
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
