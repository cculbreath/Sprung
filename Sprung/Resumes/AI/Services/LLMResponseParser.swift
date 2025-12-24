//
//  LLMResponseParser.swift
//  Sprung
//
import Foundation
/// Utility for parsing JSON responses from LLM outputs
/// Handles various response formats including code blocks and embedded JSON
struct LLMResponseParser {
    /// Parse JSON from text content with fallback strategies
    /// - Parameters:
    ///   - text: The raw text response from the LLM
    ///   - type: The expected Codable type to decode
    /// - Returns: Decoded object of type T
    /// - Throws: LLMError.decodingFailed if parsing fails
    static func parseJSON<T: Codable>(_ text: String, as type: T.Type) throws -> T {
        Logger.debug("🔍 Attempting to parse JSON from text: \(text.prefix(500))...")
        // First try direct parsing if the entire text is JSON
        if let jsonData = text.data(using: .utf8) {
            do {
                let result = try JSONDecoder().decode(type, from: jsonData)
                Logger.info("✅ Direct JSON parsing successful")
                return result
            } catch {
                Logger.debug("❌ Direct JSON parsing failed: \(error)")
                Logger.error("🚨 [JSON Debug] Full LLM response that failed direct parsing:")
                Logger.error("📄 [JSON Debug] Response length: \(text.count) characters")
                Logger.error("📄 [JSON Debug] Full response text:")
                Logger.error("--- START RESPONSE ---")
                Logger.error("\(text)")
                Logger.error("--- END RESPONSE ---")
            }
        }
        // Try to extract JSON from text (look for JSON between ```json and ``` or just {...})
        let cleanedText = extractJSONFromText(text)
        if let jsonData = cleanedText.data(using: .utf8) {
            do {
                let result = try JSONDecoder().decode(type, from: jsonData)
                Logger.info("✅ Extracted JSON parsing successful")
                return result
            } catch {
                Logger.debug("❌ Extracted JSON parsing failed: \(error)")
                Logger.error("🚨 [JSON Debug] Extracted text that failed parsing:")
                Logger.error("📄 [JSON Debug] Extracted length: \(cleanedText.count) characters")
                Logger.error("📄 [JSON Debug] Extracted text:")
                Logger.error("--- START EXTRACTED ---")
                Logger.error("\(cleanedText)")
                Logger.error("--- END EXTRACTED ---")
                Logger.error("🔍 [JSON Debug] Expected type: \(String(describing: type))")
                Logger.error("🔍 [JSON Debug] Decoding error details: \(error)")
            }
        } else {
            Logger.error("🚨 [JSON Debug] Could not convert extracted text to UTF-8 data")
            Logger.error("📄 [JSON Debug] Original text length: \(text.count)")
            Logger.error("📄 [JSON Debug] Extracted text: '\(cleanedText)'")
        }
        // If JSON parsing fails, include the full response in the error for debugging
        let fullResponsePreview = text.count > 1000 ? "\(text.prefix(1000))...[truncated]" : text
        let errorMessage = "Could not parse JSON from response. Full response: \(fullResponsePreview)"
        throw LLMError.decodingFailed(NSError(domain: "LLMResponseParser", code: 1, userInfo: [
            NSLocalizedDescriptionKey: errorMessage,
            "fullResponse": text
        ]))
    }
    /// Extract JSON from text that may contain other content
    /// Handles code blocks (```json) and standalone JSON objects/arrays
    /// Uses multiple fallback strategies for robust extraction
    /// - Parameter text: Raw text potentially containing JSON
    /// - Returns: Extracted JSON string
    static func extractJSONFromText(_ text: String) -> String {
        // Strategy 1: Look for JSON between markdown code blocks (```json...```)
        if let range = text.range(of: "```json") {
            let afterStart = text[range.upperBound...]
            if let endRange = afterStart.range(of: "```") {
                return String(afterStart[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Strategy 2: Look for JSON between generic code blocks (```...```)
        if let range = text.range(of: "```") {
            let afterStart = text[range.upperBound...]
            if let endRange = afterStart.range(of: "```") {
                let extracted = String(afterStart[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Only return if it looks like JSON (starts with { or [)
                if extracted.hasPrefix("{") || extracted.hasPrefix("[") {
                    return extracted
                }
            }
        }

        // Strategy 3: Try regex patterns for more complex scenarios
        let patterns = [
            "```json\\s*([\\s\\S]*?)```",  // JSON code block with capture group
            "```([\\s\\S]*?)```",           // Generic code block with capture group
            "\\{[\\s\\S]*\\}"               // Standalone JSON object
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                let extractedRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 0)
                if let swiftRange = Range(extractedRange, in: text) {
                    let extractedText = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Validate it looks like JSON before returning
                    if extractedText.hasPrefix("{") || extractedText.hasPrefix("[") {
                        return extractedText
                    }
                }
            }
        }

        // Strategy 4: Look for standalone JSON object using brace counting
        if let startRange = text.range(of: "{") {
            var braceCount = 1
            var index = text.index(after: startRange.lowerBound)
            while index < text.endIndex && braceCount > 0 {
                let char = text[index]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                }
                index = text.index(after: index)
            }
            if braceCount == 0 {
                let jsonRange = startRange.lowerBound..<index
                return String(text[jsonRange])
            }
        }

        // Strategy 5: Look for standalone JSON array using bracket counting
        if let startRange = text.range(of: "[") {
            var bracketCount = 1
            var index = text.index(after: startRange.lowerBound)
            while index < text.endIndex && bracketCount > 0 {
                let char = text[index]
                if char == "[" {
                    bracketCount += 1
                } else if char == "]" {
                    bracketCount -= 1
                }
                index = text.index(after: index)
            }
            if bracketCount == 0 {
                let jsonRange = startRange.lowerBound..<index
                return String(text[jsonRange])
            }
        }

        // Fallback: return original text
        return text
    }
}
