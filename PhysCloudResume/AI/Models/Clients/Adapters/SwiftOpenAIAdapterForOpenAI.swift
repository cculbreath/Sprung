//
//  SwiftOpenAIAdapterForOpenAI.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftOpenAI

/// OpenAI-specific adapter for SwiftOpenAI
class SwiftOpenAIAdapterForOpenAI: BaseSwiftOpenAIAdapter {
    /// The app state that contains user settings and preferences
    private weak var appState: AppState?
    
    /// Initializes the adapter with OpenAI configuration and app state
    /// - Parameters:
    ///   - config: The provider configuration
    ///   - appState: The application state
    init(config: LLMProviderConfig, appState: AppState) {
        self.appState = appState
        super.init(config: config)
    }
    
    /// Executes a query against the OpenAI API using SwiftOpenAI
    /// - Parameter query: The query to execute
    /// - Returns: The response from the OpenAI API
    override func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
        // Prepare parameters using base class helper
        let parameters = prepareChatParameters(for: query)
        
        do {
            // Execute the chat request
            let result = try await swiftService.startChat(parameters: parameters)
            
            // Process the result
            guard let content = result.choices?.first?.message?.content else {
                throw AppLLMError.unexpectedResponseFormat
            }
            
            // Check if we're expecting a structured response
            if query.desiredResponseType != nil {
                // Convert the content string to Data for structured decoding
                guard let contentData = content.data(using: .utf8) else {
                    throw AppLLMError.unexpectedResponseFormat
                }
                return .structured(contentData)
            } else {
                // Return text response
                return .text(content)
            }
        } catch {
            // Process API error using base class helper
            throw processAPIError(error)
        }
    }
}
