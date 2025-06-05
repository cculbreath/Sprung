//
//  OpenAIModelFetcher.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/16/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Provides model fetching and conversion utilities for OpenAI models
class OpenAIModelFetcher {
    /// Get the configured preferred model string from UserDefaults, with automatic correction
    static func getPreferredModelString() -> String {
        // Get the preferred model directly
        let rawModelString = UserDefaults.standard.string(forKey: "preferredLLMModel") ?? AIModels.gpt4o_latest
        
        // Check for gpt-3.5 and other unsupported models and replace with better defaults
        let modelLower = rawModelString.lowercased()
        
        // Fix deprecated or troublesome models
        if modelLower == "gpt-3.5" || modelLower == "gpt-3.5-turbo" || 
           modelLower.contains("claude-2.0") || modelLower == "claude-3.5-haiku" {
            Logger.warning("⚠️ Replacing deprecated/incorrectly formatted model '\(rawModelString)' with recommended alternative")
            
            // Check the model type to use an appropriate replacement
            if modelLower.contains("gpt") {
                return "o3-mini" // Replace GPT-3.5 family with o3-mini
            } else if modelLower.contains("claude") {
                return "claude-3-5-haiku-latest" // Replace old Claude models with latest Haiku
            } else {
                return AIModels.gpt4o_latest // Default fallback
            }
        }
        
        // Sanitize and return corrected model name
        return sanitizeModelName(rawModelString)
    }
    
    /// Returns default OpenAI models when API fetch fails
    static func defaultOpenAIModels() -> [String] {
        return []
    }
    
    /// Returns default Claude models when API fetch fails
    static func defaultClaudeModels() -> [String] {
        return []
    }
    
    /// Returns default Grok models when API fetch fails
    static func defaultGrokModels() -> [String] {
        return []
    }
    
    /// Returns default Gemini models when API fetch fails
    static func defaultGeminiModels() -> [String] {
        return []
    }
    
    /// Sanitizes a model name by correcting common corrupted variants
    /// - Parameter modelName: The potentially corrupted model name
    /// - Returns: The corrected model name
    static func sanitizeModelName(_ modelName: String) -> String {
        // Handle common corrupted model names
        switch modelName {
        // OpenAI corruptions and new reasoning mini model naming
        case "o4-mini", "4o-mini", "gpt4o-mini", "gpt-4o-mini":
            return AIModels.o4_mini // "o4-mini"
        case "o4", "4o", "gpt4o":
            return AIModels.gpt4o // "gpt-4o"
        case "o4-latest", "4o-latest", "gpt4o-latest":
            return AIModels.gpt4o_latest // "gpt-4o-2024-05-13"
        case "gpt4-turbo", "gpt-4turbo":
            return "gpt-4-turbo"
        case "gpt35-turbo", "gpt-35-turbo":
            return "gpt-3.5-turbo"
            
        // Claude corruptions
        case "claude3-opus", "claude-opus", "claudeopus":
            return AIModels.claude_3_opus
        case "claude3-sonnet", "claude-sonnet", "claudesonnet":
            return AIModels.claude_3_sonnet
        case "claude3-haiku", "claude-haiku", "claudehaiku":
            return AIModels.claude_3_haiku
        case "claude-3.5-haiku", "claude3.5-haiku", "claude-3.5-haiku-latest", "claude-3-5-haiku":
            return AIModels.claude_3_5_haiku // "claude-3-5-haiku-latest"
        
        // Grok corruptions
        case "grok1", "grok":
            return AIModels.grok_1
        case "grok1.5", "grok15":
            return AIModels.grok_1_5
        case "grok1.5-mini", "grok15-mini", "grok-mini":
            return AIModels.grok_1_5_mini
            
        // Gemini corruptions
        case "gemini", "geminipro":
            return AIModels.gemini_pro
        case "gemini-flash", "geminiflash":
            return AIModels.gemini_1_5_flash
        case "gemini-2.5-flash", "gemini2.5-flash", "gemini25flash":
            return AIModels.gemini_2_5_flash_preview
        case "gemini-2.0-flash", "gemini2.0-flash", "gemini20flash":
            return AIModels.gemini_2_0_flash
            
        default:
            // Return the original if no correction is needed
            return modelName
        }
    }

