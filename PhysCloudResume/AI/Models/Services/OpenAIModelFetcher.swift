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
        // Sanitize and return corrected model name
        return sanitizeModelName(rawModelString)
    }
    
    /// Sanitizes a model name by correcting common corrupted variants
    /// - Parameter modelName: The potentially corrupted model name
    /// - Returns: The corrected model name
    static func sanitizeModelName(_ modelName: String) -> String {
        // Handle common corrupted model names
        switch modelName {
        case "o4-mini", "4o-mini", "gpt4o-mini":
            return AIModels.gpt4o_mini // "gpt-4o-mini"
        case "o4", "4o", "gpt4o":
            return AIModels.gpt4o // "gpt-4o"
        case "o4-latest", "4o-latest", "gpt4o-latest":
            return AIModels.gpt4o_latest // "gpt-4o-2024-05-13"
        case "gpt4-turbo", "gpt-4turbo":
            return "gpt-4-turbo"
        case "gpt35-turbo", "gpt-35-turbo":
            return "gpt-3.5-turbo"
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
                    // More comprehensive filtering for chat models
                    let id = modelId.lowercased()
                    return id.contains("gpt-4o") ||     // GPT-4o variants
                           id.contains("gpt-4") ||      // GPT-4 variants
                           id.contains("gpt-3.5") ||    // GPT-3.5 variants
                           id.contains("o1-") ||        // Reasoning models
                           id.contains("o3-") ||        // Future o3 models
                           id.contains("mini")          // Mini variants
                }
                .sorted()

            Logger.debug("✅ Fetched \(chatModels.count) OpenAI models")
            return chatModels
        } catch {
            Logger.error("❌ Failed to fetch OpenAI models: \(error.localizedDescription)")
            return []
        }
    }


}
