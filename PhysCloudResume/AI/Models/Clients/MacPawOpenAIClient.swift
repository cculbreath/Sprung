//
//  MacPawOpenAIClient.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/22/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI
import OpenAI

/// Custom URLSession delegate to log network activity
class NetworkLoggingDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    func urlSession(_: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let request = task.currentRequest,
              let response = task.response as? HTTPURLResponse
        else {
            return
        }

        let url = request.url?.absoluteString ?? "unknown"
        let statusCode = response.statusCode
        let headers = response.allHeaderFields

        Logger.debug("🌐 Request completed for URL: \(url)")
        Logger.debug("📊 HTTP Status: \(statusCode)")
        Logger.debug("⏱️ Request timing:")

        for metric in metrics.transactionMetrics {
            if let fetchStartDate = metric.fetchStartDate,
               let responseEndDate = metric.responseEndDate
            {
                let duration = responseEndDate.timeIntervalSince(fetchStartDate)
                Logger.debug("   - Duration: \(duration) seconds")
            }
        }

        Logger.debug("📝 Response Headers:")
        for (key, value) in headers {
            Logger.debug("   \(key): \(value)")
        }

        if statusCode >= 400 {
            Logger.debug("❌ Error response with status code: \(statusCode)")
        }
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let response = dataTask.response as? HTTPURLResponse {
            let statusCode = response.statusCode
            if statusCode >= 400 {
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                Logger.debug("❌ Error response body: \(responseString)")
            }
        }
    }
}

/// Implementation of OpenAIClientProtocol using MacPaw/OpenAI library
class MacPawOpenAIClient: OpenAIClientProtocol {
    private let client: OpenAI
    private let apiKeyValue: String

    /// The API key used for requests
    var apiKey: String {
        apiKeyValue
    }

    /// Initializes a new client with the given configuration
    /// - Parameter configuration: The configuration to use for requests
    init(configuration: OpenAI.Configuration) {
        apiKeyValue = configuration.token ?? "none" // Unwrap optional token value
        client = OpenAI(configuration: configuration)
    }

    /// Initializes a new client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    init(apiKey: String) {
        apiKeyValue = apiKey

        // Create custom URLSession that logs network activity
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 900.0 // 15 minutes (increased from 5 minutes for reasoning models)
        
        // Create a logging session (unused directly, but kept for reference)
        _ = URLSession(configuration: sessionConfig, delegate: NetworkLoggingDelegate(), delegateQueue: nil)

