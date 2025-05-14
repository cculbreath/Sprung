//
//  SystemFingerprintFixClient.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/13/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI
import OpenAI

/// A subclass of the MacPaw OpenAI client that handles null system_fingerprint fields
class SystemFingerprintFixClient: MacPawOpenAIClient {
    
    /// A custom implementation of the chats method that handles null system_fingerprint
    /// This override intercepts the chat completion request to handle system_fingerprint errors
    override func sendChatCompletionAsync(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) async throws -> ChatCompletionResponse {
        Logger.debug("SystemFingerprintFixClient: Using direct API call for all requests")
        
        // Skip the standard client and go directly to our custom implementation
        // to avoid any system_fingerprint issues
        return try await sendDirectChatRequest(
            messages: messages,
            model: model,
            temperature: temperature
        )
    }
    
    /// Sends a direct HTTP request to the OpenAI API
    /// - Parameters:
    ///   - messages: The messages to send
    ///   - model: The model to use
    ///   - temperature: The temperature
    /// - Returns: A chat completion response
    private func sendDirectChatRequest(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) async throws -> ChatCompletionResponse {
        Logger.debug("SystemFingerprintFixClient: Sending direct HTTP request to OpenAI API")
        
        // Convert our messages to a format for JSON
        var jsonMessages: [[String: String]] = []
        for message in messages {
            let roleString: String
            switch message.role {
            case .system: roleString = "system"
            case .user: roleString = "user"
            case .assistant: roleString = "assistant"
            }
            
            jsonMessages.append([
                "role": roleString,
                "content": message.content
            ])
        }
        
        // Create the request body
        let requestBody: [String: Any] = [
            "model": model,
            "messages": jsonMessages,
            "temperature": temperature,
            "response_format": ["type": "json_object"]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Create the request
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Log the request details
        Logger.debug("SystemFingerprintFixClient: Sending request to OpenAI API")
        if let bodyString = String(data: jsonData, encoding: .utf8) {
            Logger.debug("SystemFingerprintFixClient: Request body: \(bodyString)")
        }
        
        // Send the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Log the response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            Logger.debug("SystemFingerprintFixClient: Raw API response: \(responseString)")
        }
        
        // Check the response
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("SystemFingerprintFixClient: Direct API request failed: \(errorMessage)")
            throw NSError(
                domain: "SystemFingerprintFixClient",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "API request failed: \(errorMessage)"]
            )
        }
        
        // Parse the response using a dictionary approach to avoid system_fingerprint issues
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            
            return ChatCompletionResponse(
                content: content,
                model: model
            )
        } else {
            // If we couldn't parse it this way, log the response and throw an error
            let responseString = String(data: data, encoding: .utf8) ?? "Invalid response"
            Logger.error("SystemFingerprintFixClient: Failed to parse direct API response: \(responseString)")
            throw NSError(
                domain: "SystemFingerprintFixClient",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse API response"]
            )
        }
    }
}
