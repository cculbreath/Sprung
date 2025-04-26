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
    /// - Returns: void - results are stored in the message property
    func startChat(messages: [ChatMessage]) async throws {
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
                            print("Sending structured output chat request to OpenAI with model: \(modelString)")
                            print("Request payload structure: \(chatMessages.count) messages, responseFormat: jsonSchema")

                            do {
                                let result = try await macPawClient.openAIClient.chats(query: query)
                                print("✅ Received response from OpenAI API")

                                if let resultJson = try? JSONEncoder().encode(result),
                                   let resultString = String(data: resultJson, encoding: .utf8)
                                {
                                    print("Raw API response: \(resultString)")
                                }
                            } catch {
                                print("❌❌❌ OpenAI API request failed with error: \(error)")
                                if let nsError = error as NSError? {
                                    print("Error domain: \(nsError.domain), code: \(nsError.code)")
                                    print("Error user info: \(nsError.userInfo)")
                                }
                                throw error
                            }

                            // Extract structured output response
                            // For MacPaw/OpenAI structured outputs, we need to check the content string
                            // since there's no structured output property directly accessible
                            print("Extracting content from response")

                            // We need to handle the result variable, which may be undefined in the outer scope
                            // if our nested try-catch block had an error
                            let apiResult: ChatResult
                            do {
                                // Re-get the result to ensure it's properly defined
                                apiResult = try await macPawClient.openAIClient.chats(query: query)
                                print("Response choice count: \(apiResult.choices.count)")
                            } catch {
                                print("❌ Failed to re-fetch API result: \(error)")
                                throw error
                            }

                            guard let choice = apiResult.choices.first else {
                                print("❌ No choices found in API response")
                                throw NSError(
                                    domain: "ResumeChatProviderError",
                                    code: 1002,
                                    userInfo: [NSLocalizedDescriptionKey: "No choices in API response"]
                                )
                            }

                            print("Message role: \(choice.message.role)")
                            if let content = choice.message.content {
                                print("Content length: \(content.count) characters")
                                print("Content first 100 chars: \(String(content.prefix(100)))")
                            } else {
                                print("❌ Content is nil")
                            }

                            guard let content = choice.message.content,
                                  !content.isEmpty
                            else {
                                print("❌ Content is empty or nil")
                                throw NSError(
                                    domain: "ResumeChatProviderError",
                                    code: 1002,
                                    userInfo: [NSLocalizedDescriptionKey: "Empty content in API response"]
                                )
                            }

                            guard let data = content.data(using: .utf8) else {
                                print("❌ Failed to convert content to data")
                                throw NSError(
                                    domain: "ResumeChatProviderError",
                                    code: 1002,
                                    userInfo: [NSLocalizedDescriptionKey: "Failed to get structured output content"]
                                )
                            }

                            // Decode the JSON content into RevisionsContainer
                            let structuredOutput: RevisionsContainer
                            do {
                                print("Decoding JSON data: \(String(data: data, encoding: .utf8) ?? "invalid data")")
                                structuredOutput = try JSONDecoder().decode(RevisionsContainer.self, from: data)
                                print("Successfully decoded structured output with \(structuredOutput.revArray.count) revision nodes")
                            } catch {
                                print("JSON decoding error: \(error.localizedDescription)")
                                throw NSError(
                                    domain: "ResumeChatProviderError",
                                    code: 1003,
                                    userInfo: [NSLocalizedDescriptionKey: "Failed to decode structured output: \(error.localizedDescription)"]
                                )
                            }

                            await coordinator.resumeWithValue(structuredOutput, continuation: continuation)
                        } catch {
                            print("API call error: \(error.localizedDescription)")
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
                            print("API call error: \(error.localizedDescription)")
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

    /// Send a chat completion request to the OpenAI API - patched version that handles null system_fingerprint
    /// - Parameter messages: The message history to use for context
    /// - Returns: void - results are stored in the message property
    func startChatPatched(messages: [ChatMessage]) async throws {
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

        do {
            // Check if we're using the MacPaw client
            if let macPawClient = openAIClient as? MacPawOpenAIClient {
                // Convert our messages to MacPaw's format
                let chatMessages = messages.compactMap { macPawClient.convertMessage($0) }

                // Create the query with structured output format
                let query = ChatQuery(
                    messages: chatMessages,
                    model: modelString,
                    responseFormat: .jsonObject,
                    temperature: 1.0
                )

                // Make direct HTTP request to bypass the system_fingerprint null issue
                let url = URL(string: "https://api.openai.com/v1/chat/completions")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(macPawClient.apiKey)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                // Encode the query
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                request.httpBody = try encoder.encode(query)

                print("Sending direct API request to OpenAI with model: \(modelString)")

                // Execute the request
                let (data, response) = try await URLSession.shared.data(for: request)

                // Log response for debugging
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP Status: \(httpResponse.statusCode)")
                    if httpResponse.statusCode >= 400 {
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        print("API Error: \(errorString)")
                        throw NSError(
                            domain: "ResumeChatProviderError",
                            code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: errorString]
                        )
                    }
                }

                // Extract just the content string from the response
                struct ChatChoiceContent: Decodable {
                    struct Choice: Decodable {
                        struct Message: Decodable {
                            let content: String?
                        }

                        let message: Message
                    }

                    let choices: [Choice]
                }

                // Decode with a simplified structure to avoid system_fingerprint
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase

                print("Decoding API response...")
                let contentResult = try decoder.decode(ChatChoiceContent.self, from: data)

                guard let content = contentResult.choices.first?.message.content,
                      !content.isEmpty
                else {
                    throw NSError(
                        domain: "ResumeChatProviderError",
                        code: 1002,
                        userInfo: [NSLocalizedDescriptionKey: "No content in API response"]
                    )
                }

                print("Content extracted successfully, length: \(content.count)")
                print("Content first 100 chars: \(String(content.prefix(100)))")

                // Parse the JSON content to extract the RevNode array
                if let responseData = content.data(using: .utf8) {
                    do {
                        print("Parsing JSON content to RevNode array...")

                        // First try to parse with a custom decoder that maps different key cases
                        // Define a custom case-insensitive structure to handle different key cases
                        struct CaseInsensitiveRevisionsContainer: Decodable {
                            let revArray: [ProposedRevisionNode]

                            enum CodingKeys: String, CodingKey {
                                case revArray
                                case RevArray // Uppercase variant
                            }

                            init(from decoder: Decoder) throws {
                                let container = try decoder.container(keyedBy: CodingKeys.self)

                                // Try with lowercase first, then uppercase
                                if container.contains(.revArray) {
                                    revArray = try container.decode([ProposedRevisionNode].self, forKey: .revArray)
                                } else if container.contains(.RevArray) {
                                    revArray = try container.decode([ProposedRevisionNode].self, forKey: .RevArray)
                                } else {
                                    revArray = [] // Empty array as fallback
                                }
                            }
                        }

                        // Try to decode with the case-insensitive container
                        let caseInsensitiveDecoder = JSONDecoder()
                        let caseInsensitiveContainer = try caseInsensitiveDecoder.decode(CaseInsensitiveRevisionsContainer.self, from: responseData)

                        // Create a standard RevisionsContainer from our case-insensitive version
                        let revContainer = RevisionsContainer(revArray: caseInsensitiveContainer.revArray)

                        print("Successfully decoded JSON with \(revContainer.revArray.count) revision nodes")

                        // Convert to JSON string for compatibility with existing code
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        let jsonData = try encoder.encode(revContainer)
                        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"revArray\": []}"

                        // Store the JSON string in messages array
                        self.messages = [jsonString]

                        // Get the revision nodes directly
                        lastRevNodeArray = revContainer.revArray

                        // Update generic messages for history
                        genericMessages.append(ChatMessage(role: .assistant, content: jsonString))
                    } catch {
                        print("JSON parsing error: \(error.localizedDescription)")
                        print("Raw content: \(content)")

                        // Fallback: Try manual JSON parsing if structured decoding fails
                        do {
                            // Try to parse as a dictionary first
                            if let jsonObj = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                                print("Attempting manual JSON parsing...")

                                // Look for RevArray or revArray
                                let revArrayData: [[String: Any]]
                                if let upperArray = jsonObj["RevArray"] as? [[String: Any]] {
                                    revArrayData = upperArray
                                    print("Found 'RevArray' key (uppercase) with \(upperArray.count) elements")
                                } else if let lowerArray = jsonObj["revArray"] as? [[String: Any]] {
                                    revArrayData = lowerArray
                                    print("Found 'revArray' key (lowercase) with \(lowerArray.count) elements")
                                } else {
                                    print("Neither 'RevArray' nor 'revArray' keys found in JSON")
                                    throw NSError(domain: "JSONParsingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find revArray in JSON"])
                                }

                                // Manually convert each dictionary to a ProposedRevisionNode
                                var nodes: [ProposedRevisionNode] = []
                                for item in revArrayData {
                                    let node = ProposedRevisionNode(
                                        id: item["id"] as? String ?? "",
                                        oldValue: item["oldValue"] as? String ?? "",
                                        newValue: item["newValue"] as? String ?? "",
                                        valueChanged: item["valueChanged"] as? Bool ?? false,
                                        isTitleNode: item["isTitleNode"] as? Bool ?? false,
                                        why: item["why"] as? String ?? ""
                                    )
                                    nodes.append(node)
                                }

                                // Create a RevisionsContainer from our manually parsed nodes
                                let revContainer = RevisionsContainer(revArray: nodes)
                                print("Successfully manually parsed JSON with \(revContainer.revArray.count) revision nodes")

                                // Convert to JSON string for compatibility with existing code
                                let encoder = JSONEncoder()
                                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                                let jsonData = try encoder.encode(revContainer)
                                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"revArray\": []}"

                                // Store the JSON string in messages array
                                self.messages = [jsonString]

                                // Get the revision nodes directly
                                lastRevNodeArray = revContainer.revArray

                                // Update generic messages for history
                                genericMessages.append(ChatMessage(role: .assistant, content: jsonString))

                                // Success! Return early
                                return
                            }
                        } catch {
                            print("Manual JSON parsing also failed: \(error.localizedDescription)")
                        }

                        // If we got here, both structured and manual parsing failed
                        throw error
                    }
                } else {
                    throw NSError(
                        domain: "ResumeChatProviderError",
                        code: 1003,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to convert content to data"]
                    )
                }
            } else {
                // Fallback to the old method for non-MacPaw clients
                let response = try await openAIClient.sendChatCompletionAsync(
                    messages: messages,
                    model: modelString,
                    temperature: 1.0
                )

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

                // Update generic messages
                genericMessages.append(ChatMessage(role: .assistant, content: content))
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
        try await startChatPatched(messages: messages)
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
