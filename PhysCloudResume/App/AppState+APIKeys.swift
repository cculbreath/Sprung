//
//  AppState+APIKeys.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation

/// Extension to AppState to provide API key management
extension AppState {
    /// API key manager for the application
    class APIKeyManager {
        /// Gets the API key for a specific provider from UserDefaults
        /// - Parameter provider: The provider to get the key for
        /// - Returns: The API key, or nil if not found
        func getKey(for provider: String) -> String? {
            let keyName: String
            
            switch provider {
            case AIModels.Provider.openai:
                keyName = "openAiApiKey"
            case AIModels.Provider.claude:
                keyName = "claudeApiKey"
            case AIModels.Provider.gemini:
                keyName = "geminiApiKey"
            case AIModels.Provider.grok:
                keyName = "grokApiKey"
            default:
                keyName = "openAiApiKey"
            }
            
            let key = UserDefaults.standard.string(forKey: keyName)
            return key != "none" ? key : nil
        }
        
        /// Sets the API key for a specific provider in UserDefaults
        /// - Parameters:
        ///   - key: The API key to set
        ///   - provider: The provider to set the key for
        func setKey(_ key: String, for provider: String) {
            let keyName: String
            
            switch provider {
            case AIModels.Provider.openai:
                keyName = "openAiApiKey"
            case AIModels.Provider.claude:
                keyName = "claudeApiKey"
            case AIModels.Provider.gemini:
                keyName = "geminiApiKey"
            case AIModels.Provider.grok:
                keyName = "grokApiKey"
            default:
                keyName = "openAiApiKey"
            }
            
            UserDefaults.standard.set(key, forKey: keyName)
        }
    }
    
    /// The API key manager for the application
    var apiKeys: APIKeyManager {
        return APIKeyManager()
    }
}
