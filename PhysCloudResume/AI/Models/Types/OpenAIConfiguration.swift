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
    /// Fill required fields if the key is not found in the response
    case fillRequiredFieldIfKeyNotFound
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
    
    /// Convenience initializer for basic usage with just an API key
    /// - Parameter apiKey: The OpenAI API key
    public init(apiKey: String) {
        self.init(token: apiKey)
    }
    
    /// Convenience initializer with parsing options
    /// - Parameters:
    ///   - token: The API token
    ///   - parsingOptions: How to handle parsing responses
    public init(token: String, parsingOptions: OpenAIParsingOptions) {
        self.init(
            token: token,
            organizationIdentifier: nil,
            host: "api.openai.com",
            basePath: "/v1",
            customHeaders: [:],
            timeoutInterval: 900.0,
            parsingOptions: parsingOptions
        )
    }
}

/// Extension to provide default configurations for common use cases
public extension OpenAIConfiguration {
    /// Default configuration with relaxed parsing for handling null fields
    /// - Parameter token: The API token
    /// - Returns: Configuration with relaxed parsing options
    static func relaxedParsing(token: String) -> OpenAIConfiguration {
        return OpenAIConfiguration(token: token, parsingOptions: .fillRequiredFieldIfKeyNotFound)
    }
    
    /// Configuration for Gemini API
    /// - Parameter apiKey: The Gemini API key
    /// - Returns: Configuration set up for Gemini API endpoints
    static func gemini(apiKey: String) -> OpenAIConfiguration {
        return OpenAIConfiguration(
            token: apiKey,
            organizationIdentifier: nil,
            host: "generativelanguage.googleapis.com",
            basePath: "/v1/models",
            customHeaders: ["x-goog-api-key": apiKey],
            timeoutInterval: 900.0,
            parsingOptions: .standard
        )
    }
}
