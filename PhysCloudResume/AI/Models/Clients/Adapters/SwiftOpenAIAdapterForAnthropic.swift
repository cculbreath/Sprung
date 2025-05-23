import Foundation
import SwiftOpenAI

/// Claude (Anthropic)-specific adapter for SwiftOpenAI
class SwiftOpenAIAdapterForAnthropic: BaseSwiftOpenAIAdapter {
    /// The app state that contains user settings and preferences
    private weak var appState: AppState?

    /// Initializes the adapter with Claude configuration and app state
    /// - Parameters:
    ///   - config: The provider configuration
    ///   - appState: The application state
    init(config: LLMProviderConfig, appState: AppState) {
        self.appState = appState
        super.init(config: config)

        // Log Claude configuration for debugging
        Logger.debug("👤 Claude adapter configured with:")
        Logger.debug("  - Base URL: \(config.baseURL ?? "nil")")
        Logger.debug("  - API Version: \(config.apiVersion ?? "nil")")
    }

    /// Executes a query against the Claude API using SwiftOpenAI
    /// - Parameter query: The query to execute
    /// - Returns: The response from the Claude API
    override func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
        // Determine if this is a query for structured output
        let isStructuredOutput = query.desiredResponseType != nil
        let typeName = isStructuredOutput ? String(describing: query.desiredResponseType) : "none"
        let isRevisionsContainer = typeName.contains("RevisionsContainer")
        let isFixFitsResponseContainer = typeName.contains("FixFitsResponseContainer")
        let isContentsFitResponse = typeName.contains("ContentsFitResponse")

        // Ensure we're using a valid Claude model - CRITICAL FIX
        let modelIdentifier = query.modelIdentifier
        if !modelIdentifier.contains("claude") {
            // Log the model mismatch
            Logger.error("🚨 Model mismatch in Claude adapter: '\(modelIdentifier)' is not a Claude model")
            throw AppLLMError.clientError("Invalid model for Claude API: \(modelIdentifier) - must be a Claude model")
        }
        
        // Verify that this is a correctly formatted Claude model name from Anthropic's API
        // Model names must follow the pattern: claude-3-opus-20240229, claude-3-5-haiku-latest, etc.
        let validModelPattern = modelIdentifier.contains("claude-3") || 
                                modelIdentifier.contains("claude-3-5") ||
                                modelIdentifier.contains("claude-3.5")
        
        if !validModelPattern {
            Logger.warning("⚠️ Potentially invalid Claude model format: \(modelIdentifier). Using it anyway, but this may fail.")
        }

        // Prepare parameters for Claude with some modifications
        var swiftMessages = MessageConverter.swiftOpenAIMessagesFrom(appMessages: query.messages)

        // Claude requires special handling for structured outputs
        let swiftResponseFormat: SwiftOpenAI.ResponseFormat? = isStructuredOutput ? .jsonObject : nil

