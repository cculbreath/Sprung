//
//  MacPawOpenAIClient.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/22/25.
//

import Foundation
import OpenAI

/// Custom URLSession delegate to log network activity
class NetworkLoggingDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let request = task.currentRequest,
              let response = task.response as? HTTPURLResponse else {
            return
        }
        
        let url = request.url?.absoluteString ?? "unknown"
        let statusCode = response.statusCode
        let headers = response.allHeaderFields
        
        print("🌐 Request completed for URL: \(url)")
        print("📊 HTTP Status: \(statusCode)")
        print("⏱️ Request timing:")
        
        metrics.transactionMetrics.forEach { metric in
            if let fetchStartDate = metric.fetchStartDate,
               let responseEndDate = metric.responseEndDate {
                let duration = responseEndDate.timeIntervalSince(fetchStartDate)
                print("   - Duration: \(duration) seconds")
            }
        }
        
        print("📝 Response Headers:")
        for (key, value) in headers {
            print("   \(key): \(value)")
        }
        
        if statusCode >= 400 {
            print("❌ Error response with status code: \(statusCode)")
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let response = dataTask.response as? HTTPURLResponse {
            let statusCode = response.statusCode
            if statusCode >= 400 {
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                print("❌ Error response body: \(responseString)")
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

    /// Initializes a new client with the given API key
    /// - Parameter apiKey: The API key to use for requests
    init(apiKey: String) {
        apiKeyValue = apiKey

        // Create custom URLSession that logs network activity
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 300.0 // 5 minutes
        
        let loggingSession = URLSession(configuration: sessionConfig, delegate: NetworkLoggingDelegate(), delegateQueue: nil)
        
        let configuration = OpenAI.Configuration(
            token: apiKey,
            organizationIdentifier: nil,
            timeoutInterval: 300.0, // Increased timeout to 5 minutes
            sessionConfiguration: sessionConfig
        )
        client = OpenAI(configuration: configuration)
    }

    /// Exposes the internal OpenAI client instance for direct access
    var openAIClient: OpenAI {
        return client
    }

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

    /// Sends a chat completion request
    /// - Parameters:
    ///   - messages: The conversation history
    ///   - model: The model to use for completion
    ///   - temperature: Controls randomness (0-1)
    ///   - onComplete: Callback with completion response
    func sendChatCompletion(
        messages: [ChatMessage],
        model: String,
        temperature: Double,
        onComplete: @escaping (Result<ChatCompletionResponse, Error>) -> Void
    ) {
        // Convert our messages to MacPaw's format
        let chatMessages = messages.compactMap { convertMessage($0) }

        // Create the query with the converted messages
        let query = ChatQuery(
            messages: chatMessages,
            model: model,
            temperature: temperature
        )

        // Send the chat completion request
        client.chats(query: query) { result in
            switch result {
            case let .success(chatResult):
                if let choice = chatResult.choices.first, let content = choice.message.content {
                    let response = ChatCompletionResponse(
                        content: content,
                        model: model
                    )
                    onComplete(.success(response))
                } else {
                    onComplete(.failure(NSError(
                        domain: "MacPawOpenAIClient",
                        code: 1001,
                        userInfo: [NSLocalizedDescriptionKey: "No valid response content"]
                    )))
                }
            case let .failure(error):
                onComplete(.failure(error))
            }
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
        var query = ChatQuery(
            messages: chatMessages,
            model: model,
            temperature: temperature
        )
        query.stream = true

        // Start the streaming request
        client.chatsStream(query: query) { chunkResult in
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
        default: mappedVoice = .alloy
        }

        // Create the query
        var query = AudioSpeechQuery(
            model: .gpt_4o_mini_tts,
            input: text,
            voice: mappedVoice,
            instructions: instructions ?? "",
            responseFormat: .mp3
        )

        // Send the TTS request
        client.audioCreateSpeech(query: query) { result in
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
        default: mappedVoice = .alloy
        }

        // Create the query
        var query = AudioSpeechQuery(
            model: .gpt_4o_mini_tts,
            input: text,
            voice: mappedVoice,
            instructions: instructions ?? "",
            responseFormat: .mp3
        )

        // Send the streaming TTS request
        client.audioCreateSpeechStream(query: query) { partialResult in
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
}
