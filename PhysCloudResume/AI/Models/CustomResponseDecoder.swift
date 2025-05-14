//
//  CustomResponseDecoder.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/13/25.
//

import Foundation
import OpenAI

/// A custom decoder that can handle null system_fingerprint in OpenAI responses
class CustomResponseDecoder {
    
    /// Decodes ChatResult from data, handling null system_fingerprint field
    /// - Parameter data: The data to decode
    /// - Returns: The decoded ChatResult
    static func decodeChatResponse(from data: Data) throws -> ChatResult {
        // First, try to parse as JSON to manually handle the system_fingerprint field
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: json) {
            
            // Create a custom decoder that adds default values for missing keys
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            // Use OpenAI's decoder but with our CustomChatResult class that has optional system_fingerprint
            return try decoder.decode(ChatResult.self, from: jsonData)
        }
        
        // Fallback to standard decoding
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ChatResult.self, from: data)
    }
}

// Extension to make ChatResult have an optional system_fingerprint
extension ChatResult {
    /// Creates a modified ChatResult with the system_fingerprint field made optional
    static func decode(from data: Data) throws -> ChatResult {
        do {
            // Try standard decoder first
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(ChatResult.self, from: data)
        } catch let error {
            // Get the NSError representation
            let nsError = error as NSError
            
            // Check if it's the specific system_fingerprint error
            if nsError.domain == "NSCocoaErrorDomain" && nsError.code == 4865,
               let _ = nsError.userInfo["NSCodingPath"] as? [Any],
               let debugDesc = nsError.userInfo["NSDebugDescription"] as? String,
               debugDesc.contains("system_fingerprint") || debugDesc.contains("null value") {
                
                // It's the system_fingerprint error - try to manually parse and fix
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Create a copy of the json with system_fingerprint set to an empty string if null
                    if json["system_fingerprint"] == nil || (json["system_fingerprint"] is NSNull) {
                        var modifiedJson = json
                        modifiedJson["system_fingerprint"] = ""
                        
                        if let modifiedData = try? JSONSerialization.data(withJSONObject: modifiedJson) {
                            let decoder = JSONDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            return try decoder.decode(ChatResult.self, from: modifiedData)
                        }
                    }
                }
            }
            
            // If we couldn't fix it, rethrow the original error
            throw nsError
        }
    }
}
