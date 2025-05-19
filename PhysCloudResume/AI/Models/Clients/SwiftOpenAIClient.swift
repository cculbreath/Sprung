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
        
        // Create SwiftOpenAI service
        if configuration.host != "api.openai.com" {
            // Custom URL configuration (e.g., for Gemini)
            swiftService = OpenAIServiceFactory.service(
                apiKey: configuration.token ?? "",
                overrideBaseURL: "https://\(configuration.host)",
                configuration: urlConfig,
                proxyPath: nil,
                overrideVersion: "v1",
                extraHeaders: configuration.customHeaders
            )
        } else {
            // Standard OpenAI configuration
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
    
    // MARK: - Helper Methods
    

    
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
        
        return ChatCompletionParameters.Message(
            role: role,
            content: .text(message.content)
        )
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
        default: return .alloy
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
    ///   - temperature: Controls randomness (0-1)
    /// - Returns: A completion with the model's response
    func sendChatCompletionAsync(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) async throws -> ChatCompletionResponse {
        Logger.debug("🤖 SwiftOpenAI: Starting chat completion for model \(model)")
        
        let swiftMessages = messages.map { convertToSwiftOpenAIMessage($0) }
        let parameters = ChatCompletionParameters(
            messages: swiftMessages,
            model: SwiftOpenAI.Model.from(model),
            temperature: temperature
        )
        
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
        temperature: Double,
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
    
    // MARK: - Responses API Methods
    
    /// Sends a request to the OpenAI Responses API using async/await
    /// - Parameters:
    ///   - message: The current message content
    ///   - model: The model to use
    ///   - temperature: Controls randomness (0-1)
    ///   - previousResponseId: Optional ID from a previous response for conversation state
    ///   - schema: Optional JSON schema for structured output
    /// - Returns: The response from the Responses API
    func sendResponseRequestAsync(
        message: String,
        model: String,
        temperature: Double?,
        previousResponseId: String?,
        schema: String? = nil
    ) async throws -> ResponsesAPIResponse {
        Logger.debug("🤖 SwiftOpenAI: Starting Responses API request for model \(model)")
        
        // Configure text response format if schema is provided
        var textConfig: TextConfiguration? = nil
        if let schemaString = schema {
            Logger.debug("🤖 SwiftOpenAI: Converting schema for structured output")
            do {
                let jsonSchema = try convertSchemaStringToJSONSchema(schemaString)
                textConfig = TextConfiguration(format: .jsonSchema(jsonSchema))
            } catch {
                Logger.debug("❌ SwiftOpenAI: Failed to convert schema: \(error)")
                throw NSError(
                    domain: "SwiftOpenAIClient",
                    code: 1005,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to convert schema: \(error.localizedDescription)"]
                )
            }
        }
        
        let parameters = ModelResponseParameter(
            input: .string(message),
            model: SwiftOpenAI.Model.from(model),
            previousResponseId: previousResponseId,
            temperature: temperature,
            text: textConfig
        )
        
        do {
            let result = try await swiftService.responseCreate(parameters)
            
            // Use the convenience property to get aggregated text output
            let content = result.outputText ?? ""
            
            Logger.debug("✅ SwiftOpenAI: Responses API request successful")
            return ResponsesAPIResponse(
                id: result.id,
                content: content,
                model: result.model
            )
        } catch {
            Logger.debug("❌ SwiftOpenAI: Responses API request failed: \(error.localizedDescription)")
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
