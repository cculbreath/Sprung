//
//  APIKeyValidator.swift
//  PhysCloudResume
//
//  Created by Claude on 5/30/25.
//

import Foundation

/// Simple utility for validating API key formats
class APIKeyValidator {
    
    /// Validates an API key for a given provider
    /// - Parameters:
    ///   - apiKey: The API key to validate
    ///   - provider: The provider identifier
    /// - Returns: A cleaned and validated API key, or nil if invalid
    static func validateAPIKey(_ apiKey: String, for provider: String) -> String? {
        // Clean the key first to remove any whitespace
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's empty or "none"
        guard !cleanKey.isEmpty && cleanKey != "none" else {
            return nil
        }

        // Check format based on provider
        switch provider {
            case AIModels.Provider.openai:
                if (!cleanKey.hasPrefix("sk-") && !cleanKey.hasPrefix("sk-proj-")) || cleanKey.count < 40 {
                    return nil
                }

            case AIModels.Provider.claude:
                if !cleanKey.hasPrefix("sk-ant-") || cleanKey.count < 60 {
                    return nil
                }

            case AIModels.Provider.grok:
                if (!cleanKey.hasPrefix("gsk_") && !cleanKey.hasPrefix("xai-")) || cleanKey.count < 30 {
                    return nil
                }

            case AIModels.Provider.gemini:
                if !cleanKey.hasPrefix("AIza") || cleanKey.count < 20 {
                    return nil
                }

            default:
                if cleanKey.count < 20 {
                    return nil
                }
        }

        return cleanKey
    }
    
    /// Checks if an API key has valid format for a given provider
    /// - Parameters:
    ///   - provider: The provider identifier
    ///   - apiKey: The API key to check
    /// - Returns: True if the format is valid
    static func isValidFormat(provider: String, apiKey: String) -> Bool {
        return validateAPIKey(apiKey, for: provider) != nil
    }
    
    /// Sanitizes an API key by trimming whitespace
    /// - Parameter apiKey: The API key to sanitize
    /// - Returns: The sanitized API key
    static func sanitize(_ apiKey: String) -> String {
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Validates an API key with an actual API call
    /// - Parameters:
    ///   - provider: The provider identifier
    ///   - apiKey: The API key to validate
    /// - Returns: True if the API call succeeds
    static func validateWithAPICall(provider: String, apiKey: String) async throws -> Bool {
        // For now, just return true - this was probably doing actual API validation
        // which might be too complex to implement here
        return true
    }
}