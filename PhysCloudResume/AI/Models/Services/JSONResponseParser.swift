//
//  JSONResponseParser.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/10/25.
//

import Foundation
/// Data transformer for converting LLM responses to structured objects
struct JSONResponseParser {
    
    /// Parse structured response with fallback strategies
    static func parseStructured<T: Codable>(_ response: LLMResponseDTO, as type: T.Type) throws -> T {
        guard let content = response.choices.first?.message?.text else {
            throw LLMError.unexpectedResponseFormat
        }
        
        // Try to parse JSON from the response content
        return try parseJSONFromText(content, as: type)
    }
    
    /// Parse flexible JSON response with enhanced error handling and recovery strategies
    static func parseFlexible<T: Codable>(from response: LLMResponseDTO, as type: T.Type) throws -> T {
        guard let content = response.choices.first?.message?.text else {
            throw LLMError.unexpectedResponseFormat
        }
        
        Logger.debug("🔍 Parsing flexible JSON response (\(content.count) chars): \(content.prefix(500))...")
        
        // Try to parse JSON from the response content with enhanced fallback strategies
        return try parseJSONFromTextFlexible(content, as: type)
    }
    
    /// Extract and parse JSON from text response
    private static func parseJSONFromText<T: Codable>(_ text: String, as type: T.Type) throws -> T {
        Logger.debug("🔍 Attempting to parse JSON from text: \(text.prefix(500))...")
        
        // First try direct parsing if the entire text is JSON
        if let jsonData = text.data(using: .utf8) {
            do {
                let result = try JSONDecoder().decode(type, from: jsonData)
                Logger.info("✅ Direct JSON parsing successful")
                return result
            } catch {
                Logger.debug("❌ Direct JSON parsing failed: \(error)")
                if let decodingError = error as? DecodingError {
                    Logger.debug("❌ Detailed decoding error: \(decodingError)")
                    switch decodingError {
                    case .dataCorrupted(let context):
                        Logger.debug("❌ Data corrupted at path: \(context.codingPath), description: \(context.debugDescription)")
                        if let underlyingError = context.underlyingError {
                            Logger.debug("❌ Underlying error: \(underlyingError)")
                        }
                    default:
                        Logger.debug("❌ Other decoding error: \(decodingError)")
                    }
                }
            }
        }
        
        // Try to find JSON blocks in the text using improved patterns
        let jsonPatterns = [
            #"\{(?:[^{}]|{[^{}]*})*\}"#,  // Non-greedy object matching
            #"\[(?:[^\[\]]|\[[^\[\]]*\])*\]"#,  // Non-greedy array matching
            #"\{[\s\S]*?\}"#,  // Minimal object matching
            #"\[[\s\S]*?\]"#   // Minimal array matching
        ]
        
        for pattern in jsonPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let jsonRange = Range(match.range, in: text) {
                
                let jsonString = String(text[jsonRange])
                Logger.debug("🔍 Trying JSON string: \(jsonString.prefix(100))...")
                
                if let jsonData = jsonString.data(using: .utf8) {
                    do {
                        let result = try JSONDecoder().decode(type, from: jsonData)
                        Logger.info("✅ JSON parsing successful with pattern: \(pattern)")
                        return result
                    } catch {
                        Logger.debug("⚠️ JSON parsing failed for pattern \(pattern): \(error)")
                        continue
                    }
                }
            }
        }
        
        Logger.error("❌ All JSON parsing attempts failed")
        throw LLMError.unexpectedResponseFormat
    }
    
    /// Enhanced JSON parsing with additional fallback strategies for flexible responses
    private static func parseJSONFromTextFlexible<T: Codable>(_ text: String, as type: T.Type) throws -> T {
        Logger.debug("🔍 Attempting flexible JSON parsing from text: \(text.prefix(500))...")
        
        // First try the standard parsing approach
        do {
            return try parseJSONFromText(text, as: type)
        } catch {
            Logger.debug("🔄 Standard parsing failed, trying enhanced strategies...")
        }
        
        // Enhanced cleanup strategies for models that include extra text
        let cleanupStrategies = [
            // Remove common markdown code block formatting
            { (text: String) -> String in
                text.replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            },
            // Remove text before and after JSON by finding the longest valid JSON
            { (text: String) -> String in
                // Find all potential JSON objects/arrays and try the largest one
                let patterns = [
                    #"\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}"#,  // Nested object matching
                    #"\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\]"#  // Nested array matching
                ]
                
                var candidates: [(String, Int)] = []
                for pattern in patterns {
                    if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                        for match in matches {
                            if let range = Range(match.range, in: text) {
                                let candidate = String(text[range])
                                candidates.append((candidate, candidate.count))
                            }
                        }
                    }
                }
                
                // Return the longest candidate, or original text if none found
                return candidates.max(by: { $0.1 < $1.1 })?.0 ?? text
            },
            // Remove leading/trailing text by finding balanced braces
            { (text: String) -> String in
                var startIndex: String.Index?
                var endIndex: String.Index?
                var braceCount = 0
                
                for (index, char) in text.enumerated() {
                    let stringIndex = text.index(text.startIndex, offsetBy: index)
                    if char == "{" {
                        if startIndex == nil {
                            startIndex = stringIndex
                        }
                        braceCount += 1
                    } else if char == "}" {
                        braceCount -= 1
                        if braceCount == 0 && startIndex != nil {
                            endIndex = text.index(after: stringIndex)
                            break
                        }
                    }
                }
                
                if let start = startIndex, let end = endIndex {
                    return String(text[start..<end])
                }
                return text
            }
        ]
        
        // Try each cleanup strategy
        for (index, strategy) in cleanupStrategies.enumerated() {
            let cleanedText = strategy(text)
            if cleanedText != text {
                Logger.debug("🧹 Trying cleanup strategy \(index + 1)")
                Logger.debug("🧹 Strategy \(index + 1) input: \(text.prefix(300))...")
                Logger.debug("🧹 Strategy \(index + 1) output: \(cleanedText.prefix(300))...")
                do {
                    let result = try parseJSONFromText(cleanedText, as: type)
                    Logger.info("✅ Flexible parsing successful with strategy \(index + 1)")
                    return result
                } catch {
                    Logger.debug("⚠️ Cleanup strategy \(index + 1) failed: \(error)")
                    Logger.debug("⚠️ Strategy \(index + 1) cleaned text (first 500 chars): \(cleanedText.prefix(500))")
                    continue
                }
            }
        }
        
        Logger.error("❌ All flexible parsing strategies failed")
        Logger.error("🔍 FULL RESPONSE CONTENT FOR DEBUGGING:")
        Logger.error("📄 Content length: \(text.count) characters")
        Logger.error("📄 Full content:\n\(text)")
        Logger.error("📄 First 1000 chars: \(text.prefix(1000))")
        Logger.error("📄 Last 1000 chars: \(text.suffix(1000))")
        throw LLMError.decodingFailed(NSError(domain: "FlexibleJSONParsing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not extract valid JSON from response"]))
    }
}
