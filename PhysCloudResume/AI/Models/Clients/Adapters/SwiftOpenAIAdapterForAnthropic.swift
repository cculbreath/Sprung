//
//  SwiftOpenAIAdapterForAnthropic.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftOpenAI

/// Claude (Anthropic)-specific adapter for SwiftOpenAI
class SwiftOpenAIAdapterForAnthropic: BaseSwiftOpenAIAdapter {
    /// The app state that contains user settings and preferences
    private weak var appState: AppState?
    
    /// Initializes the adapter with Claude configuration and app state
    /// - Parameters:
    ///   - config: The provider configuration
    ///   - appState: The application state
    init(config: LLMProviderConfig, appState: AppState) {
        self.appState = appState
        super.init(config: config)
        
        // Log Claude configuration for debugging
        Logger.debug("👤 Claude adapter configured with:")
        Logger.debug("  - Base URL: \(config.baseURL ?? "nil")")
        Logger.debug("  - API Version: \(config.apiVersion ?? "nil")")
    }
    
    /// Executes a query against the Claude API using SwiftOpenAI
    /// - Parameter query: The query to execute
    /// - Returns: The response from the Claude API
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
                guard let contentData = content.data(using: .utf8) else {
                    throw AppLLMError.unexpectedResponseFormat
                }
                return .structured(contentData)
            } else {
                return .text(content)
            }
        } catch {
            // Process API error using base class helper
            throw processAPIError(error)
        }
    }
}
