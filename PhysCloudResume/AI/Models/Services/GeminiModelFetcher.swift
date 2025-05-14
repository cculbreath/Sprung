//
//  GeminiModelFetcher.swift
//  PhysCloudResume
//
//  Created by Claude on 5/13/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Provides model fetching and conversion utilities for Gemini models
class GeminiModelFetcher {
    /// Fetches available Gemini models from the API
    static func fetchAvailableModels(apiKey: String) async -> [String] {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1/models?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 300 // default is 30 seconds
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            struct ModelResponse: Codable {
                struct Model: Codable {
                    let name: String
                    let displayName: String?
                    let supportedGenerationMethods: [String]?
                }

                let models: [Model]
            }

            let modelResponse = try JSONDecoder().decode(ModelResponse.self, from: data)
            
            // Filter for text and vision models that support generateContent
            let chatModels = modelResponse.models
                .filter { model in
                    model.supportedGenerationMethods?.contains("generateContent") == true
                }
                .map { model in
                    // Extract just the model name from the full path (e.g., "models/gemini-1.5-pro")
                    let fullName = model.name
                    let components = fullName.components(separatedBy: "/")
                    return components.last ?? fullName
                }
                .sorted()

            return chatModels
        } catch {
            print("Error fetching Gemini models: \(error)")
            return []
        }
    }
}
