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
                // Claude may include text before or after the JSON, try to extract just the JSON object
                if let jsonContent = extractJSONFromContent(content) {
                    Logger.debug("👤 Claude JSON response extracted: \(String(describing: jsonContent.prefix(100)))...")
                    return .structured(jsonContent.data(using: .utf8) ?? Data())
                } else {
                    // If extraction fails, try with the raw content
                    Logger.debug("👤 Claude JSON extraction failed, using raw content")
                    return .structured(content.data(using: .utf8) ?? Data())
                }
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


