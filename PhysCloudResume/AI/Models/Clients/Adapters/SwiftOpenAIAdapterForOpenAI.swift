//
//  SwiftOpenAIAdapterForOpenAI.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftOpenAI

/// OpenAI-specific adapter for SwiftOpenAI
class SwiftOpenAIAdapterForOpenAI: BaseSwiftOpenAIAdapter, TTSCapable {
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
        // Determine if this is a request for structured output
        let isStructuredOutput = query.desiredResponseType != nil
        
        // Detect if this is actually a Grok model being handled by OpenAI adapter
        let providerName = config.providerType == AIModels.Provider.grok ? "Grok" : "OpenAI"
        
        // Log the model and whether this is a structured output request
        Logger.debug("Executing \(isStructuredOutput ? "structured" : "text") query with \(providerName) model: \(query.modelIdentifier)")
        
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
                        Logger.error("Invalid JSON returned from \(providerName): \(error.localizedDescription)")
                        throw AppLLMError.clientError("\(providerName) returned invalid JSON: \(error.localizedDescription)")
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
    
    // MARK: - TTSCapable Implementation
    
    func sendTTSRequest(
        text: String,
        voice: String,
        instructions: String?,
        onComplete: @escaping (Result<Data, Error>) -> Void
    ) {
        _ = instructions // Unused but required by protocol
        Task {
            do {
                let parameters = AudioSpeechParameters(
                    model: .tts1,
                    input: text,
                    voice: AudioSpeechParameters.Voice(rawValue: voice) ?? .alloy,
                    responseFormat: .mp3,
                    speed: 1.0,
                    stream: false
                )
                Logger.debug("🎤 [TTS] Sending non-streaming request with voice: \(voice), text length: \(text.count)")
                let response = try await swiftService.createSpeech(parameters: parameters)
                Logger.debug("🎤 [TTS] Received response with audio data size: \(response.output.count)")
                onComplete(.success(response.output))
            } catch {
                Logger.error("🚨 [TTS] Non-streaming speech error: \(error)")
                
                // Log more details about the error
                if let apiError = error as? SwiftOpenAI.APIError {
                    Logger.error("🚨 [TTS] SwiftOpenAI API Error: \(apiError)")
                } else if let urlError = error as? URLError {
                    Logger.error("🚨 [TTS] URL Error - Code: \(urlError.code), Description: \(urlError.localizedDescription)")
                } else {
                    Logger.error("🚨 [TTS] Unknown error type: \(type(of: error)), Description: \(error.localizedDescription)")
                }
                
                onComplete(.failure(error))
            }
        }
    }
    
    func sendTTSStreamingRequest(
        text: String,
        voice: String,
        instructions: String?,
        onChunk: @escaping (Result<Data, Error>) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        _ = instructions // Unused but required by protocol
        Task {
            do {
                let parameters = AudioSpeechParameters(
                    model: .tts1,
                    input: text,
                    voice: AudioSpeechParameters.Voice(rawValue: voice) ?? .alloy,
                    responseFormat: .mp3,
                    speed: 1.0,
                    stream: true
                )
                Logger.debug("🎤 [TTS] Sending streaming request with voice: \(voice), text length: \(text.count)")
                let stream = try await swiftService.createStreamingSpeech(parameters: parameters)
                for try await chunk in stream {
                    if chunk.isLastChunk {
                        Logger.debug("🎤 [TTS] Received last chunk")
                        onComplete(nil)
                        return
                    } else {
                        Logger.debug("🎤 [TTS] Received chunk of size: \(chunk.chunk.count)")
                        onChunk(.success(chunk.chunk))
                    }
                }
                onComplete(nil)
            } catch {
                Logger.error("🚨 [TTS] Streaming speech error: \(error)")
                
                // Log more details about the error
                if let apiError = error as? SwiftOpenAI.APIError {
                    Logger.error("🚨 [TTS] SwiftOpenAI API Error: \(apiError)")
                } else if let urlError = error as? URLError {
                    Logger.error("🚨 [TTS] URL Error - Code: \(urlError.code), Description: \(urlError.localizedDescription)")
                } else {
                    Logger.error("🚨 [TTS] Unknown error type: \(type(of: error)), Description: \(error.localizedDescription)")
                }
                
                onComplete(error)
            }
        }
    }
}