        let configuration = OpenAI.Configuration(
            token: apiKey,
            organizationIdentifier: nil,
            timeoutInterval: 900.0 // 15 minutes (increased from 5 minutes for reasoning models)
        )
        client = OpenAI(configuration: configuration)
    }
    
    /// Exposes the internal OpenAI client instance for direct access
    var openAIClient: OpenAI {
        return client
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
        // Convert our messages to MacPaw's format
        let chatMessages = messages.compactMap { convertMessage($0) }

        // Generate schema for the structured output
        let schemaWrapper = generateSchema(for: structuredOutputType)
        let dynamicSchema = ChatQuery.DynamicJSONSchema(
            name: "structured-output",
            schema: schemaWrapper,
            strict: true
        )

        // Create the query with structured output format
        let query = ChatQuery(
            messages: chatMessages,
            model: model,
            responseFormat: .dynamicJsonSchema(dynamicSchema),
            temperature: temperature
        )

        do {
            // Make the API call with structured output
            let result = try await client.chats(query: query)

            // Extract structured output response
            guard let content = result.choices.first?.message.content,
                  let data = content.data(using: .utf8)
            else {
                throw NSError(
                    domain: "MacPawOpenAIClient",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to get structured output content"]
                )
            }

            // Decode the JSON content into the specified structured output type
            do {
                let structuredOutput = try JSONDecoder().decode(T.self, from: data)
                return structuredOutput
            } catch {
                throw NSError(
                    domain: "MacPawOpenAIClient",
                    code: 1003,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to decode structured output: \(error.localizedDescription)"]
                )
            }
        } catch {
            // Rethrow any errors from the API call
            throw error
        }
    }



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
        // Convert our messages to MacPaw's format
        let chatMessages = messages.compactMap { convertMessage($0) }

        // Create the query with the converted messages
        // We can directly use the model string since the ChatQuery init accepts any string value
        let query = ChatQuery(
            messages: chatMessages,
            model: model,
            temperature: temperature
        )

        do {
            // Send the chat completion request
            let result = try await client.chats(query: query)

            // Extract the response content from the first choice
            guard let choice = result.choices.first, let content = choice.message.content else {
                throw NSError(
                    domain: "MacPawOpenAIClient",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "No valid response content"]
                )
            }

            // Create and return the chat completion response
            return ChatCompletionResponse(
                content: content,
                model: model
            )
        } catch {
            // Rethrow any errors from the API call
            throw error
        }
    }

    /// Sends a chat completion request with streaming
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    ///   - onChunk: Callback for each chunk of the streaming response
    ///   - onComplete: Callback when streaming is complete
    func sendChatCompletionStreaming(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        onChunk: @escaping (Result<ChatCompletionResponse, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        // Convert our messages to MacPaw's format
        let chatMessages = messages.compactMap { convertMessage($0) }

        // Create streamable query with the converted messages
        // We can directly use the model string since the ChatQuery init accepts any string value
        var query = ChatQuery(
            messages: chatMessages,
            model: model,
            temperature: temperature
        )
        query.stream = true

        // Start the streaming request
        _ = client.chatsStream(query: query) { chunkResult in
            switch chunkResult {
            case let .success(streamResult):
                // Map the stream chunk to our response format
                if let choice = streamResult.choices.first, let content = choice.delta.content {
                    let response = ChatCompletionResponse(
                        content: content,
                        model: model
                    )
                    onChunk(.success(response))
                }
            case let .failure(error):
                onChunk(.failure(error))
            }
        } completion: { error in
            onComplete(error)
        }
    }

    /// Sends a TTS (Text-to-Speech) request
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
        // Map voice string to MacPaw's voice type
        let mappedVoice: AudioSpeechQuery.AudioSpeechVoice
        switch voice.lowercased() {
        case "alloy": mappedVoice = .alloy
        case "echo": mappedVoice = .echo
        case "fable": mappedVoice = .fable
        case "onyx": mappedVoice = .onyx
        case "nova": mappedVoice = .nova
        case "shimmer": mappedVoice = .shimmer
        // New voices - safe access through string initialization if available
        case "ash", "ballad", "coral", "sage", "verse":
            // Try to create the voice enum value directly from the string
            if let newVoice = AudioSpeechQuery.AudioSpeechVoice(rawValue: voice.lowercased()) {
                mappedVoice = newVoice
            } else {
                // Fallbacks based on similarity if not directly supported
                switch voice.lowercased() {
                case "ash": mappedVoice = .alloy // Neutral fallback
                case "ballad", "verse": mappedVoice = .fable // British fallbacks
                case "coral": mappedVoice = .nova // Female fallback
                case "sage": mappedVoice = .alloy // Neutral fallback
                default: mappedVoice = .alloy
                }
            }
        default: mappedVoice = .alloy
        }

        // Create the query
        let query = AudioSpeechQuery(
            model: AIModels.gpt_4o_mini_tts,
            input: text,
            voice: mappedVoice,
            instructions: instructions ?? "",
            responseFormat: .mp3
        )

        // Send the TTS request
        _ = client.audioCreateSpeech(query: query) { result in
            switch result {
            case let .success(audioResult):
                onComplete(.success(audioResult.audio))
            case let .failure(error):
                onComplete(.failure(error))
            }
        }
    }

    /// Sends a streaming TTS (Text-to-Speech) request
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
        // Map voice string to MacPaw's voice type
        let mappedVoice: AudioSpeechQuery.AudioSpeechVoice
        switch voice.lowercased() {
        case "alloy": mappedVoice = .alloy
        case "echo": mappedVoice = .echo
        case "fable": mappedVoice = .fable
        case "onyx": mappedVoice = .onyx
        case "nova": mappedVoice = .nova
        case "shimmer": mappedVoice = .shimmer
        // New voices - safe access through string initialization if available
        case "ash", "ballad", "coral", "sage", "verse":
            // Try to create the voice enum value directly from the string
            if let newVoice = AudioSpeechQuery.AudioSpeechVoice(rawValue: voice.lowercased()) {
                mappedVoice = newVoice
            } else {
                // Fallbacks based on similarity if not directly supported
                switch voice.lowercased() {
                case "ash": mappedVoice = .alloy // Neutral fallback
                case "ballad", "verse": mappedVoice = .fable // British fallbacks
                case "coral": mappedVoice = .nova // Female fallback
                case "sage": mappedVoice = .alloy // Neutral fallback
                default: mappedVoice = .alloy
                }
            }
        default: mappedVoice = .alloy
        }

        // Create the query
        let query = AudioSpeechQuery(
            model: AIModels.gpt_4o_mini_tts,
            input: text,
            voice: mappedVoice,
            instructions: instructions ?? "",
            responseFormat: .mp3
        )

        // Send the streaming TTS request
        _ = client.audioCreateSpeechStream(query: query) { partialResult in
            switch partialResult {
            case let .success(chunk):
                onChunk(.success(chunk.audio))
            case let .failure(error):
                onChunk(.failure(error))
            }
        } completion: { error in
            onComplete(error)
        }
    }

    // MARK: - Responses API Methods

    /// Sends a request to the OpenAI Responses API using async/await
    /// - Parameters:
    ///   - message: The current message content
    ///   - model: The model to use
    ///   - temperature: Controls randomness (0-1)
    ///   - previousResponseId: Optional ID from a previous response for conversation state
    /// - Returns: The response from the Responses API
    func sendResponseRequestAsync(
        message: String,
        model: String,
        temperature: Double?,
        previousResponseId: String?,
        schema: String? = nil
    ) async throws -> ResponsesAPIResponse {
        // Build the request dictionary following the official Responses API structure.
        var requestDict: [String: Any] = [
            "model": model,
            "input": message,
        ]
        
        // Only add temperature if it's provided (some models don't support it)
        if let temp = temperature {
            requestDict["temperature"] = temp
        }

        if let previous = previousResponseId {
            requestDict["previous_response_id"] = previous
        }

        // Add structured output schema if provided.
        if let schemaString = schema,
           let schemaData = schemaString.data(using: .utf8),
           let schemaJson = try? JSONSerialization.jsonObject(with: schemaData) as? [String: Any]
        {
            requestDict["text"] = [
                "format": [
                    "type": "json_schema",
                    "name": "resume_revisions",
                    "schema": schemaJson,
                    "strict": true,
                ],
            ]
        }

        // Serialize request body.
        let httpBody = try JSONSerialization.data(withJSONObject: requestDict, options: [])

        // Create URL request
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw NSError(
                domain: "MacPawOpenAIClient",
                code: 1000,
                userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        // Log payload for debugging.
        if let bodyString = String(data: httpBody, encoding: .utf8) {
            Logger.debug("🌐 Sending request to OpenAI Responses API with payload:\n\(bodyString)")
        }

        // Perform request.
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check for HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "MacPawOpenAIClient",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
            )
        }

        // Log the response for debugging
        Logger.debug("📊 HTTP Status: \(httpResponse.statusCode)")

        // Check for error status codes
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            // Try to parse the error response
            do {
                let errorResponse = try JSONDecoder().decode(ResponsesAPIErrorResponse.self, from: data)
                throw NSError(
                    domain: "OpenAIAPI",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message]
                )
            } catch {
                throw NSError(
                    domain: "MacPawOpenAIClient",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP Error: \(httpResponse.statusCode)"]
                )
            }
        }

        // Log the response data for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            Logger.debug("📝 Response data: \(responseString)")
        }

        // Decode the response
        let responseWrapper = try JSONDecoder().decode(ResponsesAPIResponseWrapper.self, from: data)

        // Convert to our ResponsesAPIResponse format
        return responseWrapper.toResponsesAPIResponse()
    }

    // MARK: - Helper Methods

    /// Converts our ChatMessage to MacPaw's ChatQuery.ChatCompletionMessageParam
    /// - Parameter message: The message to convert
    /// - Returns: The converted message
    func convertMessage(_ message: ChatMessage) -> ChatQuery.ChatCompletionMessageParam? {
        let role: ChatQuery.ChatCompletionMessageParam.Role

        switch message.role {
        case .system:
            role = .system
        case .user:
            role = .user
        case .assistant:
            role = .assistant
        }

        return ChatQuery.ChatCompletionMessageParam(
            role: role,
            content: message.content
        )
    }

    /// Generates a structured output schema for a given type
    /// - Parameter type: The structured output type
    /// - Returns: The schema as a wrapper
    func generateSchema<T: StructuredOutput>(for type: T.Type) -> StructuredSchemaDict {
        // Handle BestCoverLetterResponse
        if T.self == BestCoverLetterResponse.self {
            return StructuredSchemaDict(dict: [
                "type": "object",
                "properties": [
                    "strengthAndVoiceAnalysis": [
                        "type": "string",
                        "description": "Brief summary ranking/assessment of each letter's strength and voice"
                    ],
                    "bestLetterUuid": [
                        "type": "string",
                        "description": "UUID of the selected best cover letter"
                    ],
                    "verdict": [
                        "type": "string", 
                        "description": "Reason for the ultimate choice"
                    ]
                ],
                "required": ["strengthAndVoiceAnalysis", "bestLetterUuid", "verdict"],
                "additionalProperties": false
            ])
        }
        
        // Handle RevisionsContainer 
        if T.self == RevisionsContainer.self {
            return StructuredSchemaDict(dict: [
                "type": "object",
                "properties": [
                    "revArray": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "id": ["type": "string"],
                                "oldValue": ["type": "string"],
                                "newValue": ["type": "string"],
                                "valueChanged": ["type": "boolean"],
                                "why": ["type": "string"],
                                "isTitleNode": ["type": "boolean"],
                                "treePath": ["type": "string"]
                            ],
                            "required": ["id", "oldValue", "newValue", "valueChanged", "why", "isTitleNode", "treePath"],
                            "additionalProperties": false
                        ]
                    ]
                ],
                "required": ["revArray"],
                "additionalProperties": false
            ])
        }
        
        // Fallback: basic object schema
        return StructuredSchemaDict(dict: [
            "type": "object",
            "additionalProperties": true
        ])
    }

    /// Wrapper for schema dictionary to make it Sendable
    struct StructuredSchemaDict: Codable, Sendable {
        let dict: [String: Any]
        
        enum CodingKeys: String, CodingKey {
            case dict
        }
        
        init(dict: [String: Any]) {
            self.dict = dict
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(AnyCodable(dict))
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(AnyCodable.self)
            self.dict = value.value as? [String: Any] ?? [:]
        }
    }
    
    /// Helper to encode Any values
    private struct AnyCodable: Codable {
        let value: Any
        
        init(_ value: Any) {
            self.value = value
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            
            if let dict = value as? [String: Any] {
                try container.encode(dict.mapValues(AnyCodable.init))
            } else if let array = value as? [Any] {
                try container.encode(array.map(AnyCodable.init))
            } else if let string = value as? String {
                try container.encode(string)
            } else if let bool = value as? Bool {
                try container.encode(bool)
            } else if let int = value as? Int {
                try container.encode(int)
            } else if let double = value as? Double {
                try container.encode(double)
            } else {
                try container.encodeNil()
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            
            if let dict = try? container.decode([String: AnyCodable].self) {
                value = dict.mapValues { $0.value }
            } else if let array = try? container.decode([AnyCodable].self) {
                value = array.map { $0.value }
            } else if let string = try? container.decode(String.self) {
                value = string
            } else if let bool = try? container.decode(Bool.self) {
                value = bool
            } else if let int = try? container.decode(Int.self) {
                value = int
            } else if let double = try? container.decode(Double.self) {
                value = double
            } else {
                value = NSNull()
            }
        }
    }


}
