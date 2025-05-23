//
//  SwiftOpenAIAdapterForGrok.swift
//  PhysCloudResume
//
//  Created by Claude on 5/22/25.
//

import Foundation
import SwiftOpenAI

/// Grok-specific adapter for SwiftOpenAI
class SwiftOpenAIAdapterForGrok: BaseSwiftOpenAIAdapter {
    /// The app state that contains user settings and preferences
    private weak var appState: AppState?
    
    /// Initializes the adapter with Grok configuration and app state
    /// - Parameters:
    ///   - config: The provider configuration
    ///   - appState: The application state
    init(config: LLMProviderConfig, appState: AppState) {
        self.appState = appState
        super.init(config: config)
    }
    
    /// Executes a query against the Grok API using SwiftOpenAI
    /// - Parameter query: The query to execute
    /// - Returns: The response from the Grok API
    override func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
        // Determine if this is a request for structured output
        let isStructuredOutput = query.desiredResponseType != nil
        
        // Log the model and whether this is a structured output request
        Logger.debug("Executing \(isStructuredOutput ? "structured" : "text") query with Grok model: \(query.modelIdentifier)")
        
        // Prepare parameters for the model
        let parameters = prepareChatParameters(for: query)
        
        do {
            // Execute the chat request
            let result = try await swiftService.startChat(parameters: parameters)
            
            // Process the result
            guard let content = result.choices?.first?.message?.content else {
                throw AppLLMError.unexpectedResponseFormat
            }
            
            // Check if we're expecting a structured response
            if isStructuredOutput {
                // Try to extract clean JSON if the response isn't already well-formed
                if let jsonContent = extractJSONFromContent(content) {
                    Logger.debug("Using extracted JSON: \(String(describing: jsonContent.prefix(100)))...")
                    return .structured(jsonContent.data(using: .utf8) ?? Data())
                } else {
                    // Convert the content string to Data for structured decoding
                    guard let contentData = content.data(using: .utf8) else {
                        throw AppLLMError.unexpectedResponseFormat
                    }
                    
                    // Try to validate that it's valid JSON
                    do {
                        _ = try JSONSerialization.jsonObject(with: contentData)
                        return .structured(contentData)
                    } catch {
                        Logger.error("Invalid JSON returned from Grok: \(error.localizedDescription)")
                        throw AppLLMError.clientError("Grok returned invalid JSON: \(error.localizedDescription)")
                    }
                }
            } else {
                // Return text response
                return .text(content)
            }
        } catch {
            // Process API error using base class helper
            throw processAPIError(error)
        }
    }
    
    /// Extracts valid JSON from the content string
    /// - Parameter content: The raw content string that may contain JSON
    /// - Returns: Cleaned JSON string or nil if extraction fails
    private func extractJSONFromContent(_ content: String) -> String? {
        // Look for the first { and the last } to extract the JSON object
        guard let startIndex = content.firstIndex(of: "{"),
              let endIndex = content.lastIndex(of: "}"),
              startIndex < endIndex else {
            return nil
        }
        
        // Extract the JSON substring
        let jsonSubstring = content[startIndex...endIndex]
        let jsonString = String(jsonSubstring)
        
        // Validate that it's valid JSON
        guard let data = jsonString.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        
        return jsonString
    }
}
