//
//  AppLLMClientFactory.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation

/// Factory for creating LLM clients that conform to AppLLMClientProtocol
class AppLLMClientFactory {
    /// Creates an LLM client for the specified provider
    /// - Parameters:
    ///   - providerType: The type of provider to create a client for
    ///   - appState: The application state
    /// - Returns: An LLM client that conforms to AppLLMClientProtocol
    static func createClient(for providerType: String, appState: AppState) -> AppLLMClientProtocol {
        // Get the API key using UserDefaults
        var apiKey = ""
        
        switch providerType {
        case AIModels.Provider.openai:
            apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
        case AIModels.Provider.claude:
            apiKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? ""
        case AIModels.Provider.grok:
            apiKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? ""
        case AIModels.Provider.gemini:
            apiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        default:
            apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
        }
        
        // Create the appropriate configuration and adapter
        var config: LLMProviderConfig
        switch providerType {
        case AIModels.Provider.openai:
            config = LLMProviderConfig.forOpenAI(apiKey: apiKey)
            return SwiftOpenAIAdapterForOpenAI(config: config, appState: appState)
            
        case AIModels.Provider.gemini:
            config = LLMProviderConfig.forGemini(apiKey: apiKey)
            return SwiftOpenAIAdapterForGemini(config: config, appState: appState)
            
        case AIModels.Provider.claude:
            config = LLMProviderConfig.forClaude(apiKey: apiKey)
            return SwiftOpenAIAdapterForAnthropic(config: config, appState: appState)
            
        case AIModels.Provider.grok:
            config = LLMProviderConfig.forGrok(apiKey: apiKey)
            // Use Grok-specific adapter
            return SwiftOpenAIAdapterForGrok(config: config, appState: appState)
            
        default:
            // Default to OpenAI for unknown providers
            Logger.warning("Unknown provider type: \(providerType), defaulting to OpenAI client")
            config = LLMProviderConfig.forOpenAI(apiKey: apiKey)
            return SwiftOpenAIAdapterForOpenAI(config: config, appState: appState)
        }
    }
    
    /// Creates an LLM client for a specific model
    /// - Parameters:
    ///   - model: The model identifier
    ///   - appState: The application state
    /// - Returns: An LLM client configured for the specified model
    static func createClientForModel(model: String, appState: AppState) -> AppLLMClientProtocol {
        // ENHANCED DEBUG: Log the incoming model and detected provider
        Logger.debug("🏭 Factory called with model: '\(model)'")
        
        // Determine provider from model
        let provider = AIModels.providerForModel(model)
        Logger.debug("🔍 Detected provider: '\(provider)' for model: '\(model)'")
        
        let sanitizedModel = OpenAIModelFetcher.sanitizeModelName(model)
        Logger.debug("🧹 Sanitized model: '\(sanitizedModel)'")
        
        // Add validation to ensure provider and model match
        // This avoids the Claude adapter from being used with Grok models and vice versa
        let modelLower = model.lowercased()
        var correctedProvider = provider
        
        // Verify correct provider based on model name
        if modelLower.contains("claude") && provider != AIModels.Provider.claude {
            Logger.warning("🔄 Provider mismatch detected - correcting provider for Claude model: \(model)")
            correctedProvider = AIModels.Provider.claude
        } 
        else if modelLower.contains("gpt") || modelLower.contains("o3") || modelLower.contains("o4") {
            if provider != AIModels.Provider.openai {
                Logger.warning("🔄 Provider mismatch detected - correcting provider for OpenAI model: \(model)")
                correctedProvider = AIModels.Provider.openai
            }
        }
        else if modelLower.contains("grok") && provider != AIModels.Provider.grok {
            Logger.warning("🔄 Provider mismatch detected - correcting provider for Grok model: \(model)")
            correctedProvider = AIModels.Provider.grok
        }
        else if modelLower.contains("gemini") && provider != AIModels.Provider.gemini {
            Logger.warning("🔄 Provider mismatch detected - correcting provider for Gemini model: \(model)")
            correctedProvider = AIModels.Provider.gemini
        }
        
        Logger.debug("✅ Final provider: '\(correctedProvider)' for model: '\(model)'")
        
        // Get the API key using UserDefaults
        var apiKey = ""
        
        switch correctedProvider {
        case AIModels.Provider.openai:
            apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
        case AIModels.Provider.claude:
            apiKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? ""
        case AIModels.Provider.grok:
            apiKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? ""
        case AIModels.Provider.gemini:
            apiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        default:
            apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
        }
        
        Logger.debug("🔑 Using API key for \(correctedProvider): \(apiKey.prefix(4))..., length: \(apiKey.count)")
        
        // Create the appropriate configuration and adapter
        var config: LLMProviderConfig
        switch correctedProvider {
        case AIModels.Provider.openai:
            Logger.debug("🏗️ Creating OpenAI config")
            config = LLMProviderConfig.forOpenAI(apiKey: apiKey, model: sanitizedModel)
            return SwiftOpenAIAdapterForOpenAI(config: config, appState: appState)
            
        case AIModels.Provider.gemini:
            Logger.debug("🏗️ Creating Gemini config")
            config = LLMProviderConfig.forGemini(apiKey: apiKey, model: sanitizedModel)
            return SwiftOpenAIAdapterForGemini(config: config, appState: appState)
            
        case AIModels.Provider.claude:
            Logger.debug("🏗️ Creating Claude config")
            config = LLMProviderConfig.forClaude(apiKey: apiKey, model: sanitizedModel)
            return SwiftOpenAIAdapterForAnthropic(config: config, appState: appState)
            
        case AIModels.Provider.grok:
            Logger.debug("🏗️ Creating Grok config")
            config = LLMProviderConfig.forGrok(apiKey: apiKey, model: sanitizedModel)
            Logger.debug("🔧 Grok config created: providerType=\(config.providerType), baseURL=\(config.baseURL ?? "nil")")
            // Use Grok-specific adapter
            return SwiftOpenAIAdapterForGrok(config: config, appState: appState)
            
        default:
            // Default to OpenAI for unknown providers
            Logger.warning("Unknown provider type: \(correctedProvider), defaulting to OpenAI client")
            config = LLMProviderConfig.forOpenAI(apiKey: apiKey, model: sanitizedModel)
            return SwiftOpenAIAdapterForOpenAI(config: config, appState: appState)
        }
    }
}