        // For structured output, ensure system message instructs model to output valid JSON
        if !swiftMessages.isEmpty && swiftMessages[0].role == "system" {
            let originalContent: String
            if case let .text(text) = swiftMessages[0].content {
                originalContent = text
            } else {
                originalContent = ""
            }

            // Enhanced instructions based on the type of output
            var enhancedContent = originalContent

            if isRevisionsContainer {
                // Special handling for RevisionsContainer with detailed instructions
                enhancedContent += """
                
                IMPORTANT: Your response MUST be a valid JSON object with the following structure:
                {
                  "revArray": [
                    {
                      "id": "UUID-string",
                      "oldValue": "original text from resume",
                      "newValue": "suggested improved text",
                      "valueChanged": true or false,
                      "why": "explanation for the change",
                      "isTitleNode": false,
                      "treePath": "path in document"
                    },
                    ... more revision nodes ...
                  ]
                }
                
                Important requirements:
                1. Each "id" should be a unique string (UUID format preferred)
                2. Include several meaningful revisions in the revArray, at least 5-10
                3. Each revision should improve the resume for the target job
                4. Your response must ONLY contain this JSON structure with no additional text or explanation
                5. Each revision should be focused on a specific portion of the resume
                """
            } else if isFixFitsResponseContainer {
                // Special handling for FixFitsResponseContainer
                enhancedContent += """
                
                IMPORTANT: Your response MUST be a valid JSON object with the following structure:
                {
                  "revised_skills_and_expertise": [
                    {
                      "id": "original-uuid-string",
                      "newValue": "revised content for the skill",
                      "originalValue": "original content echoed back",
                      "treePath": "original treePath echoed back",
                      "isTitleNode": true or false
                    },
                    ... more skill nodes ...
                  ]
                }
                
                Important requirements:
                1. Wrap the array in an object with the key "revised_skills_and_expertise"
                2. Echo back the exact original values for id, originalValue, treePath, and isTitleNode
                3. Only modify the "newValue" field to make content shorter/more concise
                4. Your response must ONLY contain this JSON structure with no additional text
                """
            } else if isContentsFitResponse {
                // Special handling for ContentsFitResponse
                enhancedContent += """
                
                IMPORTANT: Your response MUST be a valid JSON object with the following structure:
                {
                  "contentsFit": true or false,
                  "overflow_line_count": integer
                }
                
                Important requirements:
                1. Analyze the image to determine if content fits without overflow
                2. Count the number of text lines that are overflowing or overlapping content below
                3. Use 0 for overflow_line_count if content fits properly OR if bounding boxes overlap but no actual text lines overflow
                4. Be conservative in line count estimation - better to underestimate than overestimate
                5. Return exactly this JSON structure with no additional text
                6. Use boolean true/false for contentsFit, not strings
                7. Use integer number for overflow_line_count, not strings
                """
            } else if typeName.contains("JobRecommendation") {
                enhancedContent += "\n\nIMPORTANT: Your response MUST be a valid JSON object with exactly these fields: "
                + "recommendedJobId (a string containing a UUID) and reason (a string explanation). "
                + "Do not include any text outside the JSON object. Format: {\"recommendedJobId\": \"uuid-string\", \"reason\": \"explanation\"}"
            } else {
                // Generic structured output instructions
                enhancedContent += """
                
                IMPORTANT: Your response MUST be a valid JSON object with exactly the required fields.
                Do not include any text outside the JSON object. Response must be valid, parseable JSON.
                """
            }

            // Replace first message with enhanced content
            swiftMessages[0] = ChatCompletionParameters.Message(
                role: .system,
                content: .text(enhancedContent)
            )
        }

        // Build custom parameters for Claude
        let claudeModel = SwiftOpenAI.Model.custom(query.modelIdentifier)
        let parameters = ChatCompletionParameters(
            messages: swiftMessages,
            model: claudeModel,
            responseFormat: swiftResponseFormat,
            temperature: query.temperature
        )