    /// Fetches available OpenAI models from the API
    static func fetchAvailableModels(apiKey: String) async -> [String] {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 900.0 // 15 minutes (increased from 5 minutes for reasoning models)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Logger.warning("Failed to fetch OpenAI models: HTTP \(response)")
                return []
            }

            struct ModelResponse: Codable {
                struct Model: Codable {
                    let id: String
                }

                let data: [Model]
            }

            let modelResponse = try JSONDecoder().decode(ModelResponse.self, from: data)
            let chatModels = modelResponse.data
                .map { $0.id }
                .filter { modelId in
                    let id = modelId.lowercased()
                    if id.hasPrefix("gpt-") {
                        return true
                    }
                    if id.hasPrefix("o"), id.count > 1,
                       id[id.index(id.startIndex, offsetBy: 1)].isNumber {
                        return true
                    }
                    return false
                }
                .sorted()

            Logger.debug("✅ Fetched \(chatModels.count) OpenAI models")
            return chatModels
        } catch {
            Logger.error("x Failed to fetch OpenAI models: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Fetches available Claude models from Anthropic API
    static func fetchClaudeModels(apiKey: String) async -> [String] {
        // Claude now has a models endpoint
        let url = URL(string: "https://api.anthropic.com/v1/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 900.0
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Logger.warning("Failed to fetch Claude models: HTTP \(response)")
                return []
            }
            
            struct ModelResponse: Codable {
                struct Model: Codable {
                    let id: String
                    let name: String
                    let maxTokens: Int?
                    
                    enum CodingKeys: String, CodingKey {
                        case id
                        case name
                        case maxTokens = "max_tokens"
                    }
                }
                let models: [Model]
            }
            
            let modelResponse = try JSONDecoder().decode(ModelResponse.self, from: data)
            let claudeModels = modelResponse.models
                .map { $0.id }
                .filter { $0.contains("claude") }
                .sorted()
            
            Logger.debug("✅ Fetched \(claudeModels.count) Claude models")
            return claudeModels
        } catch {
            Logger.error("x Failed to fetch Claude models: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Fetches available Grok models from xAI API
    static func fetchGrokModels(apiKey: String) async -> [String] {
        // Grok API structure is similar to OpenAI
        let url = URL(string: "https://api.groq.com/v1/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 900.0
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Logger.warning("Failed to fetch Grok models: HTTP \(response)")
                return []
            }
            
            struct ModelResponse: Codable {
                struct Model: Codable {
                    let id: String
                }
                let data: [Model]
            }
            
            let modelResponse = try JSONDecoder().decode(ModelResponse.self, from: data)
            let grokModels = modelResponse.data
                .map { $0.id }
                .filter { $0.contains("grok") }
                .sorted()
            
            Logger.debug("✅ Fetched \(grokModels.count) Grok models")
            return grokModels
        } catch {
            Logger.error("x Failed to fetch Grok models: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Fetches available Gemini models from Google AI API
    static func fetchGeminiModels(apiKey: String) async -> [String] {
        // Google's API for listing models
        // Need to ensure API key is properly encoded in URL
        guard let encodedApiKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            Logger.error("x Failed to encode Gemini API key for URL")
            return []
        }
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1/models?key=\(encodedApiKey)") else {
            Logger.error("x Failed to create URL for Gemini API")
            return []
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 900.0
        request.httpMethod = "GET"
        
        // Log key details for debugging (without revealing the entire key)
        Logger.debug("🔑 Gemini API request with key: \(apiKey.prefix(4))..., URL: \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Logger.warning("Failed to fetch Gemini models: HTTP \(response)")
                return []
            }
            
            struct ModelResponse: Codable {
                struct Model: Codable {
                    let name: String
                    let displayName: String?
                    let supportedGenerationMethods: [String]?
                    
                    enum CodingKeys: String, CodingKey {
                        case name
                        case displayName = "displayName"
                        case supportedGenerationMethods = "supportedGenerationMethods"
                    }
                }
                let models: [Model]
            }
            
            let modelResponse = try JSONDecoder().decode(ModelResponse.self, from: data)
            let geminiModels = modelResponse.models
                .map { $0.name.components(separatedBy: "/").last ?? $0.name }
                .filter { $0.contains("gemini") }
                .sorted()
            
            Logger.debug("✅ Fetched \(geminiModels.count) Gemini models")
            return geminiModels
        } catch {
            Logger.error("x Failed to fetch Gemini models: \(error.localizedDescription)")
            return []
        }
    }
}
