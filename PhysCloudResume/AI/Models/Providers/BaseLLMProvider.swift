import Foundation
import SwiftUI
import SwiftOpenAI

/// Base provider class for LLM interactions
/// Provides common functionality for all LLM provider implementations
@Observable
class BaseLLMProvider {
    // MARK: - Properties
    
    /// The OpenRouter client that will be used for API calls
    private(set) var openRouterClient: OpenAIService?
    
    /// The app state for accessing OpenRouter configuration
    internal var appState: AppState?
    
    // Message tracking properties
    private var streamTask: Task<Void, Never>?
    var message: String = ""
    var messages: [String] = []
    
    // Conversation history
    var conversationHistory: [AppLLMMessage] = []
    
    // Error handling
    var errorMessage: String = ""
    
    // Track the last model used to know when to switch clients
    var lastModelUsed: String = ""
    
    // MARK: - Actor to safely coordinate continuations
    
    /// Actor to safely coordinate continuations and prevent multiple resumes
    private actor ContinuationCoordinator {
        private var hasResumed = false

        func resumeWithValue(_ value: AppLLMResponse, continuation: UnsafeContinuation<AppLLMResponse, Error>) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(returning: value)
        }

        func resumeWithError(_ error: Error, continuation: UnsafeContinuation<AppLLMResponse, Error>) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(throwing: error)
        }
    }
    
    // MARK: - Initializers
    
    /// Initialize with an app state to create the OpenRouter client
    /// - Parameter appState: The application state
    init(appState: AppState) {
        self.appState = appState
        // Get API key from UserDefaults directly to avoid @AppStorage conflicts
        let apiKey = UserDefaults.standard.string(forKey: "openRouterApiKey") ?? ""
        if !apiKey.isEmpty {
            self.openRouterClient = OpenRouterClientFactory.createClient(apiKey: apiKey)
        }
    }
    
    /// Initialize with a specific OpenRouter client
    /// - Parameter client: An OpenRouter client
    init(openRouterClient: OpenAIService) {
        self.openRouterClient = openRouterClient
    }
    
    // MARK: - Conversation Management Methods
    
    /// Initialize a new conversation with system and user messages
    /// - Parameters:
    ///   - systemPrompt: The system prompt to use
    ///   - userPrompt: The initial user prompt
    /// - Returns: The conversation history after initialization
    func initializeConversation(systemPrompt: String, userPrompt: String) -> [AppLLMMessage] {
        // Clear existing conversation history
        conversationHistory = []
        
        // Add system message
        conversationHistory.append(AppLLMMessage(role: .system, text: systemPrompt))
        
        // Add user message
        conversationHistory.append(AppLLMMessage(role: .user, text: userPrompt))
        
        return conversationHistory
    }
    
    /// Add a user message to the conversation history
    /// - Parameter text: The user message text
    /// - Returns: The updated conversation history
    func addUserMessage(_ text: String) -> [AppLLMMessage] {
        conversationHistory.append(AppLLMMessage(role: .user, text: text))
        return conversationHistory
    }
    
    /// Add an assistant message to the conversation history
    /// - Parameter text: The assistant message text
    /// - Returns: The updated conversation history
    func addAssistantMessage(_ text: String) -> [AppLLMMessage] {
        conversationHistory.append(AppLLMMessage(role: .assistant, text: text))
        return conversationHistory
    }
    
    /// Updates the OpenRouter client if needed
    /// - Parameter appState: The current application state
    func updateClientIfNeeded(appState: AppState) {
        // Get API key from UserDefaults directly to avoid @AppStorage conflicts
        let apiKey = UserDefaults.standard.string(forKey: "openRouterApiKey") ?? ""
        // Only update if we don't have a client or the API key changed
        if openRouterClient == nil && !apiKey.isEmpty {
            self.openRouterClient = OpenRouterClientFactory.createClient(apiKey: apiKey)
            self.appState = appState
        }
    }
    
    /// Execute a query using the OpenRouter client
    /// - Parameter query: The query to execute
    /// - Returns: The response from the LLM
    func executeQuery(_ query: AppLLMQuery) async throws -> AppLLMResponse {
        guard let client = openRouterClient else {
            let error = AppLLMError.clientError("OpenRouter client not configured")
            errorMessage = error.localizedDescription
            throw error
        }
        
        do {
            return try await executeOpenRouterQuery(query, using: client)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    /// Execute a query directly with OpenRouter
    private func executeOpenRouterQuery(_ query: AppLLMQuery, using client: OpenAIService) async throws -> AppLLMResponse {
        // Convert AppLLMMessage to SwiftOpenAI format
        let openAIMessages = try convertToOpenAIMessages(query.messages)
        
        
        // Check if model supports structured output
        let model = await appState?.openRouterService.findModel(id: query.modelIdentifier)
        let supportsStructuredOutput = model?.supportsStructuredOutput ?? false
        
        
        // Build parameters
        var parameters = ChatCompletionParameters(
            messages: openAIMessages,
            model: .custom(query.modelIdentifier)
        )
        
        if let temperature = query.temperature {
            parameters.temperature = temperature
        }
        
        // Handle structured output if requested and supported
        if let responseType = query.desiredResponseType, supportsStructuredOutput {
            if let jsonSchema = query.jsonSchema {
                parameters.responseFormat = LLMSchemaBuilder.createResponseFormat(
                    for: responseType,
                    jsonSchema: jsonSchema
                )
            } else {
                parameters.responseFormat = LLMSchemaBuilder.createResponseFormat(for: responseType)
            }
            
        } else if query.desiredResponseType != nil && !supportsStructuredOutput {
            // Add system prompt for non-structured output models
            let fallbackPrompt = createFallbackStructuredPrompt(for: query.desiredResponseType!)
            parameters.messages.insert(
                ChatCompletionParameters.Message(role: .system, content: .text(fallbackPrompt)),
                at: 0
            )
        }
        
        // Execute the request
        do {
            let response = try await client.startChat(parameters: parameters)
            
            // Process response
            if let content = response.choices?.first?.message?.content {
                
                if query.desiredResponseType != nil {
                    // Return as structured data for JSON decoding
                    guard let data = content.data(using: String.Encoding.utf8) else {
                        throw AppLLMError.decodingError("Could not convert response to UTF-8 data")
                    }
                    return .structured(data)
                } else {
                    return .text(content)
                }
            } else {
                throw AppLLMError.unexpectedResponseFormat
            }
        } catch {
            // Log the actual error from the API
            Logger.error("🚨 API call failed with error: \(error)")
            if let apiError = error as? APIError {
                Logger.error("🚨 API Error details: \(apiError.displayDescription)")
            }
            throw error
        }
    }
    
    /// Convert AppLLMMessage array to SwiftOpenAI message format
    private func convertToOpenAIMessages(_ messages: [AppLLMMessage]) throws -> [ChatCompletionParameters.Message] {
        return messages.map { appMessage in
            let role: ChatCompletionParameters.Message.Role
            switch appMessage.role {
            case .system: role = .system
            case .user: role = .user
            case .assistant: role = .assistant
            }
            
            // Handle multimodal content
            if appMessage.contentParts.count == 1, case .text(let text) = appMessage.contentParts[0] {
                // Simple text message
                return ChatCompletionParameters.Message(role: role, content: .text(text))
            } else {
                // Multimodal message with text and/or images
                let content = appMessage.contentParts.compactMap { part -> ChatCompletionParameters.Message.ContentType.MessageContent? in
                    switch part {
                    case .text(let text):
                        return ChatCompletionParameters.Message.ContentType.MessageContent.text(text)
                    case .imageUrl(let base64Data, let mimeType):
                        let dataUrl = "data:\(mimeType);base64,\(base64Data)"
                        if let url = URL(string: dataUrl) {
                            return ChatCompletionParameters.Message.ContentType.MessageContent.imageUrl(.init(url: url))
                        }
                        return nil
                    }
                }
                return ChatCompletionParameters.Message(role: role, content: .contentArray(content))
            }
        }
    }
    
    /// Create fallback system prompt for models that don't support structured output
    private func createFallbackStructuredPrompt(for responseType: Decodable.Type) -> String {
        let typeName = String(describing: responseType)
        return """
        You must respond with valid JSON that matches the expected structure. Your response should contain ONLY the JSON object, with no additional text, explanations, or formatting. The JSON must be valid and parseable.
        
        Expected response type: \(typeName)
        
        Ensure your JSON response:
        - Is properly formatted with correct syntax
        - Contains all required fields for the \(typeName) structure
        - Uses appropriate data types (strings in quotes, numbers without quotes, booleans as true/false)
        - Has no trailing commas or syntax errors
        """
    }

    /// Execute a query with a timeout
    /// - Parameters:
    ///   - query: The query to execute
    ///   - timeout: Timeout in seconds (default: 180)
    /// - Returns: The response from the LLM
    func executeQueryWithTimeout(_ query: AppLLMQuery, timeout: TimeInterval = 180) async throws -> AppLLMResponse {
        // Update the last model used for tracking
        lastModelUsed = query.modelIdentifier
        
        // Use a task with timeout to handle API timeouts gracefully
        return try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<AppLLMResponse, Error>) in
            // Create a coordination actor to ensure we only resume once
            let coordinator = ContinuationCoordinator()
            
            // Create a task to execute the query
            let task = Task {
                do {
                    let result = try await executeQuery(query)
                    // Resume with success result
                    await coordinator.resumeWithValue(result, continuation: continuation)
                } catch {
                    // Resume with error
                    await coordinator.resumeWithError(error, continuation: continuation)
                }
            }
            
            // Create a timeout task
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                // Cancel the main task if it's still running
                task.cancel()
                
                // Resume with timeout error if continuation hasn't been resumed
                await coordinator.resumeWithError(
                    AppLLMError.timeout("Request timed out after \(timeout) seconds"),
                    continuation: continuation
                )
            }
        }
    }
    
    /// Process a structured response from the LLM
    /// - Parameters:
    ///   - response: The raw response from the LLM
    ///   - type: The expected return type
    /// - Returns: The decoded structured output
    func processStructuredResponse<T: Decodable>(_ response: AppLLMResponse, as type: T.Type) throws -> T {
        switch response {
        case .structured(let data):
            do {
                // Try to directly decode the JSON data
                return try JSONDecoder().decode(type, from: data)
            } catch {
                Logger.error("Failed to decode structured response: \(error.localizedDescription)")
                throw AppLLMError.decodingError("Failed to decode structured response: \(error.localizedDescription)")
            }
            
        case .text(let text):
            // For text responses, try to extract and parse JSON
            if let jsonData = text.data(using: .utf8) {
                do {
                    return try JSONDecoder().decode(type, from: jsonData)
                } catch {
                    Logger.error("Failed to parse JSON from text response: \(error.localizedDescription)")
                    throw AppLLMError.decodingError("Failed to parse JSON from text response: \(error.localizedDescription)")
                }
            } else {
                Logger.error("Unable to convert text response to data for JSON parsing")
                throw AppLLMError.decodingError("Unable to convert text response to data for JSON parsing")
            }
        }
    }
    
    /// Save a message to a debug file for troubleshooting
    /// - Parameters:
    ///   - message: The message to save
    ///   - fileName: The file name to use
    func saveMessageToDebugFile(_ message: String, fileName: String) {
        // Create a temporary URL for the debug file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try message.write(to: tempURL, atomically: true, encoding: .utf8)
            Logger.debug("Saved debug message to: \(tempURL.path)")
        } catch {
            Logger.error("Failed to save debug message: \(error.localizedDescription)")
        }
    }
    private func handleRevisionsContainerFormats(dataString: String) throws -> Any {
        Logger.debug("🔄 Attempting to parse RevisionsContainer from: \(String(dataString.prefix(100)))...")
        
        // Try to parse as a raw array of revisions
        if dataString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            let decoder = JSONDecoder()
            if let data = dataString.data(using: .utf8) {
                // Try to decode directly as array of ProposedRevisionNode
                if let revisionsArray = try? decoder.decode([ProposedRevisionNode].self, from: data) {
                    Logger.debug("✅ Parsed direct array format with \(revisionsArray.count) revisions")
                    return RevisionsContainer(revArray: revisionsArray)
                }
                
                // Alternative format with slightly different keys
                if let alternativeArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                    var nodes: [ProposedRevisionNode] = []
                    
                    for item in alternativeArray {
                        // Create node using the dictionary initializer
                        let node = ProposedRevisionNode(from: item)
                        nodes.append(node)
                    }
                    
                    if !nodes.isEmpty {
                        Logger.debug("✅ Mapped alternative array format with \(nodes.count) revisions")
                        return RevisionsContainer(revArray: nodes)
                    }
                }
            }
        }
        
        // Try to parse as revisions container directly
        let decoder = JSONDecoder()
        if let data = dataString.data(using: .utf8) {
            if let container = try? decoder.decode(RevisionsContainer.self, from: data) {
                Logger.debug("✅ Successfully parsed RevisionsContainer directly")
                return container
            }
        }
        
        // Try to parse with wrapper fields
        // Many models return structure like {"revisions": [...]} or {"rev_array": [...]}
        let possibleWrapperKeys = ["revArray", "RevArray", "revisions", "nodes", "revision_nodes", "changes"]
        
        for key in possibleWrapperKeys {
            // Try to find a wrapper object with the key
            if let wrapperData = extractJSONForKey(key, from: dataString),
               let data = wrapperData.data(using: .utf8),
               let revisions = try? JSONDecoder().decode([ProposedRevisionNode].self, from: data) {
                Logger.debug("✅ Extracted revisions using wrapper key: \(key)")
                return RevisionsContainer(revArray: revisions)
            }
        }
        
        // Try other common formats by normalizing the JSON
        let normalizedString = dataString
            .replacingOccurrences(of: "\"revArray\"", with: "\"revArray\"")
            .replacingOccurrences(of: "\"RevArray\"", with: "\"revArray\"")
            .replacingOccurrences(of: "\"value\"", with: "\"newValue\"")
            .replacingOccurrences(of: "\"explanation\"", with: "\"why\"")
            .replacingOccurrences(of: "\"original\"", with: "\"oldValue\"")
            .replacingOccurrences(of: "\"revision\"", with: "\"newValue\"")
            .replacingOccurrences(of: "\"reason\"", with: "\"why\"")

        // Try to parse the normalized string
        let normalizedDecoder = JSONDecoder()
        if let data = normalizedString.data(using: .utf8) {
            if let container = try? normalizedDecoder.decode(RevisionsContainer.self, from: data) {
                return container
            }
        }
        
        // If the model returned a response intended for another purpose, create an empty container
        // This happens with Claude which sometimes returns job recommendation JSON instead
        if dataString.contains("recommendedJobId") || dataString.contains("reason") {
            Logger.warning("⚠️ Model returned wrong response format. Creating empty revisions container.")
            return RevisionsContainer(revArray: [])
        }
        
        // If all attempts fail, throw an error
        throw AppLLMError.clientError("Failed to parse revision data in any supported format")
    }
    
    /// Extract JSON array for a specific key from a JSON string
    /// - Parameters:
    ///   - key: The key to extract
    ///   - jsonString: The JSON string
    /// - Returns: The extracted JSON array as a string, or nil if extraction fails
    private func extractJSONForKey(_ key: String, from jsonString: String) -> String? {
        do {
            if let data = jsonString.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                
                // Extract the array directly 
                if let array = json[key] as? [[String: String]] {
                    let arrayData = try JSONSerialization.data(withJSONObject: array)
                    return String(data: arrayData, encoding: .utf8)
                }
                
                // Fallback for more complex dictionaries
                if let array = json[key] as? [Any] {
                    let arrayData = try JSONSerialization.data(withJSONObject: array)
                    return String(data: arrayData, encoding: .utf8)
                }
            }
        } catch {
            Logger.error("x Failed to extract JSON for key \(key): \(error.localizedDescription)")
        }
        return nil
    }

    // Remaining methods stay the same...
}
