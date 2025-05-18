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
import SwiftOpenAI
import OpenAI

/// Factory for creating OpenAI clients
class OpenAIClientFactory {
    /// Creates an OpenAI client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An instance conforming to OpenAIClientProtocol
    static func createClient(apiKey: String) -> OpenAIClientProtocol {
        return SwiftOpenAIClient(apiKey: apiKey)
    }
    
    /// Creates a TTS-capable client
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An OpenAIClientProtocol that supports TTS
    static func createTTSClient(apiKey: String) -> OpenAIClientProtocol {
        return SwiftOpenAIClient(apiKey: apiKey)
    }
    
    /// Creates a Gemini client with the given API key
    /// - Parameter apiKey: The Gemini API key to use for requests
    /// - Returns: An instance conforming to OpenAIClientProtocol configured for Gemini API
    static func createGeminiClient(apiKey: String) -> OpenAIClientProtocol {
        // Use our custom Gemini configuration
        let configuration = OpenAIConfiguration.gemini(apiKey: apiKey)
        return SwiftOpenAIClient(configuration: configuration)
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
