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
    /// Get the configured preferred model string from UserDefaults
    static func getPreferredModelString() -> String {
        // Get the preferred model directly
        let modelString = UserDefaults.standard.string(forKey: "preferredLLMModel") ?? AIModels.gpt4o_latest
        return modelString
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
                .filter {
                        $0.contains("o1") ||
                        $0.contains("o3") ||
                        $0.contains("o4") ||
                        $0.contains("4.5") ||
                        $0.contains("4o") ||
                        $0.contains("mini")
                }
                .sorted()

            return chatModels
        } catch {
            return []
        }
    }


}
