//
//  ResumeChatProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import Foundation
import OpenAI
import SwiftUI

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

    func unloadResponse() -> [ProposedRevisionNode]? {
        if let nodes = convertJsonToNodes(messages[0]) {
            messages.removeFirst()
            for node in nodes {}
            lastRevNodeArray = nodes
            return nodes
        } else {
            return nil
        }
    }

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
    func startChat(messages: [ChatMessage], resume: Resume? = nil) async throws {
        // Check if we should use the new Responses API implementation
        if isResponsesAPIEnabled() {
            try await startChatWithResponsesAPI(messages: messages, resume: resume)
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

    /// Sends a request to the OpenAI Responses API
    /// - Parameters:
    ///   - messages: The message history for context
    ///   - resume: The resume to update with the response ID
    /// - Returns: void - results are stored in properties
    func startChatWithResponsesAPI(messages: [ChatMessage], resume: Resume?) async throws {
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

        // Extract the system and user messages
        var systemMessage = ""
        var userMessage = ""

        for message in messages {
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
                break
            }
        }

        // Combine for the final message
        let combinedMessage = """
        System context:
        \(systemMessage)

        User message:
        \(userMessage)
        """

        // Determine if this is a new conversation or continuation
        let previousResponseId = resume?.previousResponseId
        let isNewConversation = previousResponseId == nil

        print("Starting \(isNewConversation ? "new" : "continuation") conversation with Responses API")
        if !isNewConversation {
            print("Using previous response ID: \(previousResponseId ?? "nil")")
        }

        do {
            // Call the Responses API
            let response = try await openAIClient.sendResponseRequestAsync(
                message: combinedMessage,
                model: modelString,
                temperature: 1.0,
                previousResponseId: previousResponseId
            )

            print("✅ Received response from OpenAI Responses API with ID: \(response.id)")

            // Store the response ID in the resume if provided
            if let resume = resume {
                resume.previousResponseId = response.id
            }

            // Process the response content
            let content = response.content

            // Parse the JSON content to extract the RevNode array
            if let responseData = content.data(using: .utf8) {
                do {
                    print("Parsing JSON content to RevNode array...")

                    // Try first as a direct array (Responses API format)
                    if let jsonArray = try? JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] {
                        print("Detected direct JSON array format")

                        var nodes: [ProposedRevisionNode] = []
                        for item in jsonArray {
                            // Get the node properties with appropriate fallbacks
                            let nodeId = item["id"] as? String ?? ""
                            let treePath = item["tree_path"] as? String ?? ""
                            let oldValue = item["oldValue"] as? String ?? ""
                            
                            let node = ProposedRevisionNode(
                                id: nodeId,
                                oldValue: oldValue,
                                newValue: item["newValue"] as? String ?? "",
                                valueChanged: item["valueChanged"] as? Bool ?? false,
                                isTitleNode: item["isTitleNode"] as? Bool ?? false,
                                why: item["why"] as? String ?? "",
                                treePath: treePath
                            )
                            nodes.append(node)
                        }

                        // Create a container with our nodes
                        let revContainer = RevisionsContainer(revArray: nodes)
                        print("Successfully parsed JSON array with \(nodes.count) revision nodes")

                        // Format for storage
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        let jsonData = try encoder.encode(revContainer)
                        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"revArray\": []}"

                        // Store results
                        self.messages = [jsonString]
                        lastRevNodeArray = revContainer.revArray
                        genericMessages.append(ChatMessage(role: .assistant, content: jsonString))
                        return
                    }

                    // Try as a container with revArray property (legacy format)
                    let container = try JSONDecoder().decode(RevisionsContainer.self, from: responseData)
                    print("Successfully decoded JSON with container format: \(container.revArray.count) revision nodes")

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
                    print("JSON parsing error: \(error.localizedDescription)")
                    print("Raw content: \(content)")
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

    /// Send a streaming chat completion request
    /// - Parameter messages: The message history to use for context
    func startStreamingChat(messages: [ChatMessage]) async throws {
        // Clear any previous error message
        errorMessage = ""

        // Fall back to non-streaming version with our abstraction layer
        try await startChat(messages: messages)
    }

    func cancelStream() {
        streamTask?.cancel()
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
