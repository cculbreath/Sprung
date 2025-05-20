//
//  SwiftOpenAIClient.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/18/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI
import SwiftOpenAI
// Also import our type definitions

/// Implementation of OpenAIClientProtocol using SwiftOpenAI library
class SwiftOpenAIClient: OpenAIClientProtocol {
    private let swiftService: OpenAIService
    private let apiKeyValue: String
    
    /// The API key used for requests
    var apiKey: String {
        apiKeyValue
    }
    
    /// Initializes a new client with the given custom configuration
    /// - Parameter configuration: The custom configuration to use for requests
    required init(configuration: OpenAIConfiguration) {
        apiKeyValue = configuration.token ?? "none"
        
        // Configure SwiftOpenAI service
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = configuration.timeoutInterval
        
        // Create SwiftOpenAI service based on host
        if configuration.host == "api.anthropic.com" {
            // Special handling for Claude API
            Logger.debug("👤 Creating Claude-specific API client")
            
            // Setup the URL session configuration with the required headers
            var configHeaders = urlConfig.httpAdditionalHeaders as? [String: String] ?? [:]
            configHeaders["anthropic-version"] = "2023-06-01"
            configHeaders["x-api-key"] = configuration.token ?? ""
            configHeaders["Content-Type"] = "application/json"
            
            // Remove any Authorization header to prevent conflicts
            configHeaders.removeValue(forKey: "Authorization")
            
            // Set the headers back on the config
            urlConfig.httpAdditionalHeaders = configHeaders
            
            // Setup the extra headers for the service creation
            var anthropicHeaders = [
                "anthropic-version": "2023-06-01",
                "x-api-key": configuration.token ?? ""
            ]
            
            // Add any custom headers from configuration
            for (key, value) in configuration.customHeaders {
                anthropicHeaders[key] = value
            }
            
            Logger.debug("🔧 Creating Claude client with multiple authentication methods")
            Logger.debug("🔑 Using x-api-key: \(String((configuration.token ?? "").prefix(4)))...")
            
            // Create the service with empty API key and proper headers
            swiftService = OpenAIServiceFactory.service(
                apiKey: "", // Claude doesn't use standard Bearer token
                overrideBaseURL: "https://\(configuration.host)",
                configuration: urlConfig,
                proxyPath: nil,
                overrideVersion: "v1",
                extraHeaders: anthropicHeaders
            )
        } else if configuration.host == "api.groq.com" || configuration.host == "api.x.ai" {
            // Special handling for Grok API
            Logger.debug("⚡ Creating Grok-specific API client")
            swiftService = OpenAIServiceFactory.service(
                apiKey: configuration.token ?? "",
                overrideBaseURL: "https://\(configuration.host)",
                configuration: urlConfig,
                proxyPath: nil,
                overrideVersion: "v1",
                extraHeaders: configuration.customHeaders
            )
        } else if configuration.host == "generativelanguage.googleapis.com" {
            // Special handling for Gemini API using OpenAI-compatible endpoint
            Logger.debug("🌟 Creating Gemini-specific API client")
            let versionPath = configuration.basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // Pass the API key as bearer token; no x-api-key needed
            swiftService = OpenAIServiceFactory.service(
                apiKey: configuration.token ?? "",
                overrideBaseURL: "https://\(configuration.host)",
                configuration: urlConfig,
                proxyPath: nil,
                overrideVersion: versionPath,
                extraHeaders: configuration.customHeaders
            )
        } else if configuration.host != "api.openai.com" {
            // Other custom URL configuration
            Logger.debug("🔄 Creating custom API client for host: \(configuration.host)")
            swiftService = OpenAIServiceFactory.service(
                apiKey: configuration.token ?? "",
                overrideBaseURL: "https://\(configuration.host)",
                configuration: urlConfig,
                proxyPath: nil,
                overrideVersion: configuration.basePath.replacingOccurrences(of: "/", with: ""),
                extraHeaders: configuration.customHeaders
            )
        } else {
            // Standard OpenAI configuration
            Logger.debug("🤖 Creating standard OpenAI API client")
            swiftService = OpenAIServiceFactory.service(
                apiKey: configuration.token ?? "",
                organizationID: configuration.organizationIdentifier,
                configuration: urlConfig
            )
        }
    }
    
