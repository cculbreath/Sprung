//
//  BaseSwiftOpenAIAdapter.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftOpenAI

/// Base class for SwiftOpenAI-based adapters
/// Handles common initialization and message conversion logic
class BaseSwiftOpenAIAdapter: AppLLMClientProtocol {
    /// The SwiftOpenAI service instance
    let swiftService: OpenAIService
    
    /// The provider configuration
    let config: LLMProviderConfig
    
    /// Initializes the adapter with a provider configuration
    /// - Parameter config: The LLM provider configuration
    init(config: LLMProviderConfig) {
        self.config = config
        
        // Configure SwiftOpenAI service
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 900.0 // 15 minutes for reasoning models
        
        // Configure the service based on provider settings
        if config.providerType == AIModels.Provider.claude {
            // Special handling for Claude API
            Logger.debug("👤 Creating Claude-specific API client")
            
            // Setup extra headers with anthropic-version
            var anthropicHeaders: [String: String] = config.extraHeaders ?? [:]
            anthropicHeaders["anthropic-version"] = "2023-06-01"
            
            // Create the service using the Anthropic API key via standard Authorization header
            swiftService = OpenAIServiceFactory.service(
                apiKey: config.apiKey,
                overrideBaseURL: config.baseURL ?? "https://api.anthropic.com", // Provide a default if nil
                configuration: urlConfig,
                proxyPath: config.proxyPath,
                overrideVersion: config.apiVersion ?? "v1", // Provide a default if nil
                extraHeaders: anthropicHeaders
            )
        } else {
            // Standard configuration for OpenAI-compatible APIs
            Logger.debug("🔄 Creating API client for provider: \(config.providerType)")
            
            // Determine the default base URL based on provider
            let baseURL: String
            let apiVersion: String
            
            switch config.providerType {
            case AIModels.Provider.gemini:
                baseURL = config.baseURL ?? "https://generativelanguage.googleapis.com"
                apiVersion = config.apiVersion ?? "v1beta"
            case AIModels.Provider.grok:
                if config.apiKey.hasPrefix("xai-") {
                    baseURL = config.baseURL ?? "https://api.x.ai"
                } else {
                    baseURL = config.baseURL ?? "https://api.groq.com"
                }
                apiVersion = config.apiVersion ?? "v1"
            case AIModels.Provider.openai:
                baseURL = config.baseURL ?? "https://api.openai.com"
                apiVersion = config.apiVersion ?? "v1"
            default:
                baseURL = config.baseURL ?? "https://api.openai.com"
                apiVersion = config.apiVersion ?? "v1"
            }
            
            // Create the service with proper handling of parameters
            swiftService = OpenAIServiceFactory.service(
                apiKey: config.apiKey,
                overrideBaseURL: baseURL,
                configuration: urlConfig,
                proxyPath: config.proxyPath,
                overrideVersion: apiVersion,
                extraHeaders: config.extraHeaders
            )
        }
    }
    
