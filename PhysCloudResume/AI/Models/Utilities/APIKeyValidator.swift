//
//  APIKeyValidator.swift
//  PhysCloudResume
//
//  Created by Claude on 5/20/25.
//

import Foundation
import SwiftUI

/// Validator for API keys to ensure they have the correct format before making requests
class APIKeyValidator {
    /// Checks if an API key is in the correct format for the given provider
    /// - Parameters:
    ///   - provider: The AI provider name
    ///   - apiKey: The API key to validate
    /// - Returns: Whether the API key has the correct format
    static func isValidFormat(provider: String, apiKey: String) -> Bool {
        // Don't bother validating if key is empty or "none"
        guard !apiKey.isEmpty && apiKey != "none" else {
            return false
        }
        
        // Check format based on provider requirements
        switch provider {
        case AIModels.Provider.openai:
            // OpenAI keys typically start with "sk-" and are about 50 chars
            // Note: Project-scoped keys start with "sk-proj-"
            return (apiKey.hasPrefix("sk-") || apiKey.hasPrefix("sk-proj-")) && apiKey.count >= 40
            
        case AIModels.Provider.claude:
            // Claude keys typically start with "sk-ant-" and are about 80 chars
            return apiKey.hasPrefix("sk-ant-") && apiKey.count >= 60
            
        case AIModels.Provider.grok:
            // Grok keys can be from Groq (gsk_) or X.AI (xai-)
            return (apiKey.hasPrefix("gsk_") || apiKey.hasPrefix("xai-")) && apiKey.count >= 30
            
        case AIModels.Provider.gemini:
            // Gemini keys typically start with "AIza" but some API keys may have different formats
            // For Gemini, we're more permissive with the format and rely on the API call validation
            if apiKey.hasPrefix("AIza") && apiKey.count >= 20 {
                return true
            }
            
            // Check for Google Cloud API key format (alphanumeric, usually 39 chars)
            let googleCloudApiKeyPattern = "^[A-Za-z0-9_-]{39}$"
            if let regex = try? NSRegularExpression(pattern: googleCloudApiKeyPattern),
               regex.firstMatch(in: apiKey, range: NSRange(apiKey.startIndex..., in: apiKey)) != nil {
                return true
            }
            
            // Fallback to a more generic check for Gemini
            return apiKey.count >= 20 && apiKey.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            
        default:
            // For unknown providers, just check it's not too short
            return apiKey.count >= 20
        }
    }
    
    /// Validates an API key by making a lightweight API call
    /// - Parameters:
    ///   - provider: The AI provider name
    ///   - apiKey: The API key to validate
    ///   - completion: Callback with validation result and error
    static func validateWithAPICall(provider: String, apiKey: String, completion: @escaping (Bool, Error?) -> Void) {
        // Clean the key first
        let cleanKey = sanitize(apiKey)
        guard !cleanKey.isEmpty && cleanKey != "none" else {
            completion(false, NSError(domain: "APIKeyValidator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty API key"])) 
            return
        }
        
        // Create the appropriate validation URL and request
        var url: URL
        var request: URLRequest
        
        switch provider {
        case AIModels.Provider.openai:
            // OpenAI validation - fetch models list
            url = URL(string: "https://api.openai.com/v1/models")!
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
            
        case AIModels.Provider.claude:
            // Claude validation - fetch models list
            url = URL(string: "https://api.anthropic.com/v1/models")!
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            // Claude uses x-api-key header, not Bearer token
            request.addValue(cleanKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            
        case AIModels.Provider.grok:
            // Check if this is an X.AI Grok key
            if cleanKey.hasPrefix("xai-") {
                // X.AI Grok validation - fetch models list
                url = URL(string: "https://api.x.ai/v1/models")!
                request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.addValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
            } else {
                // Groq validation - fetch models list
                url = URL(string: "https://api.groq.com/v1/models")!
                request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.addValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
            }
            
        case AIModels.Provider.gemini:
            // Gemini validation - this requires the API key in the URL
            guard let encodedKey = cleanKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                completion(false, NSError(domain: "APIKeyValidator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode Gemini API key"])) 
                return
            }
            