    /// Initializes a new client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    required init(apiKey: String) {
        apiKeyValue = apiKey
        
        // Create SwiftOpenAI service with standard configuration
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 900.0 // 15 minutes for reasoning models
        
        swiftService = OpenAIServiceFactory.service(
            apiKey: apiKey,
            configuration: urlConfig
        )
    }
    
    /// Initializes a client for a specific model with appropriate configuration
    /// - Parameters:
    ///   - model: The model to use
    ///   - apiKeys: Dictionary of API keys by provider
    /// - Returns: A client configured for the specified model, or nil if no API key is available
    static func clientForModel(model: String, apiKeys: [String: String]) -> OpenAIClientProtocol? {
        let provider = AIModels.providerForModel(model)
        
        switch provider {
        case AIModels.Provider.claude:
            if let apiKey = apiKeys[AIModels.Provider.claude],
               let validKey = ModelFilters.validateAPIKey(apiKey, for: AIModels.Provider.claude) {
                let config = OpenAIConfiguration.forClaude(apiKey: validKey)
                return SwiftOpenAIClient(configuration: config)
            }
        case AIModels.Provider.grok:
            if let apiKey = apiKeys[AIModels.Provider.grok],
               let validKey = ModelFilters.validateAPIKey(apiKey, for: AIModels.Provider.grok) {
                let config = OpenAIConfiguration.forGrok(apiKey: validKey)
                return SwiftOpenAIClient(configuration: config)
            }
        case AIModels.Provider.gemini:
            if let apiKey = apiKeys[AIModels.Provider.gemini],
               let validKey = ModelFilters.validateAPIKey(apiKey, for: AIModels.Provider.gemini) {
                let config = OpenAIConfiguration.forGemini(apiKey: validKey)
                return SwiftOpenAIClient(configuration: config)
            }
        case AIModels.Provider.openai:
            if let apiKey = apiKeys[AIModels.Provider.openai],
               let validKey = ModelFilters.validateAPIKey(apiKey, for: AIModels.Provider.openai) {
                return SwiftOpenAIClient(apiKey: validKey)
            }
        default:
            // Default to OpenAI if provider isn't recognized
            if let apiKey = apiKeys[AIModels.Provider.openai],
               let validKey = ModelFilters.validateAPIKey(apiKey, for: AIModels.Provider.openai) {
                return SwiftOpenAIClient(apiKey: validKey)
            }
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    /// Converts our ResponseFormat to SwiftOpenAI's ChatCompletionParameters.ResponseFormat
    /// - Parameter format: Our ResponseFormat to convert
    /// - Returns: The converted SwiftOpenAI format
    private func convertToSwiftOpenAIResponseFormat(_ format: AIResponseFormat?) -> SwiftOpenAI.ResponseFormat? {
        guard let format = format else { return nil }
        
        switch format {
        case .text:
            return nil // Plain text is the default
        case .jsonObject:
            return .jsonObject
        case .jsonSchema(let jsonSchema):
            let swiftSchema = SwiftOpenAI.JSONSchema(
                type: .object,
                properties: convertPropertiesToSwiftOpenAI(jsonSchema.schema),
                required: [],
                additionalProperties: true
            )
            
            return .jsonSchema(SwiftOpenAI.JSONSchemaResponseFormat(
                name: jsonSchema.name,
                strict: jsonSchema.strict,
                schema: swiftSchema
            ))
        }
    }
    
    /// Converts dictionary properties to SwiftOpenAI format
    /// - Parameter properties: The schema properties
    /// - Returns: Converted properties
    private func convertPropertiesToSwiftOpenAI(_ schemaDict: [String: Any]) -> [String: SwiftOpenAI.JSONSchema] {
        var result: [String: SwiftOpenAI.JSONSchema] = [:]
        
        for (key, value) in schemaDict {
            if let dictValue = value as? [String: Any] {
                // Convert the property value based on what we have
                if let typeString = dictValue["type"] as? String {
                    let type: SwiftOpenAI.JSONSchemaType? = {
                        switch typeString {
                        case "string": return .string
                        case "object": return .object
                        case "array": return .array
                        case "boolean": return .boolean
                        case "integer": return .integer
                        case "number": return .number
                        case "null": return .null
                        default: return nil
                        }
                    }()
                    
                    // Extract description if available
                    let description = dictValue["description"] as? String
                    
                    // Convert nested properties if this is an object
                    var properties: [String: SwiftOpenAI.JSONSchema]? = nil
                    if typeString == "object", let propsDict = dictValue["properties"] as? [String: Any] {
                        properties = convertPropertiesToSwiftOpenAI(propsDict)
                    }
                    
                    // Extract required fields if available
                    let required = dictValue["required"] as? [String]
                    
                    // Extract additional properties flag
                    let additionalProps = dictValue["additionalProperties"] as? Bool ?? false
                    
                    // Create the JSON schema
                    result[key] = SwiftOpenAI.JSONSchema(
                        type: type,
                        description: description,
                        properties: properties,
                        required: required,
                        additionalProperties: additionalProps
                    )
                }
            }
        }
        
        return result
    }
    
    /// Converts our ChatMessage to SwiftOpenAI's ChatCompletionParameters.Message
    /// - Parameter message: The message to convert
    /// - Returns: The converted message
    private func convertToSwiftOpenAIMessage(_ message: ChatMessage) -> ChatCompletionParameters.Message {
        let role: ChatCompletionParameters.Message.Role
        switch message.role {
        case .system:
            role = .system
        case .user:
            role = .user
        case .assistant:
            role = .assistant
        }
        
        // Handle text-only messages
        if message.imageData == nil {
            return ChatCompletionParameters.Message(
                role: role,
                content: .text(message.content)
            )
        }
        
        // Handle messages with images (vision models)
        else {
            let textContent = ChatCompletionParameters.Message.ContentType.MessageContent.text(message.content)
            let imageUrlString = "data:image/png;base64,\(message.imageData!)"
            
            // Create image URL
            guard let imageURL = URL(string: imageUrlString) else {
                // Fallback to text-only if URL creation fails
                return ChatCompletionParameters.Message(
                    role: role,
                    content: .text(message.content)
                )
            }
            
            let imageDetail = ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(
                url: imageURL,
                detail: "high"
            )
            let imageContent = ChatCompletionParameters.Message.ContentType.MessageContent.imageUrl(imageDetail)
            
            return ChatCompletionParameters.Message(
                role: role,
                content: .contentArray([textContent, imageContent])
            )
        }
    }
    
    /// Maps voice string to SwiftOpenAI's AudioSpeechParameters.Voice
    /// - Parameter voice: The voice string
    /// - Returns: The mapped voice enum
    private func mapVoiceToSwiftOpenAI(_ voice: String) -> AudioSpeechParameters.Voice {
        switch voice.lowercased() {
        case "alloy": return .alloy
        case "echo": return .echo
        case "fable": return .fable
        case "onyx": return .onyx
        case "nova": return .nova
        case "shimmer": return .shimmer
        case "ash": return .ash
        case "coral": return .coral
        case "sage": return .sage
        default: return .alloy // Default fallback voice
        }
    }
    
    /// Maps SwiftOpenAI errors to our error format
    /// - Parameter error: The error to map
    /// - Returns: Mapped error
    private func mapSwiftOpenAIError(_ error: Error) -> Error {
        if let apiError = error as? SwiftOpenAI.APIError {
            switch apiError {
            case .responseUnsuccessful(let description, let statusCode):
                return NSError(domain: "OpenAIAPI", code: statusCode,
                             userInfo: [NSLocalizedDescriptionKey: description])
            case .invalidData:
                return NSError(domain: "SwiftOpenAIClient", code: 1002,
                             userInfo: [NSLocalizedDescriptionKey: "No valid response content"])
            case .jsonDecodingFailure(let description):
                return NSError(domain: "SwiftOpenAIClient", code: 1004,
                             userInfo: [NSLocalizedDescriptionKey: "JSON decoding failed: \(description)"])
            default:
                return NSError(domain: "SwiftOpenAIClient", code: 1000,
                             userInfo: [NSLocalizedDescriptionKey: apiError.displayDescription])
            }
        }
        return error
    }
    
    // MARK: - Chat Completion Methods
    
    /// Sends a chat completion request using async/await
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - responseFormat: Optional response format (e.g., JSON mode)
    ///   - temperature: Controls randomness (0-1)
    /// - Returns: A completion with the model's response
    func sendChatCompletionAsync(
        messages: [ChatMessage],
        model: String,
        responseFormat: AIResponseFormat?,
        temperature: Double?
    ) async throws -> ChatCompletionResponse {
        Logger.debug("🤖 SwiftOpenAI: Starting chat completion for model \(model)")
        
        // Get the provider for the model
        let provider = AIModels.providerForModel(model)
        
        // For Claude models, use a direct implementation that works with their API
        if provider == AIModels.Provider.claude {
            Logger.debug("📡 Using direct Claude API implementation for model: \(model)")
            return try await sendClaudeCompletionAsync(messages: messages, model: model, temperature: temperature)
        }
        
        // Otherwise use the standard SwiftOpenAI approach
        let swiftMessages = messages.map { convertToSwiftOpenAIMessage($0) }
        let swiftResponseFormat = convertToSwiftOpenAIResponseFormat(responseFormat)
        
        // Build chat completion parameters
        var parameters = ChatCompletionParameters(
            messages: swiftMessages,
            model: SwiftOpenAI.Model.from(model),
            responseFormat: swiftResponseFormat,
            temperature: temperature
        )
        // For reasoning models (o-series, Grok mini, and Gemini v2+ variants), constrain reasoning effort to medium
        let idLower = model.lowercased()
        if idLower.starts(with: "o")
            || (idLower.contains("grok") && idLower.contains("mini"))
            || idLower.starts(with: "gemini-2") {
            parameters.reasoningEffort = "medium"
        }
        
        do {
            let result = try await swiftService.startChat(parameters: parameters)
            
            guard let content = result.choices?.first?.message?.content else {
                Logger.debug("❌ SwiftOpenAI: No content in chat completion response")
                throw NSError(
                    domain: "SwiftOpenAIClient",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "No valid response content"]
                )
            }
            
            Logger.debug("✅ SwiftOpenAI: Chat completion successful")
            return ChatCompletionResponse(content: content, model: model, id: result.id)
        } catch {
            Logger.debug("❌ SwiftOpenAI: Chat completion failed: \(error.localizedDescription)")
            throw mapSwiftOpenAIError(error)
        }
    }
    
    /// Direct implementation for Claude models that bypasses SwiftOpenAI's compatibility issues
    private func sendClaudeCompletionAsync(
        messages: [ChatMessage],
        model: String,
        temperature: Double?
    ) async throws -> ChatCompletionResponse {
        Logger.debug("🤖 Claude API: Starting direct completion for model \(model)")
        
        // Build Claude-specific request format - they use a different structure than OpenAI
        var systemPrompt: String? = nil
        var userMessages: [String] = []
        var assistantMessages: [String] = []
        
        // Extract system message (if present) and collect user/assistant messages
        for message in messages {
            switch message.role {
            case .system:
                systemPrompt = message.content
            case .user:
                userMessages.append(message.content)
            case .assistant:
                assistantMessages.append(message.content)
            }
        }
        
        // Build the Claude conversation array format - only user and assistant messages
        var claudeMessages: [[String: Any]] = []
        
        // Now interleave user and assistant messages
        let maxIndex = max(userMessages.count, assistantMessages.count)
        for i in 0..<maxIndex {
            if i < userMessages.count {
                claudeMessages.append([
                    "role": "user",
                    "content": userMessages[i]
                ])
            }
            if i < assistantMessages.count {
                claudeMessages.append([
                    "role": "assistant",
                    "content": assistantMessages[i]
                ])
            }
        }
        
        // Ensure the last message is from the user (Claude requires this)
        if let lastMessage = claudeMessages.last, lastMessage["role"] as? String != "user" {
            Logger.debug("⚠️ Claude API: Last message must be from user, adding empty user message")
            claudeMessages.append([
                "role": "user",
                "content": "Please continue."
            ])
        }
        
        // Prepare the request payload
        var requestBody: [String: Any] = [
            "model": model,
            "messages": claudeMessages,
            "temperature": temperature ?? 0.7,
            "max_tokens": 4096
        ]
        
        // Add system message as a top-level parameter (Claude API requirement)
        if let systemPrompt = systemPrompt {
            requestBody["system"] = systemPrompt
            Logger.debug("📝 Claude API: Adding system message as top-level parameter")
        }
        
        // Convert to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw NSError(domain: "SwiftOpenAIClient", code: 1001, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to encode Claude request"])
        }
        
        // Create URL request
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        
        // Set headers - crucial for Claude API
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Use both x-api-key and Authorization headers for compatibility
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Log the request for debugging
        Logger.debug("📡 Claude API request to \(url.absoluteString) with model \(model)")
        
        // Send request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check response status
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "SwiftOpenAIClient", code: 1003,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            }
            
            // Check for success
            guard httpResponse.statusCode == 200 else {
                // Try to extract error details
                var errorMessage = "Status code \(httpResponse.statusCode)"
                if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorResponse["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage += ": \(message)"
                }
                
                Logger.debug("❌ Claude API error: \(errorMessage)")
                throw NSError(domain: "ClaudeAPI", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            
            // Parse the successful response
            guard let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = responseDict["content"] as? [[String: Any]],
                  let firstContentBlock = content.first,
                  let text = firstContentBlock["text"] as? String,
                  let id = responseDict["id"] as? String else {
                throw NSError(domain: "SwiftOpenAIClient", code: 1004,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to parse Claude response"])
            }
            
            Logger.debug("✅ Claude API completion successful")
            return ChatCompletionResponse(content: text, model: model, id: id)
        } catch {
            Logger.debug("❌ Claude API completion failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Sends a chat completion request with structured output using async/await
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    ///   - structuredOutputType: The type to use for structured output
    /// - Returns: A completion with the structured output
    func sendChatCompletionWithStructuredOutput<T: StructuredOutput>(
        messages: [ChatMessage],
        model: String,
        temperature: Double?,
        structuredOutputType: T.Type
    ) async throws -> T {
        Logger.debug("🤖 SwiftOpenAI: Starting structured chat completion for model \(model)")
        
        let swiftMessages = messages.map { convertToSwiftOpenAIMessage($0) }
        let schema = generateJSONSchema(for: structuredOutputType)
        
        let responseFormat = SwiftOpenAI.ResponseFormat.jsonSchema(SwiftOpenAI.JSONSchemaResponseFormat(
            name: String(describing: T.self),
            strict: true,
            schema: schema
        ))
        
        let parameters = ChatCompletionParameters(
            messages: swiftMessages,
            model: SwiftOpenAI.Model.from(model),
            responseFormat: responseFormat,
            temperature: temperature
        )
        
        do {
            let result = try await swiftService.startChat(parameters: parameters)
            
            guard let content = result.choices?.first?.message?.content,
                  let data = content.data(using: String.Encoding.utf8) else {
                Logger.debug("❌ SwiftOpenAI: No content in structured completion response")
                throw NSError(
                    domain: "SwiftOpenAIClient",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "No valid response content for structured output"]
                )
            }
            
            Logger.debug("✅ SwiftOpenAI: Structured completion successful, parsing JSON...")
            let decoder = JSONDecoder()
            let structuredOutput = try decoder.decode(T.self, from: data)
            Logger.debug("✅ SwiftOpenAI: Structured output parsed successfully")
            return structuredOutput
        } catch let error as DecodingError {
            Logger.debug("❌ SwiftOpenAI: Failed to decode structured output: \(error)")
            throw NSError(
                domain: "SwiftOpenAIClient",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode structured output: \(error.localizedDescription)"]
            )
        } catch {
            Logger.debug("❌ SwiftOpenAI: Structured completion failed: \(error.localizedDescription)")
            throw mapSwiftOpenAIError(error)
        }
    }
    
    // MARK: - TTS Methods
    
    /// Sends a TTS (Text-to-Speech) request using SwiftOpenAI
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - instructions: Voice instructions for TTS generation (optional)
    ///   - onComplete: Callback with audio data
    func sendTTSRequest(
        text: String,
        voice: String,
        instructions: String?,
        onComplete: @escaping (Result<Data, Error>) -> Void
    ) {
        Logger.debug("🎵 SwiftOpenAI: Starting TTS request with voice \(voice)")
        
        Task {
            do {
                let parameters = AudioSpeechParameters(
                    model: .tts1,
                    input: text,
                    voice: mapVoiceToSwiftOpenAI(voice)
                )
                
                let result = try await swiftService.createSpeech(parameters: parameters)
                Logger.debug("✅ SwiftOpenAI: TTS request successful")
                onComplete(.success(result.output))
            } catch {
                Logger.debug("❌ SwiftOpenAI: TTS request failed: \(error.localizedDescription)")
                onComplete(.failure(mapSwiftOpenAIError(error)))
            }
        }
    }
    
    /// Sends a streaming TTS (Text-to-Speech) request using SwiftOpenAI
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - instructions: Voice instructions for TTS generation (optional)
    ///   - onChunk: Callback for each chunk of audio data
    ///   - onComplete: Callback when streaming is complete
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        instructions: String?,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        Logger.debug("🎵 SwiftOpenAI: Starting TTS streaming request with voice \(voice) (native streaming)")
        
        Task {
            do {
                let parameters = AudioSpeechParameters(
                    model: .tts1,
                    input: text,
                    voice: mapVoiceToSwiftOpenAI(voice),
                    responseFormat: nil,
                    speed: nil,
                    stream: true
                )
                
                let stream = try await swiftService.createStreamingSpeech(parameters: parameters)
                
                var hasCompletedNormally = false
                
                for try await chunk in stream {
                    if chunk.isLastChunk {
                        hasCompletedNormally = true
                        onComplete(nil)
                        break
                    } else {
                        onChunk(.success(chunk.chunk))
                    }
                }
                
                // If we exit the stream without seeing the last chunk, still complete normally
                if !hasCompletedNormally {
                    Logger.debug("🎵 SwiftOpenAI: TTS stream completed without explicit last chunk")
                    onComplete(nil)
                }
                
            } catch {
                Logger.debug("❌ SwiftOpenAI: TTS streaming failed: \(error.localizedDescription)")
                let mappedError = mapSwiftOpenAIError(error)
                onComplete(mappedError)
            }
        }
    }
    
    // MARK: - Schema Generation Helpers
    
    /// Generates a JSONSchema for a given StructuredOutput type
    /// - Parameter type: The structured output type
    /// - Returns: The JSONSchema
    private func generateJSONSchema<T: StructuredOutput>(for type: T.Type) -> SwiftOpenAI.JSONSchema {
        Logger.debug("🔧 SwiftOpenAI: Generating JSON schema for \(String(describing: T.self))")
        
        if T.self == BestCoverLetterResponse.self {
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
                required: ["strengthAndVoiceAnalysis", "bestLetterUuid", "verdict"],
                additionalProperties: false
            )
        }
        
        if T.self == RevisionsContainer.self {
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
                            required: ["id", "oldValue", "newValue", "valueChanged", "why", "isTitleNode", "treePath"],
                            additionalProperties: false
                        )
                    )
                ],
                required: ["revArray"],
                additionalProperties: false
            )
        }
        
        // Fallback for unknown types
        Logger.debug("⚠️ SwiftOpenAI: Using fallback schema for unknown type \(String(describing: T.self))")
        return SwiftOpenAI.JSONSchema(type: .object, additionalProperties: false)
    }
    
    /// Helper to convert a JSONSchemaType to its string representation
    /// - Parameter type: The JSONSchemaType
    /// - Returns: String representation of the type
    private func typeToString(_ type: SwiftOpenAI.JSONSchemaType) -> String {
        switch type {
        case .string: return "string"
        case .object: return "object"
        case .array: return "array"
        case .boolean: return "boolean"
        case .integer: return "integer"
        case .number: return "number"
        case .null: return "null"
        case .union: return "object" // Fallback for nested unions
        }
    }
    
    /// Converts a schema string to JSONSchema
    /// - Parameter schemaString: The schema as a JSON string
    /// - Returns: The converted JSONSchema
    /// - Throws: An error if conversion fails
    private func convertSchemaStringToJSONSchema(_ schemaString: String) throws -> SwiftOpenAI.JSONSchema {
        guard let data = schemaString.data(using: .utf8) else {
            throw NSError(domain: "SwiftOpenAIClient", code: 1006,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to convert schema string to data"])
        }
        
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "SwiftOpenAIClient", code: 1007,
                         userInfo: [NSLocalizedDescriptionKey: "Schema string is not a valid JSON object"])
        }
        
        return try createJSONSchemaFromDict(dict)
    }
    
    /// Converts SwiftOpenAI's JSONSchema to a dictionary
    /// - Parameter schema: The SwiftOpenAI JSONSchema
    /// - Returns: A dictionary representation of the schema
    private func createDictionaryFromJSONSchema(_ schema: SwiftOpenAI.JSONSchema) -> [String: Any] {
        var result: [String: Any] = [:]
        
        if let type = schema.type {
            switch type {
            case .string: result["type"] = "string"
            case .object: result["type"] = "object"
            case .array: result["type"] = "array"
            case .boolean: result["type"] = "boolean"
            case .integer: result["type"] = "integer"
            case .number: result["type"] = "number"
            case .null: result["type"] = "null"
            case .union(let types):
                // For union types, create a type array
                result["type"] = types.map { typeToString($0) }
            }
        }
        
        if let description = schema.description {
            result["description"] = description
        }
        
        if let properties = schema.properties {
            var propsDict: [String: [String: Any]] = [:]
            for (key, value) in properties {
                propsDict[key] = createDictionaryFromJSONSchema(value)
            }
            result["properties"] = propsDict
        }
        
        if let items = schema.items {
            result["items"] = createDictionaryFromJSONSchema(items)
        }
        
        if let required = schema.required {
            result["required"] = required
        }
        
        result["additionalProperties"] = schema.additionalProperties
        
        if let enumValues = schema.enum {
            result["enum"] = enumValues
        }
        
        return result
    }
    
    /// Creates a JSONSchema from a dictionary
    /// - Parameter dict: The dictionary representation of the schema
    /// - Returns: The JSONSchema object
    /// - Throws: An error if creation fails
    private func createJSONSchemaFromDict(_ dict: [String: Any]) throws -> SwiftOpenAI.JSONSchema {
        let schemaType: SwiftOpenAI.JSONSchemaType? = {
            guard let typeString = dict["type"] as? String else { return nil }
            switch typeString {
            case "string": return .string
            case "object": return .object
            case "array": return .array
            case "boolean": return .boolean
            case "integer": return .integer
            case "number": return .number
            default: return nil
            }
        }()
        
        var properties: [String: SwiftOpenAI.JSONSchema]? = nil
        if let propsDict = dict["properties"] as? [String: [String: Any]] {
            properties = try propsDict.mapValues { try createJSONSchemaFromDict($0) }
        }
        
        var items: SwiftOpenAI.JSONSchema? = nil
        if let itemsDict = dict["items"] as? [String: Any] {
            items = try createJSONSchemaFromDict(itemsDict)
        }
        
        return SwiftOpenAI.JSONSchema(
            type: schemaType,
            description: dict["description"] as? String,
            properties: properties,
            items: items,
            required: dict["required"] as? [String],
            additionalProperties: dict["additionalProperties"] as? Bool ?? false,
            enum: dict["enum"] as? [String]
        )
    }
}
