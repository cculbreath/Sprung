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

/// Factory for creating OpenAI clients
class OpenAIClientFactory {
    /// Creates an OpenAI client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An instance conforming to OpenAIClientProtocol
    static func createClient(apiKey: String) -> OpenAIClientProtocol? {
        // Validate the API key first
        guard let validKey = ModelFilters.validateAPIKey(apiKey, for: AIModels.Provider.openai) else {
            Logger.warning("⚠️ Invalid OpenAI API key format provided to createClient")
            return nil
        }
        
        return SwiftOpenAIClient(apiKey: validKey)
    }
    
    /// Creates a TTS-capable client
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An OpenAIClientProtocol that supports TTS
    static func createTTSClient(apiKey: String) -> OpenAIClientProtocol? {
        // Validate the API key first
        guard let validKey = ModelFilters.validateAPIKey(apiKey, for: AIModels.Provider.openai) else {
            Logger.warning("⚠️ Invalid OpenAI API key format provided to createTTSClient")
            return nil
        }
        
        return SwiftOpenAIClient(apiKey: validKey)
    }
    
    /// Creates a client for the appropriate service based on the selected model
    /// - Parameters:
    ///   - model: The model to use (determines which service to connect to)
    ///   - apiKeys: Dictionary of API keys for different providers
    /// - Returns: A client configured for the specified model, or nil if no API key is available
    static func createClientForModel(model: String, apiKeys: [String: String]) -> OpenAIClientProtocol? {
        // First determine the provider for this model
        let provider = AIModels.providerForModel(model)
        Logger.debug("🔄 Creating client for model: \(model) (Provider: \(provider))")
        
        // Get and validate the API key for this provider
        if let apiKey = apiKeys[provider], apiKey != "none" {
            let validKey = ModelFilters.validateAPIKey(apiKey, for: provider)
            
            if let validKey = validKey {
                // Log success without revealing the entire key
                Logger.debug("✅ Using validated \(provider) API key: \(validKey.prefix(4))...")
                
                // Create provider-specific client configurations
                switch provider {
                case AIModels.Provider.claude:
                    let config = OpenAIConfiguration.forClaude(apiKey: validKey)
                    return SwiftOpenAIClient(configuration: config)
                    
                case AIModels.Provider.grok:
                    let config = OpenAIConfiguration.forGrok(apiKey: validKey)
                    return SwiftOpenAIClient(configuration: config)
                    
                case AIModels.Provider.gemini:
                    let config = OpenAIConfiguration.forGemini(apiKey: validKey)
                    return SwiftOpenAIClient(configuration: config)
                    
                case AIModels.Provider.openai:
                    // For OpenAI, use the standard client
                    return SwiftOpenAIClient(apiKey: validKey)
                    
                default:
                    // For unknown providers, default to OpenAI client
                    Logger.warning("⚠️ Unknown provider: \(provider), defaulting to OpenAI client")
                    return SwiftOpenAIClient(apiKey: validKey)
                }
            } else {
                Logger.error("❌ Invalid API key format for provider: \(provider)")
            }
        } else {
            Logger.error("❌ No API key available for provider: \(provider)")
        }
        
        // If we reach here, fall back to the old client creation method
        return SwiftOpenAIClient.clientForModel(model: model, apiKeys: apiKeys)
    }
}
