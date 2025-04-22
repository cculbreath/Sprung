import Foundation
import OpenAI

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

        let configuration = OpenAI.Configuration(
            token: apiKey,
            organizationIdentifier: nil,
            timeoutInterval: 60.0
        )
        self.client = OpenAI(configuration: configuration)
    }

    /// Converts our ChatMessage to MacPaw's ChatQuery.ChatCompletionMessageParam
    /// - Parameter message: The message to convert
    /// - Returns: The converted message
    private func convertMessage(_ message: ChatMessage) -> ChatQuery.ChatCompletionMessageParam? {
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
        temperature: Double = 0.7,
        onComplete: @escaping (Result<ChatCompletionResponse, Error>) -> Void
    ) {
        // Convert our messages to MacPaw's format
        let chatMessages = messages.compactMap { convertMessage($0) }
        
        // Create the query with the converted messages
        let query = ChatQuery(
            model: model,
            messages: chatMessages,
            temperature: temperature
        )
        
        // Send the chat completion request
        client.chats(query: query) { result in
            switch result {
            case .success(let chatResult):
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
            case .failure(let error):
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
        temperature: Double = 0.7
    ) async throws -> ChatCompletionResponse {
        // Convert our messages to MacPaw's format
        let chatMessages = messages.compactMap { convertMessage($0) }
        
        // Create the query with the converted messages
        let query = ChatQuery(
            model: model,
            messages: chatMessages,
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
        temperature: Double = 0.7,
        onChunk: @escaping (Result<ChatCompletionResponse, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        // Convert our messages to MacPaw's format
        let chatMessages = messages.compactMap { convertMessage($0) }
        
        // Create streamable query with the converted messages
        var query = ChatQuery(
            model: model,
            messages: chatMessages,
            temperature: temperature
        )
        query.stream = true
        
        // Start the streaming request
        client.chatsStream(query: query) { chunkResult in
            switch chunkResult {
            case .success(let streamResult):
                // Map the stream chunk to our response format
                if let choice = streamResult.choices.first, let content = choice.delta.content {
                    let response = ChatCompletionResponse(
                        content: content,
                        model: model
                    )
                    onChunk(.success(response))
                }
            case .failure(let error):
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
    ///   - onComplete: Callback with audio data
    func sendTTSRequest(
        text: String,
        voice: String,
        onComplete: @escaping (Result<Data, Error>) -> Void
    ) {
        // Map voice string to MacPaw's voice type
        let mappedVoice: AudioSpeechQuery.Voice
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
        let query = AudioSpeechQuery(
            model: .tts_1,
            input: text,
            voice: mappedVoice,
            responseFormat: .mp3
        )
        
        // Send the TTS request
        client.audioCreateSpeech(query: query) { result in
            switch result {
            case .success(let audioResult):
                onComplete(.success(audioResult.audio))
            case .failure(let error):
                onComplete(.failure(error))
            }
        }
    }
    
    /// Sends a streaming TTS (Text-to-Speech) request
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - onChunk: Callback for each chunk of audio data
    ///   - onComplete: Callback when streaming is complete
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        // Map voice string to MacPaw's voice type
        let mappedVoice: AudioSpeechQuery.Voice
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
        let query = AudioSpeechQuery(
            model: .tts_1,
            input: text,
            voice: mappedVoice,
            responseFormat: .mp3
        )
        
        // Send the streaming TTS request
        client.audioCreateSpeechStream(query: query) { partialResult in
            switch partialResult {
            case .success(let chunk):
                onChunk(.success(chunk.audio))
            case .failure(let error):
                onChunk(.failure(error))
            }
        } completion: { error in
            onComplete(error)
        }
    }
}