        do {
            // Execute the chat request
            let result = try await swiftService.startChat(parameters: parameters)

            // Process the result
            guard let content = result.choices?.first?.message?.content else {
                throw AppLLMError.unexpectedResponseFormat
            }

            // If structured output is requested, handle it specially
            if isStructuredOutput {
                // First, check if we need to wrap arrays for specific response types
                let processedContent: Data
                
                // Extract JSON content from markdown or other formatting
                if let jsonContent = extractJSONFromContent(content) {
                    Logger.debug("👤 Claude JSON response extracted: \(String(describing: jsonContent.prefix(100)))...")
                    
                    // Check if content is a JSON array that needs wrapping
                    let trimmedContent = jsonContent.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if trimmedContent.hasPrefix("[") {
                        // Validate it's a proper JSON array
                        if let data = trimmedContent.data(using: .utf8),
                           let _ = try? JSONSerialization.jsonObject(with: data) {
                            
                            if isRevisionsContainer {
                                // Wrap array in revArray object
                                let revisionsContent = """
                                {
                                  "revArray": \(trimmedContent)
                                }
                                """
                                Logger.debug("👤 Wrapped array in revArray object")
                                processedContent = Data(revisionsContent.utf8)
                            } else if isFixFitsResponseContainer {
                                // Wrap array in revised_skills_and_expertise object
                                let fixFitsContent = """
                                {
                                  "revised_skills_and_expertise": \(trimmedContent)
                                }
                                """
                                Logger.debug("👤 Wrapped array in revised_skills_and_expertise object")
                                processedContent = Data(fixFitsContent.utf8)
                            } else {
                                // For other types, use the array as-is
                                processedContent = Data(trimmedContent.utf8)
                            }
                        } else {
                            // Invalid JSON array, use as-is
                            processedContent = Data(jsonContent.utf8)
                        }
                    } else {
                        // Not an array, use the extracted JSON as-is
                        processedContent = Data(jsonContent.utf8)
                    }
                } else {
                    // If extraction fails, try with the raw content
                    Logger.debug("👤 Claude JSON extraction failed, using raw content")
                    processedContent = Data(content.utf8)
                }
                
                return .structured(processedContent)
            } else {
                // Return text response for non-structured outputs
                return .text(content)
            }
        } catch {
            // Process and enhance error information
            Logger.error("👤 Claude API error: \(error.localizedDescription)")

            if let apiError = error as? SwiftOpenAI.APIError {
                switch apiError {
                    case .responseUnsuccessful(let description, let statusCode):
                        throw AppLLMError.clientError("Claude API Error (HTTP \(statusCode)): \(description)")
                    default:
                        throw AppLLMError.clientError("Claude API Error: \(apiError.localizedDescription)")
                }
            } else {
                throw AppLLMError.clientError("Claude API Error: \(error.localizedDescription)")
            }
        }
    }

    /// Extracts valid JSON from the content string
    /// - Parameter content: The raw content string that may contain JSON
    /// - Returns: Cleaned JSON string or nil if extraction fails
    private func extractJSONFromContent(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        // Handle markdown code blocks first
        if trimmed.hasPrefix("```json") || trimmed.hasPrefix("```") {
            // Extract content between code block markers
            let lines = trimmed.components(separatedBy: .newlines)
            var jsonLines: [String] = []
            var insideCodeBlock = false
            
            for line in lines {
                if line.hasPrefix("```") {
                    if !insideCodeBlock {
                        insideCodeBlock = true
                        continue
                    } else {
                        // End of code block
                        break
                    }
                } else if insideCodeBlock {
                    jsonLines.append(line)
                }
            }
            
            let extractedContent = jsonLines.joined(separator: "\n")
            return validateAndReturnJSON(extractedContent)
        }
        
        // Handle direct JSON content
        return validateAndReturnJSON(trimmed)
    }
    
    /// Validates and returns JSON content if valid
    /// - Parameter content: The content to validate
    /// - Returns: Valid JSON string or nil
    private func validateAndReturnJSON(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        // Special case: if the content is already a valid JSON array, return it
        if trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                return trimmed
            }
        }
        
        // Special case: if the content is already a valid JSON object, return it
        if trimmed.hasPrefix("{") {
            if let data = trimmed.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                return trimmed
            }
        }
        
        // Look for the first { and the last } to extract the JSON object
        guard let startIndex = trimmed.firstIndex(of: "{"),
              let endIndex = trimmed.lastIndex(of: "}"),
              startIndex < endIndex else {
            // Try looking for JSON array instead
            guard let arrayStart = trimmed.firstIndex(of: "["),
                  let arrayEnd = trimmed.lastIndex(of: "]"),
                  arrayStart < arrayEnd else {
                return nil
            }
            
            let jsonSubstring = trimmed[arrayStart...arrayEnd]
            let jsonString = String(jsonSubstring)
            
            // Validate that it's valid JSON
            guard let data = jsonString.data(using: .utf8),
                  let _ = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            
            return jsonString
        }
        
        // Extract the JSON substring for objects
        let jsonSubstring = trimmed[startIndex...endIndex]
        let jsonString = String(jsonSubstring)
        
        // Validate that it's valid JSON
        guard let data = jsonString.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        
        return jsonString
    }
}


