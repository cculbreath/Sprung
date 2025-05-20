//
//  OpenAIConfiguration.swift
//  PhysCloudResume
//
//  Created by ChatBot on 5/17/25.
//

import Foundation

/// Custom parsing options for OpenAI API responses
/// This replaces OpenAI.Configuration.ParsingOptions to remove the OpenAI dependency
public enum OpenAIParsingOptions {
    /// Standard parsing without fallbacks
    case standard
}

/// Custom configuration for OpenAI clients
/// This replaces OpenAI.Configuration to remove the direct OpenAI dependency
public struct OpenAIConfiguration {
    /// The API token for authentication
    public let token: String?
    
    /// Optional organization identifier
    public let organizationIdentifier: String?
    
    /// Custom host for the API (default: api.openai.com)
    public let host: String
    
    /// Base path for API endpoints (default: /v1)
    public let basePath: String
    
    /// Custom headers to include in requests
    public let customHeaders: [String: String]
    
    /// Timeout interval for requests in seconds
    public let timeoutInterval: TimeInterval
    
    /// Parsing options for handling API responses
    public let parsingOptions: OpenAIParsingOptions
    
    /// Creates a new OpenAI configuration
    /// - Parameters:
    ///   - token: The API token
    ///   - organizationIdentifier: Optional organization ID
    ///   - host: Custom host (defaults to api.openai.com)
    ///   - basePath: Custom base path (defaults to /v1)
    ///   - customHeaders: Additional headers to include
    ///   - timeoutInterval: Request timeout in seconds (defaults to 900.0)
    ///   - parsingOptions: How to handle parsing responses (defaults to .standard)
    public init(
        token: String? = nil,
        organizationIdentifier: String? = nil,
        host: String = "api.openai.com",
        basePath: String = "/v1",
        customHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 900.0,
        parsingOptions: OpenAIParsingOptions = .standard
    ) {
        self.token = token
        self.organizationIdentifier = organizationIdentifier
        self.host = host
        self.basePath = basePath
        self.customHeaders = customHeaders
        self.timeoutInterval = timeoutInterval
        self.parsingOptions = parsingOptions
    }

}

/// Extension to provide default configurations for common use cases
public extension OpenAIConfiguration {
    /// Creates configuration for Claude API
    /// - Parameter apiKey: The API key for Claude
    /// - Returns: Configuration for Claude API
    static func forClaude(apiKey: String) -> OpenAIConfiguration {
        // The SwiftOpenAI client will utilize the token parameter to create an Authorization header
        // For Claude API, we need to use the proper anthropic-version header and x-api-key format
        // But the underlying library might also be using the token field
        return OpenAIConfiguration(
            token: apiKey, // Pass token normally for library compatibility
            host: "api.anthropic.com",
            basePath: "/v1",
            customHeaders: [
                "anthropic-version": "2023-06-01",
                "x-api-key": apiKey, // Claude uses x-api-key header
                "Authorization": "Bearer \(apiKey)" // Also include Authorization header format
            ],
            timeoutInterval: 900.0
        )
    }
    
    /// Creates configuration for Grok API
    /// - Parameter apiKey: The API key for Grok
    /// - Returns: Configuration for Grok API
    static func forGrok(apiKey: String) -> OpenAIConfiguration {
        // Check if this is an X.AI Grok key (starts with xai-)
        if apiKey.hasPrefix("xai-") {
            return OpenAIConfiguration(
                token: apiKey,
                host: "api.x.ai",
                basePath: "/v1",
                timeoutInterval: 900.0
            )
        } else {
            // Legacy Groq API
            return OpenAIConfiguration(
                token: apiKey,
                host: "api.groq.com",
                basePath: "/v1",
                timeoutInterval: 900.0
            )
        }
    }
    
    /// Creates configuration for Gemini API using OpenAI-compatible endpoint
    /// - Parameter apiKey: The API key for Gemini
    /// - Returns: Configuration for Gemini API
    static func forGemini(apiKey: String) -> OpenAIConfiguration {
        return OpenAIConfiguration(
            token: apiKey,
            host: "generativelanguage.googleapis.com",
            basePath: "/v1beta/openai", // Use the official OpenAI-compatible endpoint
            customHeaders: [:],
            timeoutInterval: 900.0
        )
    }
    
    /// Creates configuration for a specific provider based on the model name
    /// - Parameters:
    ///   - model: The model name (used to determine provider)
    ///   - apiKeys: Dictionary of API keys by provider
    /// - Returns: The appropriate configuration or nil if no matching API key
    static func forModel(model: String, apiKeys: [String: String]) -> OpenAIConfiguration? {
        let provider = AIModels.providerForModel(model)
        
        switch provider {
        case AIModels.Provider.claude:
            if let apiKey = apiKeys[AIModels.Provider.claude], apiKey != "none" {
                return .forClaude(apiKey: apiKey)
            }
        case AIModels.Provider.grok:
            if let apiKey = apiKeys[AIModels.Provider.grok], apiKey != "none" {
                return .forGrok(apiKey: apiKey)
            }
        case AIModels.Provider.gemini:
            if let apiKey = apiKeys[AIModels.Provider.gemini], apiKey != "none" {
                return .forGemini(apiKey: apiKey)
            }
        case AIModels.Provider.openai:
            if let apiKey = apiKeys[AIModels.Provider.openai], apiKey != "none" {
                return OpenAIConfiguration(token: apiKey, timeoutInterval: 900.0)
            }
        default:
            break
        }
        
        return nil
    }
}
