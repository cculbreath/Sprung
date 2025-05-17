//
//  ResumeChatProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI
import OpenAI

/// Helper for handling resume chat functionality

@Observable
final class ResumeChatProvider {
    // The OpenAI client that will be used for API calls
    private let openAIClient: OpenAIClientProtocol

    private var streamTask: Task<Void, Never>?
    var message: String = ""
    var messages: [String] = []
    // Generic message format for the abstraction layer
    var genericMessages: [ChatMessage] = []
    var errorMessage: String = ""
    var lastRevNodeArray: [ProposedRevisionNode] = []
    
    // Track the last model used to know when to switch clients
    var lastModelUsed: String = ""

    // MARK: - Initializers

    /// Initialize with the new abstraction layer client
    /// - Parameter client: An OpenAI client conforming to OpenAIClientProtocol
    init(client: OpenAIClientProtocol) {
        openAIClient = client
    }

    private func convertJsonToNodes(_ jsonString: String?) -> [ProposedRevisionNode]? {
        guard let jsonString = jsonString, let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            // Decode the JSON data into RevisionsContainer
            let revisionsContainer = try JSONDecoder().decode(RevisionsContainer.self, from: jsonData)

            // Return the array of ProposedRevisionNode
            return revisionsContainer.revArray
        } catch {
            return nil
        }
    }

    // MARK: - Public Methods



    // Actor to safely coordinate continuations and prevent multiple resumes
    private actor ContinuationCoordinator {
        private var hasResumed = false

        func resumeWithValue<T, E: Error>(_ value: T, continuation: CheckedContinuation<T, E>) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(returning: value)
        }

        func resumeWithError<T, E: Error>(_ error: E, continuation: CheckedContinuation<T, E>) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(throwing: error)
        }
    }

    /// Send a chat completion request to the OpenAI API
    /// - Parameter messages: The message history to use for context
    /// - Parameter resume: Optional resume to update with response ID for server-side conversation state
    /// - Returns: void - results are stored in the message property
    func startChat(messages: [ChatMessage],
                   resume: Resume? = nil,
                   continueConversation: Bool = false) async throws
    {
        // Check if we should use the new Responses API implementation
        if isResponsesAPIEnabled() {
            try await startChatWithResponsesAPI(messages: messages,
                                                resume: resume,
                                                continueConversation: continueConversation)
            return
        }
        // Clear previous error message before starting
        errorMessage = ""

        // Store for reference
        genericMessages = messages

        // Get model as string
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        // Use our abstraction layer with a timeout
        let timeoutError = NSError(
            domain: "ResumeChatProviderError",
            code: -1001,
            userInfo: [NSLocalizedDescriptionKey: "API request timed out. Please try again."]
        )

        // Create a coordinator for safe continuation resumption
        let coordinator = ContinuationCoordinator()

        do {
            // Check if we're using the MacPaw client
            if let macPawClient = openAIClient as? MacPawOpenAIClient {
                // Start a task with specific timeout for the API call
                let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RevisionsContainer, Error>) in
                    let apiTask = Task {
                        do {
                            // Convert our messages to MacPaw's format
                            let chatMessages = messages.compactMap { macPawClient.convertMessage($0) }

                            // Create the query with structured output format
                            let query = ChatQuery(
                                messages: chatMessages,
                                model: modelString,
                                responseFormat: .jsonSchema(name: "resume-revisions", type: RevisionsContainer.self),
                                temperature: 1.0
                            )

                            // Make the API call with structured output
                            let result = try await macPawClient.openAIClient.chats(query: query)

                            // Extract structured output response
                            // For MacPaw/OpenAI structured outputs, we need to check the content string
                            // since there's no structured output property directly accessible
                            guard let content = result.choices.first?.message.content,
                                  let data = content.data(using: .utf8)
                            else {
                                throw NSError(
                                    domain: "ResumeChatProviderError",
                                    code: 1002,
                                    userInfo: [NSLocalizedDescriptionKey: "Failed to get structured output content"]
                                )
                            }

                            // Decode the JSON content into RevisionsContainer
                            let structuredOutput: RevisionsContainer
                            do {
                                structuredOutput = try JSONDecoder().decode(RevisionsContainer.self, from: data)
                            } catch {
                                throw NSError(
                                    domain: "ResumeChatProviderError",
                                    code: 1003,
                                    userInfo: [NSLocalizedDescriptionKey: "Failed to decode structured output: \(error.localizedDescription)"]
                                )
                            }

                            await coordinator.resumeWithValue(structuredOutput, continuation: continuation)
                        } catch {
                            await coordinator.resumeWithError(error, continuation: continuation)
                        }
                    }

                    // Set up a timeout task
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000_000) // 500s timeout
                        if !apiTask.isCancelled {
                            apiTask.cancel()
                            await coordinator.resumeWithError(timeoutError, continuation: continuation)
                        }
                    }
                }

                // Convert structured response to JSON for compatibility with existing code
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(response)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"revArray\": []}"

                // Store the JSON string in messages array
                self.messages = [jsonString]

                if self.messages.isEmpty {
                    throw NSError(
                        domain: "ResumeChatProviderError",
                        code: 1002,
                        userInfo: [NSLocalizedDescriptionKey: "No response content received from AI service."]
                    )
                }

                // Get the revision nodes directly from the structured response
                lastRevNodeArray = response.revArray

                // Update generic messages for history
                genericMessages.append(ChatMessage(role: .assistant, content: jsonString))
            } else {
                // Fallback to the old method for non-MacPaw clients
                let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ChatCompletionResponse, Error>) in
                    let apiTask = Task {
                        do {
                            let result = try await openAIClient.sendChatCompletionAsync(
                                messages: messages,
                                model: modelString,
                                temperature: 1.0 // Using standard temperature of 1.0 as requested
                            )
                            await coordinator.resumeWithValue(result, continuation: continuation)
                        } catch {
                            await coordinator.resumeWithError(error, continuation: continuation)
                        }
                    }

                    // Set up a timeout task
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000_000) // 500s timeout
                        if !apiTask.isCancelled {
                            apiTask.cancel()
                            await coordinator.resumeWithError(timeoutError, continuation: continuation)
                        }
                    }
                }

                // Process the response
                let content = response.content

                // Process messages format and store in messages array
                self.messages = [content.asJsonFormatted()]

                if self.messages.isEmpty {
                    throw NSError(
                        domain: "ResumeChatProviderError",
                        code: 1002,
                        userInfo: [NSLocalizedDescriptionKey: "No response content received from AI service."]
                    )
                }

                // Try to convert to nodes
                lastRevNodeArray = convertJsonToNodes(self.messages.last) ?? []

                // Add to message history
                let lastContent = content

                // Update generic messages
                genericMessages.append(ChatMessage(role: .assistant, content: lastContent))
            }

        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Check if the Responses API should be used
    /// - Returns: True if the Responses API should be used
    private func isResponsesAPIEnabled() -> Bool {
        // We can add a feature flag here in the future
        // For now, always return true to use the new API
        return true
    }

    /// Helper method to save message content to debug file
    private func saveMessageToDebugFile(_ content: String, fileName: String) {
        // Check if debug prompt saving is enabled
        let saveDebugPrompts = UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        
        // Only save if debug is enabled
        if saveDebugPrompts {
            let fileManager = FileManager.default
            let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
            let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
            let fileURL = downloadsURL.appendingPathComponent(fileName)
            
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                Logger.debug("Debug message content saved to: \(fileURL.path)")
            } catch {
                Logger.debug("Error saving debug message: \(error.localizedDescription)")
            }
        } else {
            // Log that we would have saved a debug file, but it's disabled
            Logger.debug("Debug message NOT saved (saveDebugPrompts disabled)")
        }
    }
    
    /// Sends a request to the OpenAI Responses API
    /// - Parameters:
    ///   - messages: The message history for context
    ///   - resume: The resume to update with the response ID
    /// - Returns: void - results are stored in properties
    func startChatWithResponsesAPI(messages: [ChatMessage],
                                   resume: Resume?,
                                   continueConversation: Bool) async throws
    {
        // Clear previous error message before starting
        errorMessage = ""

        // Store for reference
        genericMessages = messages

        // Get model as string
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        // Extract the system and user messages
        var systemMessage = ""
        var userMessage = ""

        // For debug: capture updatableFields JSON from the resume if provided
        if let resume = resume, let root = resume.rootNode {
            let fieldsArr = TreeNode.traverseAndExportNodes(node: root)
            if let data = try? JSONSerialization.data(withJSONObject: fieldsArr, options: .prettyPrinted),
               let jsonString = String(data: data, encoding: .utf8)
            {
                Logger.debug("▶️ JSON sent to LLM (updatableFields):")
                Logger.debug(jsonString)
            }
            // Do *not* wipe previousResponseId here; it is needed for
            // follow-up revision calls.
        }
        
        // Check for empty messages array - this is a critical error
        var workingMessages = messages // Create a mutable copy
        if workingMessages.isEmpty {
            Logger.debug("❌ CRITICAL ERROR: Empty messages array received in startChatWithResponsesAPI!")
            
            // If we have a resume, try to generate a fallback prompt
            if resume != nil {
                // Create a basic fallback prompt that just asks for improvement of the resume
                let fallbackPrompt = """
                Please help improve this resume for a job application. Propose changes that would make it more effective.
                
                Generate your response in the required JSON format with the RevNode array schema.
                """
                
                // Add a generic system message and the fallback user prompt
                workingMessages = [
                    ChatMessage(role: .system, content: "You are a helpful assistant specializing in resume improvements."),
                    ChatMessage(role: .user, content: fallbackPrompt)
                ]
                
                // Update genericMessages for future reference
                genericMessages = workingMessages
                
                Logger.debug("⚠️ Created emergency fallback prompt due to empty messages array")
            } else {
                throw NSError(domain: "ResumeChatProviderError", code: 1005, 
                    userInfo: [NSLocalizedDescriptionKey: "Empty messages array and no resume to generate fallback"])
            }
        }
        
        // Debug log for messages being processed
        Logger.debug("Processing \(workingMessages.count) messages for chat request")
        for (index, message) in workingMessages.enumerated() {
            Logger.debug("Message \(index): Role=\(message.role), Content length=\(message.content.count) chars")
            
            // Now process the message normally
            switch message.role {
            case .system:
                if !systemMessage.isEmpty {
                    systemMessage += "\n\n"
                }
                systemMessage += message.content
            case .user:
                if !userMessage.isEmpty {
                    userMessage += "\n\n"
                }
                userMessage += message.content
            default:
                Logger.debug("Skipping message with role: \(message.role)")
                break
            }
        }
        
        // Debug log the extracted content
        Logger.debug("Final system message length: \(systemMessage.count) chars")
        Logger.debug("Final user message length: \(userMessage.count) chars")

        // Combine for the final message
        var combinedMessage = ""
        
        // Only include system context if there is actual content
        if !systemMessage.isEmpty {
            combinedMessage += """
            System context:
            \(systemMessage)
            
            """
        }
        
        // Only include user message if there is actual content
        if !userMessage.isEmpty {
            combinedMessage += """
            User message:
            \(userMessage)
            """
        } else {
            // If there's no user message, add a placeholder to avoid empty requests
            Logger.debug("⚠️ Warning: Empty user message in chat request")
        }
        
        // Ensure we have at least some content
        if combinedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Logger.debug("⚠️ Error: Empty combined message in chat request")
            
            // Create a fallback prompt if both system and user messages are empty
            if let resume = resume, let root = resume.rootNode {
                // Extract some node values to include in the fallback
                let nodes = TreeNode.traverseAndExportNodes(node: root)
                let nodeStrings = nodes.prefix(5).compactMap { node -> String? in
                    if let value = node["value"] as? String, !value.isEmpty {
                        return value
                    }
                    return nil
                }
                
                let nodeContent = nodeStrings.joined(separator: "\n- ")
                
                combinedMessage = """
                Please help improve this resume. I need suggestions for the following sections:
                
                - \(nodeContent)
                
                Respond with a JSON array of revision nodes following the schema I provided.
                """
                
                Logger.debug("✅ Created emergency fallback message from resume nodes")
            } else {
                // Use the raw messages as a last resort
                combinedMessage = workingMessages.map { "[\($0.role)]: \($0.content)" }.joined(separator: "\n\n")
                
                if combinedMessage.isEmpty {
                    // If even that's empty, use a completely generic message
                    combinedMessage = "Please suggest improvements for this resume. Respond with a JSON array following the schema format."
                }
            }
        }
        
        // Save the final combined message to a debug file for analysis
        saveMessageToDebugFile(combinedMessage, fileName: "resume_chat_debug.txt")

        // Decide whether to continue a previous conversation
        let previousResponseId: String? = continueConversation ? resume?.previousResponseId : nil
        let isNewConversation = previousResponseId == nil

        Logger.debug("Starting \(isNewConversation ? "new" : "continuation") conversation with Responses API")
        if !isNewConversation {
            Logger.debug("Using previous response ID: \(previousResponseId ?? "nil")")
        } else {
            Logger.debug("Starting fresh conversation with no previous context")
        }

        do {
            // Get the JSON schema for revisions
            let schema = ResumeApiQuery.revNodeArraySchemaString

            // Call the Responses API with structured output schema
            let response = try await openAIClient.sendResponseRequestAsync(
                message: combinedMessage,
                model: modelString,
                temperature: 1.0,
                previousResponseId: previousResponseId,
                schema: schema
            )

            Logger.debug("✅ Received response from OpenAI Responses API with ID: \(response.id)")

            // Debug: print the raw JSON returned from the LLM for troubleshooting
            Logger.debug("🛬 JSON returned from LLM:")
            Logger.debug(response.content)

            // Store the response ID in the resume if provided
            if let resume = resume {
                resume.previousResponseId = response.id
            }

            // Process the response content
            let content = response.content

            // Parse the JSON content to extract the RevNode array
            if let responseData = content.data(using: .utf8) {
                do {
                    Logger.debug("Parsing JSON content to RevNode array...")

                    // Try as a container with revArray property (legacy format)
                    let container = try JSONDecoder().decode(RevisionsContainer.self, from: responseData)
                    Logger.debug("Successfully decoded JSON with container format: \(container.revArray.count) revision nodes")

                    // Format for storage
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let jsonData = try encoder.encode(container)
                    let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"revArray\": []}"

                    // Store results
                    self.messages = [jsonString]
                    lastRevNodeArray = container.revArray
                    genericMessages.append(ChatMessage(role: .assistant, content: jsonString))

                } catch {
                    Logger.debug("JSON parsing error: \(error.localizedDescription)")
                    Logger.debug("Raw content: \(content)")
                    throw error
                }
            } else {
                throw NSError(
                    domain: "ResumeChatProviderError",
                    code: 1003,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to convert content to data"]
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }


}

/// Helper that allows to display the JSON Schema.
extension String {
    func asJsonFormatted() -> String {
        guard let data = data(using: .utf8) else { return self }
        do {
            // Parse JSON string to Any object
            if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                // Traverse and strip quotes from string values
                let cleanedObject = stripQuotes(from: jsonObject)

                // Convert back to data with pretty-printing
                let prettyPrintedData = try JSONSerialization.data(
                    withJSONObject: cleanedObject, options: [.prettyPrinted, .sortedKeys]
                )

                // Convert formatted data back to string
                return String(data: prettyPrintedData, encoding: .utf8) ?? self
            }
        } catch {}
        return self
    }

    // Recursive function to traverse and strip quotes from string values in a dictionary
    private func stripQuotes(from dictionary: [String: Any]) -> [String: Any] {
        var newDict = dictionary
        for (key, value) in dictionary {
            if let stringValue = value as? String {
                // Strip quotes from the string value
                newDict[key] = stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } else if let nestedDict = value as? [String: Any] {
                // Recursively strip quotes in nested dictionaries
                newDict[key] = stripQuotes(from: nestedDict)
            } else if let arrayValue = value as? [Any] {
                // Recursively process arrays
                newDict[key] = stripQuotes(from: arrayValue)
            }
        }
        return newDict
    }

    // Recursive function to traverse and strip quotes from string values in an array
    private func stripQuotes(from array: [Any]) -> [Any] {
        return array.map { value in
            if let stringValue = value as? String {
                return stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } else if let nestedDict = value as? [String: Any] {
                return stripQuotes(from: nestedDict)
            } else if let nestedArray = value as? [Any] {
                return stripQuotes(from: nestedArray)
            } else {
                return value
            }
        }
    }
}