    /// Default implementation of executeQuery - to be overridden by subclasses
    /// - Parameter query: The query to execute
    /// - Returns: The query response
    func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
        // Base class implementation, should be overridden by subclasses
        throw AppLLMError.clientError("BaseSwiftOpenAIAdapter.executeQuery must be overridden by subclasses")
    }
    
    // MARK: - Helper methods for subclasses
    
    /// Converts an AppLLMMessage to SwiftOpenAI's ChatCompletionParameters.Message
    /// - Parameter message: The message to convert
    /// - Returns: The converted message
    func convertToSwiftOpenAIMessage(_ message: AppLLMMessage) -> ChatCompletionParameters.Message {
        let role: ChatCompletionParameters.Message.Role
        switch message.role {
        case .system: role = .system
        case .user: role = .user
        case .assistant: role = .assistant
        }
        
        // Handle simple text-only message
        if message.contentParts.count == 1, case let .text(content) = message.contentParts[0] {
            return ChatCompletionParameters.Message(
                role: role,
                content: .text(content)
            )
        }
        
        // Handle multimodal message (text + images)
        else {
            var contents: [ChatCompletionParameters.Message.ContentType.MessageContent] = []
            
            // Convert each content part
            for part in message.contentParts {
                switch part {
                case let .text(content):
                    contents.append(.text(content))
                case let .imageUrl(base64Data, mimeType):
                    let imageUrlString = "data:\(mimeType);base64,\(base64Data)"
                    if let imageURL = URL(string: imageUrlString) {
                        let imageDetail = ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(
                            url: imageURL,
                            detail: "high"
                        )
                        contents.append(.imageUrl(imageDetail))
                    } else {
                        Logger.error("Failed to create URL from image data")
                    }
                }
            }
            
            // Create message with content array
            return ChatCompletionParameters.Message(
                role: role,
                content: .contentArray(contents)
            )
        }
    }
    
    /// Creates a JSONSchema for a Decodable type (simplified version)
    /// - Parameter type: The Decodable type
    /// - Returns: A JSONSchema object
    func createJSONSchema(for type: Decodable.Type) -> SwiftOpenAI.JSONSchema {
        // This is a simplified implementation - for production code, you would want
        // to use runtime reflection or code generation to build the schema dynamically
        
        if type == RevisionsContainer.self {
            return SwiftOpenAI.JSONSchema(
                type: .object,
                properties: [
                    "revArray": SwiftOpenAI.JSONSchema(
                        type: .array,
                        items: SwiftOpenAI.JSONSchema(
                            type: .object,
                            properties: [
                                "id": SwiftOpenAI.JSONSchema(type: .string),
                                "oldValue": SwiftOpenAI.JSONSchema(type: .string),
                                "newValue": SwiftOpenAI.JSONSchema(type: .string),
                                "valueChanged": SwiftOpenAI.JSONSchema(type: .boolean),
                                "why": SwiftOpenAI.JSONSchema(type: .string),
                                "isTitleNode": SwiftOpenAI.JSONSchema(type: .boolean),
                                "treePath": SwiftOpenAI.JSONSchema(type: .string)
                            ],
                            required: ["id", "oldValue", "newValue", "valueChanged", "why", "isTitleNode", "treePath"]
                        )
                    )
                ],
                required: ["revArray"]
            )
        }
        
        if type == BestCoverLetterResponse.self {
            return SwiftOpenAI.JSONSchema(
                type: .object,
                properties: [
                    "strengthAndVoiceAnalysis": SwiftOpenAI.JSONSchema(
                        type: .string,
                        description: "Brief summary ranking/assessment of each letter's strength and voice"
                    ),
                    "bestLetterUuid": SwiftOpenAI.JSONSchema(
                        type: .string,
                        description: "UUID of the selected best cover letter"
                    ),
                    "verdict": SwiftOpenAI.JSONSchema(
                        type: .string,
                        description: "Reason for the ultimate choice"
                    )
                ],
                required: ["strengthAndVoiceAnalysis", "bestLetterUuid", "verdict"]
            )
        }
        
        // Add more types as needed...
        
        // Fallback - empty schema
        return SwiftOpenAI.JSONSchema(type: .object)
    }
    
    /// Parses a JSONSchema string into a SwiftOpenAI.JSONSchema object
    /// - Parameter jsonString: The schema as a JSON string
    /// - Returns: The parsed JSONSchema
    func parseJSONSchemaString(_ jsonString: String) -> SwiftOpenAI.JSONSchema? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        
        do {
            // Parse JSON into dictionary
            let jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let dict = jsonDict else { return nil }
            
            // Extract type
            let typeString = dict["type"] as? String
            let type: SwiftOpenAI.JSONSchemaType?
            switch typeString {
            case "string": type = .string
            case "object": type = .object
            case "array": type = .array
            case "boolean": type = .boolean
            case "integer": type = .integer
            case "number": type = .number
            case "null": type = .null
            default: type = nil
            }
            
            // Extract properties if this is an object
            var properties: [String: SwiftOpenAI.JSONSchema]?
            if typeString == "object", let props = dict["properties"] as? [String: [String: Any]] {
                properties = [:]
                for (key, propDict) in props {
                    if let propType = propDict["type"] as? String {
                        let propSchemaType: SwiftOpenAI.JSONSchemaType?
                        switch propType {
                        case "string": propSchemaType = .string
                        case "object": propSchemaType = .object
                        case "array": propSchemaType = .array
                        case "boolean": propSchemaType = .boolean
                        case "integer": propSchemaType = .integer
                        case "number": propSchemaType = .number
                        default: propSchemaType = nil
                        }
                        
                        properties?[key] = SwiftOpenAI.JSONSchema(
                            type: propSchemaType,
                            description: propDict["description"] as? String
                        )
                    }
                }
            }
            
            return SwiftOpenAI.JSONSchema(
                type: type,
                description: dict["description"] as? String,
                properties: properties,
                required: dict["required"] as? [String],
                additionalProperties: dict["additionalProperties"] as? Bool ?? false
            )
        } catch {
            Logger.error("Error parsing JSON schema: \(error.localizedDescription)")
            return nil
        }
    }
}
