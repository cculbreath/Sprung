//
//  OpenAIModelFetcher.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/7/25.
//

import Foundation
import SwiftOpenAI

/// Provides model fetching and conversion utilities for OpenAI models
class OpenAIModelFetcher {
    /// Get the configured preferred model string from UserDefaults
    static func getPreferredModelString() -> String {
        let modelString = UserDefaults.standard.string(forKey: "preferredOpenAIModel") ?? "gpt-4o-2024-08-06"
        return modelString
    }
    
    /// Get the configured preferred model as a SwiftOpenAI Model enum
    static func getPreferredModel() -> Model {
        let modelString = getPreferredModelString()
        let model = modelFromString(modelString)
        print("Retrieved preferred model: \(modelString) → \(model)")
        return model
    }

    static func fetchAvailableModels(apiKey: String) async -> [String] {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 300 // default is 30 seconds
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Error fetching models: invalid response")
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
                .filter { $0.contains("gpt") || $0.contains("o1") || $0.contains("o3") }
                .sorted()

            return chatModels
        } catch {
            print("Error fetching models: \(error)")
            return []
        }
    }

    static func modelFromString(_ modelId: String) -> Model {
        // Array of known enum members (ignoring the .custom case)
        let knownModels: [Model] = [
            .gpt4oAudioPreview,
            .o1Preview,
            .o1Mini,
            .gpt4o,
            .gpt4o20240513,
            .gpt4o20240806,
            .gpt4o20241120,
            .gpt4omini,
            .gpt35Turbo,
            .gpt35Turbo1106,
            .gpt35Turbo0125,
            .gpt4,
            .gpt41106Preview,
            .gpt35Turbo0613,
            .gpt35Turbo16k0613,
            .gpt4VisionPreview,
            .dalle2,
            .dalle3,
            .gpt4TurboPreview,
            .gpt40125Preview,
            .gpt4Turbo20240409,
            .gpt4turbo,
        ]

        // Build a dictionary from the enum’s computed string values.
        // Note: Each key includes dashes as per the canonical API format.
        let mapping = Dictionary(uniqueKeysWithValues: knownModels.map { ($0.value, $0) })

        // If the modelId matches one of our keys (including the dashes) we return that case;
        // otherwise, we fall back to a custom model.
        return mapping[modelId] ?? .custom(modelId)
    }

    /// Convert a model string to the corresponding SwiftOpenAI Model enum
    
    /// MacPaw/OpenAI model mapping (will be used when we integrate MacPaw/OpenAI)
    static func getMacPawModelString(_ modelId: String) -> String {
        // MacPaw/OpenAI uses string constants for models
        // This is a placeholder for future implementation
        return modelId
    }
}