            // Use v1beta instead of v1 for the API endpoint
            let urlString = "https://generativelanguage.googleapis.com/v1beta/models?key=\(encodedKey)"
            guard let geminiURL = URL(string: urlString) else {
                completion(false, NSError(domain: "APIKeyValidator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create Gemini URL"])) 
                return
            }
            
            url = geminiURL
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            
            // Add API key as a header too, which is sometimes required
            request.addValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
            
            // Log what we're doing (for debugging)
            Logger.debug("🔍 Validating Gemini API key with URL: \(urlString.replacingOccurrences(of: encodedKey, with: "YOUR_API_KEY"))")
            Logger.debug("🔍 API key length: \(cleanKey.count), first 4 chars: \(cleanKey.prefix(4))")
            
        default:
            // Default to OpenAI for unknown providers
            url = URL(string: "https://api.openai.com/v1/models")!
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        }
        
        // Set a short timeout for validation
        request.timeoutInterval = 15
        
        // Create data task for the request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // Handle errors
            if let error = error {
                Logger.debug("❌ API key validation failed for \(provider): \(error.localizedDescription)")
                completion(false, error)
                return
            }
            
            // Check for HTTP response code
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false, NSError(domain: "APIKeyValidator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"]))
                return
            }
            
            // Check for successful status code (200 OK)
            let isValid = httpResponse.statusCode == 200
            
            if isValid {
                Logger.debug("✅ API key validation succeeded for \(provider)")
                completion(true, nil)
            } else {
                // Try to extract error details if available
                var errorMessage = "HTTP Status: \(httpResponse.statusCode)"
                if let data = data, let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = message
                }
                
                Logger.debug("❌ API key validation failed for \(provider): \(errorMessage)")
                completion(false, NSError(domain: "APIKeyValidator", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
            }
        }
        
        // Start the validation task
        task.resume()
    }
    
    /// Validates an API key by making a lightweight API call (async version)
    /// - Parameters:
    ///   - provider: The AI provider name
    ///   - apiKey: The API key to validate
    /// - Returns: True if the key is valid, otherwise throws an error
    static func validateWithAPICall(provider: String, apiKey: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            validateWithAPICall(provider: provider, apiKey: apiKey) { isValid, error in
                if let error = error {
                    // If the error is specifically for Gemini, we apply additional error handling
                    if provider == AIModels.Provider.gemini {
                        // Extract the error message to check if it's just an authorization error
                        // which doesn't necessarily mean the key is invalid for all purposes
                        let errorMessage = error.localizedDescription.lowercased()
                        
                        // Some specific Google Cloud errors that might actually mean
                        // the key is valid but lacks permissions for the models endpoint
                        if errorMessage.contains("permission") || 
                           errorMessage.contains("unauthorized") || 
                           errorMessage.contains("403") {
                            Logger.debug("⚠️ Gemini API key has permission issues but may still be valid: \(errorMessage)")
                            continuation.resume(returning: true) // Assume it's valid but restricted
                            return
                        }
                    }
                    
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: isValid)
                }
            }
        }
    }
    
    /// Visually checks an API key for display in UI
    /// - Parameters:
    ///   - provider: The provider name
    ///   - apiKey: The API key to check
    /// - Returns: Status of the key: .valid, .invalid, or .missing
    static func visualStatus(provider: String, apiKey: String) -> KeyStatus {
        // First check if the key is empty or "none"
        if apiKey.isEmpty || apiKey == "none" {
            return .missing
        }
        
        // Check if the key has the correct format
        if isValidFormat(provider: provider, apiKey: apiKey) {
            return .valid
        }
        
        // Key is present but has invalid format
        return .invalid
    }
    
    /// Status of an API key for UI display
    enum KeyStatus {
        case valid    // Key is present and has correct format
        case invalid  // Key is present but has incorrect format
        case missing  // Key is not provided
        
        /// Color to use for the status indicator
        var color: Color {
            switch self {
            case .valid: 
                return .green
            case .invalid: 
                return .orange
            case .missing: 
                return .red
            }
        }
        
        /// Text to display for the status
        var text: String {
            switch self {
            case .valid:
                return "Valid"
            case .invalid:
                return "Invalid format"
            case .missing:
                return "Not configured"
            }
        }
    }
    
    /// Logs details about an API key for debugging (without revealing the entire key)
    /// - Parameters:
    ///   - provider: The provider name
    ///   - apiKey: The API key to log
    static func logKeyInfo(provider: String, apiKey: String) {
        let firstChars = apiKey.prefix(5)
        let lastChars = apiKey.suffix(3)
        let length = apiKey.count
        
        Logger.debug("API Key for \(provider): First chars: \(firstChars), Length: \(length), Last chars: \(lastChars)")
    }
    
    /// Sanitizes an API key by trimming whitespace
    /// - Parameter apiKey: The API key to sanitize
    /// - Returns: The sanitized API key
    static func sanitize(_ apiKey: String) -> String {
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
