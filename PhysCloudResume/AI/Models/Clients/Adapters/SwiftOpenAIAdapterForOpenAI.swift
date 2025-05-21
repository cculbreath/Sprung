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
        // Convert AppLLMMessages to SwiftOpenAI Messages
        let swiftMessages = query.messages.map { convertToSwiftOpenAIMessage($0) }
        
        // Create model from identifier
        let model = SwiftOpenAI.Model.from(query.modelIdentifier)
        
        // Handle structured JSON output if desired
        var swiftResponseFormat: SwiftOpenAI.ResponseFormat?
        if let responseType = query.desiredResponseType {
            // If a specific JSON schema was provided
            if let jsonSchema = query.jsonSchema, let schema = parseJSONSchemaString(jsonSchema) {
                swiftResponseFormat = .jsonSchema(
                    SwiftOpenAI.JSONSchemaResponseFormat(
                        name: String(describing: responseType),
                        strict: true,
                        schema: schema
                    )
                )
            }
            // Otherwise use the simpler JSON object format or create schema from type
            else {
                swiftResponseFormat = .jsonObject
            }
        }
        
        // Build chat completion parameters without a temperature parameter (use server default)
        var parameters = ChatCompletionParameters(
            messages: swiftMessages,
            model: model,
            responseFormat: swiftResponseFormat
        )

        // For reasoning models (o-series models), constrain reasoning effort to medium
        let idLower = query.modelIdentifier.lowercased()
        if idLower.contains("gpt-4o") || idLower.contains("gpt-4-turbo") {
            parameters.reasoningEffort = "medium"
        }
        
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
        } catch let apiError as SwiftOpenAI.APIError {
            switch apiError {
            case .responseUnsuccessful(let description, let statusCode):
                Logger.error("OpenAI API error (status code \(statusCode)): \(description)")
                throw AppLLMError.clientError("OpenAI API error (status code \(statusCode)): \(description)")
            default:
                Logger.error("OpenAI API error: \(apiError.localizedDescription)")
                throw AppLLMError.clientError("OpenAI API error: \(apiError.localizedDescription)")
            }
        } catch {
            Logger.error("OpenAI API error: \(error.localizedDescription)")
            throw AppLLMError.clientError("OpenAI API error: \(error.localizedDescription)")
        }
    }
}
