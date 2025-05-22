import Foundation
import SwiftOpenAI

/// Gemini-specific adapter for SwiftOpenAI
class SwiftOpenAIAdapterForGemini: BaseSwiftOpenAIAdapter {
    /// The app state that contains user settings and preferences
    private weak var appState: AppState?

    /// Initializes the adapter with Gemini configuration and app state
    /// - Parameters:
    ///   - config: The provider configuration
    ///   - appState: The application state
    init(config: LLMProviderConfig, appState: AppState) {
        self.appState = appState
        super.init(config: config)

        // Log Gemini configuration for debugging
        Logger.debug("🌟 Gemini adapter configured with:")
        Logger.debug("  - Base URL: \(config.baseURL ?? "nil")")
        Logger.debug("  - API Version: \(config.apiVersion ?? "nil")")
        Logger.debug("  - Proxy Path: \(config.proxyPath ?? "nil")")
    }

    /// Executes a query against the Gemini API using SwiftOpenAI's OpenAI-compatible endpoint
    /// - Parameter query: The query to execute
    /// - Returns: The response from the Gemini API
    override func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
        // Determine if this is a request for structured output
        let isStructuredOutput = query.desiredResponseType != nil
        let typeName = isStructuredOutput ? String(describing: query.desiredResponseType) : "none"
        let isRevisionsContainer = typeName.contains("RevisionsContainer")
        let isJobRecommendation = typeName.contains("JobRecommendation")

        // Ensure we're using a valid Gemini model - CRITICAL FIX
        let modelIdentifier = query.modelIdentifier
        if !modelIdentifier.contains("gemini") {
            // Log the model mismatch
            Logger.error("🚨 Model mismatch in Gemini adapter: '\(modelIdentifier)' is not a Gemini model")
            throw AppLLMError.clientError("Invalid model for Gemini API: \(modelIdentifier) - must be a Gemini model")
        }

        // Convert AppLLMMessages to SwiftOpenAI Messages
        var swiftMessages = MessageConverter.swiftOpenAIMessagesFrom(appMessages: query.messages)

        // Important: For Gemini, we need to ensure the model string is correctly formatted
        // Gemini's OpenAI-compatible API expects model names prefixed with "models/"
        let modelString = query.modelIdentifier
        let fullModelString = modelString.hasPrefix("models/") ? modelString : "models/\(modelString)"

        // Explicit model creation without relying on a static method
        let model: SwiftOpenAI.Model = .custom(fullModelString)

        // Handle structured JSON output
        let swiftResponseFormat: SwiftOpenAI.ResponseFormat? = isStructuredOutput ? .jsonObject : nil

        // Log that we're using JSON mode
        Logger.debug("🌟 Gemini adapter using JSON mode for structured output: \(typeName)")

        // For structured output, ensure system message instructs model to output valid JSON
        // This is critical for Gemini to produce the expected JSON
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
            } else if isJobRecommendation {
                enhancedContent += "\n\nIMPORTANT: Your response MUST be a valid JSON object with exactly these fields: "
                + "recommendedJobId (a string containing a UUID) and reason (a string explanation). "
                + "Do not include any text outside the JSON object. Format: {\"recommendedJobId\": \"uuid-string\", \"reason\": \"explanation\"}"
            } else {
                // Generic structured output instructions
                enhancedContent += """
                
                IMPORTANT: Your response MUST be a valid JSON object conforming to the required structure.
                Do not include any text outside the JSON object. Response must be valid, parseable JSON.
                """
            }

            // Replace first message with enhanced content
            swiftMessages[0] = ChatCompletionParameters.Message(
                role: .system,
                content: .text(enhancedContent)
            )
        }

        // Build chat completion parameters
        let parameters = ChatCompletionParameters(
            messages: swiftMessages,
            model: model,
            responseFormat: swiftResponseFormat,
            temperature: query.temperature
        )

        do {
            // Execute the chat request with debug logging
            Logger.debug("🌟 Sending request to Gemini API with model: \(fullModelString)")
            let result = try await swiftService.startChat(parameters: parameters)

            // Process the result
            guard let content = result.choices?.first?.message?.content else {
                Logger.error("🌟 Gemini API returned unexpected response format (no content)")
                throw AppLLMError.unexpectedResponseFormat
            }

            Logger.debug("🌟 Gemini API request successful")

            // For structured responses, we need to clean the JSON
            if isStructuredOutput {
                // Extract JSON from the content
                let processedContent: Data
                if let jsonContent = extractJSONFromContent(content) {
                    Logger.debug("🌟 Extracted JSON: \(String(describing: jsonContent.prefix(200)))")
                    processedContent = Data(jsonContent.utf8)
                } else {
                    // Try to handle array format responses
                    if isRevisionsContainer && content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).hasPrefix("[") {
                        // If this is a RevisionsContainer expecting an array
                        let revisionsContent = """
                        {
                          "revArray": \(content)
                        }
                        """
                        Logger.debug("🌟 Wrapped array in revArray object")
                        processedContent = Data(revisionsContent.utf8)
                    } else {
                        // If we couldn't extract JSON, try to pass the content directly
                        processedContent = Data(content.utf8)
                    }
                }
                return .structured(processedContent)
            } else {
                // Return text response
                return .text(content)
            }
        } catch {
            Logger.error("🌟 Gemini API error: \(error.localizedDescription)")

            // Provide more detailed error for debugging
            if let apiError = error as? SwiftOpenAI.APIError {
                switch apiError {
                case .responseUnsuccessful(let description, let statusCode):
                    Logger.error("🌟 Gemini API HTTP \(statusCode): \(description)")
                    
                    // Special handling for 400 errors to help diagnose the issue
                    if statusCode == 400 {
                        throw AppLLMError.clientError("Gemini API HTTP 400: \(description). This may be due to incorrect model format or unsupported features.")
                    }
                    
                    throw AppLLMError.clientError("Gemini API HTTP \(statusCode): \(description)")
                    
                case .jsonDecodingFailure(let description):
                    Logger.error("🌟 Gemini API JSON decoding error: \(description)")
                    throw AppLLMError.clientError("Gemini API response parsing error: \(description)")
                    
                default:
                    throw AppLLMError.clientError("Gemini API error: \(apiError.displayDescription)")
                }
            } else {
                throw AppLLMError.clientError("Gemini API error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Extracts valid JSON from the content string
    /// - Parameter content: The raw content string that may contain JSON
    /// - Returns: Cleaned JSON string or nil if extraction fails
    private func extractJSONFromContent(_ content: String) -> String? {
        // Special case: if the content is already valid JSON array, return it
        if content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).hasPrefix("[") {
            if let data = content.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                return content
            }
        }
        
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
}
