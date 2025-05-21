//
//  OpenAIClientFactory.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/22/25.
//  Updated by Christopher Culbreath on 5/20/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI
import SwiftOpenAI

/// Factory for creating OpenAI clients
/// This is maintained for backward compatibility
/// @available(*, deprecated, message: "Use AppLLMClientFactory instead")
class OpenAIClientFactory {
    /// Creates an OpenAI client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An instance conforming to OpenAIClientProtocol
    /// @available(*, deprecated, message: "Use AppLLMClientFactory.createClient instead")
    static func createClient(apiKey: String) -> OpenAIClientProtocol? {
        // Validate the API key first
        guard let validKey = ModelFilters.validateAPIKey(apiKey, for: AIModels.Provider.openai) else {
            Logger.warning("⚠️ Invalid OpenAI API key format provided to createClient")
            return nil
        }
        
        // Wrap it in a legacy adapter
        return LegacyOpenAIClientAdapter(apiKey: validKey)
    }
    
    /// Creates a TTS-capable client
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An OpenAIClientProtocol that supports TTS
    /// @available(*, deprecated, message: "Use AppLLMClientFactory.createClient with TTSProvider instead")
    static func createTTSClient(apiKey: String) -> OpenAIClientProtocol? {
        // TTS is still supported directly through SwiftOpenAIClient
        // Validate the API key first
        guard let validKey = ModelFilters.validateAPIKey(apiKey, for: AIModels.Provider.openai) else {
            Logger.warning("⚠️ Invalid OpenAI API key format provided to createTTSClient")
            return nil
        }
        
        // For now, use the original SwiftOpenAIClient for TTS since our adapters don't handle TTS
        return SwiftOpenAIClient(apiKey: validKey)
    }
    
    /// Creates a client for the appropriate service based on the selected model
    /// - Parameters:
    ///   - model: The model to use (determines which service to connect to)
    ///   - apiKeys: Dictionary of API keys for different providers
    /// - Returns: A client configured for the specified model, or nil if no API key is available
    /// @available(*, deprecated, message: "Use AppLLMClientFactory.createClient instead")
    static func createClientForModel(model: String, apiKeys: [String: String]) -> OpenAIClientProtocol? {
        // First determine the provider for this model
        let provider = AIModels.providerForModel(model)
        Logger.debug("🔄 Creating legacy client for model: \(model) (Provider: \(provider))")
        
        // Get and validate the API key for this provider
        if let apiKey = apiKeys[provider], apiKey != "none" {
            let validKey = ModelFilters.validateAPIKey(apiKey, for: provider)
            
            if let validKey = validKey {
                // Log success without revealing the entire key
                Logger.debug("✅ Using validated \(provider) API key: \(validKey.prefix(4))...")
                
                // Create a config for the appropriate provider
                let config: LLMProviderConfig
                
                switch provider {
                case AIModels.Provider.claude:
                    config = LLMProviderConfig.forClaude(apiKey: validKey)
                    
                case AIModels.Provider.grok:
                    config = LLMProviderConfig.forGrok(apiKey: validKey)
                    
                case AIModels.Provider.gemini:
                    config = LLMProviderConfig.forGemini(apiKey: validKey)
                    
                case AIModels.Provider.openai:
                    config = LLMProviderConfig.forOpenAI(apiKey: validKey)
                    
                default:
                    config = LLMProviderConfig.forOpenAI(apiKey: validKey)
                }
                
                // Create an OpenAIConfiguration from the LLMProviderConfig
                let openAIConfig = createOpenAIConfiguration(from: config)
                
                // Use the legacy adapter to wrap the new client
                return LegacyOpenAIClientAdapter(configuration: openAIConfig)
            } else {
                Logger.error("❌ Invalid API key format for provider: \(provider)")
            }
        } else {
            Logger.error("❌ No API key available for provider: \(provider)")
        }
        
        // If we reach here, fall back to the old client creation method
        return nil
    }
    
    /// Helper to create an OpenAIConfiguration from an LLMProviderConfig
    /// - Parameter config: The LLM provider configuration
    /// - Returns: An OpenAIConfiguration
    /// @available(*, deprecated, message: "Use AppLLMClientFactory instead")
    private static func createOpenAIConfiguration(from config: LLMProviderConfig) -> OpenAIConfiguration {
        var customHeaders: [String: String] = config.extraHeaders ?? [:]
        
        // Set the host and path
        let host = config.baseURL?.replacingOccurrences(of: "https://", with: "") ?? "api.openai.com"
        let basePath = "/\(config.apiVersion ?? "v1")"
        
        // For Claude, add the anthropic headers
        if config.providerType == AIModels.Provider.claude {
            customHeaders["anthropic-version"] = "2023-06-01"
            customHeaders["x-api-key"] = config.apiKey
        }
        
        return OpenAIConfiguration(
            token: config.apiKey,
            host: host,
            basePath: basePath,
            customHeaders: customHeaders,
            timeoutInterval: 900.0
        )
    }
}
