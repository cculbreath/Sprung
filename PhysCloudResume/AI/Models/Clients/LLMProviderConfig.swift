//
//  LLMProviderConfig.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation

/// Configuration settings for various LLM providers
struct LLMProviderConfig {
    /// The provider type (OpenAI, Claude, Gemini, etc.)
    let providerType: String // Using String to match AIModels.Provider
    
    /// API key for authentication
    let apiKey: String
    
    /// Base URL for API requests
    let baseURL: String? // For SwiftOpenAI overrideBaseURL
    
    /// API version
    let apiVersion: String? // For SwiftOpenAI overrideVersion
    
    /// Optional proxy path for API routing
    let proxyPath: String? // For SwiftOpenAI proxyPath
    
    /// Additional headers for API requests
    let extraHeaders: [String: String]? // For SwiftOpenAI extraHeaders
    
    /// The specific model to use
    let model: String?
    
    // MARK: - Factory methods for common providers
    
    /// Creates configuration for OpenAI API
    /// - Parameters:
    ///   - apiKey: The API key for OpenAI
    ///   - model: Optional specific model to use
    /// - Returns: Configuration for OpenAI API
    static func forOpenAI(apiKey: String, model: String? = nil) -> LLMProviderConfig {
        return LLMProviderConfig(
            providerType: AIModels.Provider.openai,
            apiKey: apiKey,
            baseURL: nil, // Default OpenAI URL
            apiVersion: nil, // Default OpenAI version
            proxyPath: nil,
            extraHeaders: nil,
            model: model
        )
    }
    
    /// Creates configuration for Claude API
    /// - Parameters:
    ///   - apiKey: The API key for Claude
    ///   - model: Optional specific model to use
    /// - Returns: Configuration for Claude API
    static func forClaude(apiKey: String, model: String? = nil) -> LLMProviderConfig {
        return LLMProviderConfig(
            providerType: AIModels.Provider.claude,
            apiKey: apiKey,
            baseURL: "https://api.anthropic.com",
            apiVersion: "v1",
            proxyPath: nil,
            extraHeaders: [
                "anthropic-version": "2023-06-01"
            ],
            model: model
        )
    }
    
    /// Creates configuration for Gemini API using OpenAI-compatible endpoint
    /// - Parameters:
    ///   - apiKey: The API key for Gemini
    ///   - model: Optional specific model to use
    /// - Returns: Configuration for Gemini API
    static func forGemini(apiKey: String, model: String? = nil) -> LLMProviderConfig {
        return LLMProviderConfig(
            providerType: AIModels.Provider.gemini,
            apiKey: apiKey,
            baseURL: "https://generativelanguage.googleapis.com",
            apiVersion: "v1beta",
            proxyPath: nil,
            extraHeaders: nil,
            model: model
        )
    }
    
    /// Creates configuration for Grok API
    /// - Parameters:
    ///   - apiKey: The API key for Grok
    ///   - model: Optional specific model to use
    /// - Returns: Configuration for Grok API
    static func forGrok(apiKey: String, model: String? = nil) -> LLMProviderConfig {
        // Check if this is an X.AI Grok key (starts with xai-)
        if apiKey.hasPrefix("xai-") {
            return LLMProviderConfig(
                providerType: AIModels.Provider.grok,
                apiKey: apiKey,
                baseURL: "https://api.x.ai",
                apiVersion: "v1",
                proxyPath: nil,
                extraHeaders: nil,
                model: model
            )
        } else {
            // Legacy Groq API
            return LLMProviderConfig(
                providerType: AIModels.Provider.grok,
                apiKey: apiKey,
                baseURL: "https://api.groq.com",
                apiVersion: "v1",
                proxyPath: nil,
                extraHeaders: nil,
                model: model
            )
        }
    }
}
