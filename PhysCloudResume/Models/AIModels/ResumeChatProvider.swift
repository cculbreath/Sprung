//
//  ResumeChatProvider.swift
//  SwiftOpenAIExample
//
//  Created by James Rochabrun on 8/10/24.
//

import Foundation
import SwiftOpenAI

/// Helper to fetch available OpenAI models and convert model IDs to SwiftOpenAI Model enum

@Observable
final class ResumeChatProvider {
    private let service: OpenAIService
    private var streamTask: Task<Void, Never>?
    var message: String = ""
    var messages: [String] = []
    var messageHist: [ChatCompletionParameters.Message] = []
    var errorMessage: String = ""
    var lastRevNodeArray: [ProposedRevisionNode] = []

    // MARK: - Initializer

    init(service: OpenAIService) {
        self.service = service
    }

    private func convertJsonToNodes(_ jsonString: String?) -> [ProposedRevisionNode]? {
        guard let jsonString = jsonString, let jsonData = jsonString.data(using: .utf8) else {
            print("Error converting string to data")
            return nil
        }

        do {
            // Decode the JSON data into RevisionsContainer
            let revisionsContainer = try JSONDecoder().decode(RevisionsContainer.self, from: jsonData)

            // Return the array of ProposedRevisionNode
            return revisionsContainer.revArray
        } catch {
            print("Failed to decode JSON: \(error)")
            return nil
        }
    }

    // MARK: - Public Methods

    func unloadResponse() -> [ProposedRevisionNode]? {
        if let nodes = convertJsonToNodes(messages[0]) {
            messages.removeFirst()
            print("Nodes processed from JSON response:")
            for node in nodes {
                print("Node ID: \(node.id), isTitleNode: \(node.isTitleNode), oldValue: \(node.oldValue.prefix(20))...")
            }
            lastRevNodeArray = nodes
            return nodes
        } else {
            print("❌ ERROR: Failed to convert JSON response to nodes")
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

    func startChat(
        parameters: ChatCompletionParameters
    ) async throws {
        // Clear previous error message before starting
        errorMessage = ""

        do {
            // Create a coordinator for safe continuation resumption
            let coordinator = ContinuationCoordinator()

            // Start a task with specific timeout for the API call
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ChatCompletionObject, Error>) in
                let timeoutError = NSError(
                    domain: "ResumeChatProviderError",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "API request timed out. Please try again."]
                )

                let apiTask = Task {
                    do {
                        let result = try await service.startChat(parameters: parameters)
                        await coordinator.resumeWithValue(result, continuation: continuation)
                    } catch {
                        await coordinator.resumeWithError(error, continuation: continuation)
                    }
                }

                // Set up a timeout task
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000_000) // 500s timeout (a bit less than the URLSession timeout)
                    if !apiTask.isCancelled {
                        apiTask.cancel()
                        await coordinator.resumeWithError(timeoutError, continuation: continuation)
                    }
                }
            }

            // Safely unwrap choices
            let unwrappedChoices = result.choices ?? []

            // Process messages from choices
            messages = unwrappedChoices.compactMap { choice -> String? in
                // Safely access message
                guard let messageObj = choice.message else { return nil }
                // Safely access content
                guard let contentStr = messageObj.content else { return nil }
                return contentStr.asJsonFormatted()
            }

            if messages.isEmpty {
                throw NSError(
                    domain: "ResumeChatProviderError",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "No response content received from AI service."]
                )
            }

            print("AI response received: \(messages.last?.prefix(100) ?? "Empty")")

            lastRevNodeArray = convertJsonToNodes(messages.last) ?? []
            // Get the last message content safely
            let lastContent: String = {
                guard let lastChoice = unwrappedChoices.last else { return "" }
                guard let lastMessage = lastChoice.message else { return "" }
                return lastMessage.content ?? ""
            }()

            messageHist.append(
                .init(role: .assistant, content: .text(lastContent))
            )

            // Check for refusal
            if let firstChoice = unwrappedChoices.first,
               let firstMessage = firstChoice.message,
               let refusal = firstMessage.refusal,
               !refusal.isEmpty
            {
                errorMessage = refusal
                throw NSError(
                    domain: "OpenAIRefusalError",
                    code: 1003,
                    userInfo: [NSLocalizedDescriptionKey: "AI refused to complete the request: \(refusal)"]
                )
            }
        } catch let APIError.responseUnsuccessful(description, statusCode) {
            self.errorMessage = "Network error with status code: \(statusCode) and description: \(description)"
            throw NSError(
                domain: "OpenAINetworkError",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func startStreamedChat(
        parameters: ChatCompletionParameters
    ) async throws {
        // Clear any previous error message
        errorMessage = ""

        // Create and store a new task for streaming
        streamTask = Task {
            do {
                // Create a coordinator for the timeout
                let coordinator = ContinuationCoordinator()

                // Use withTimeout pattern similar to startChat
                let stream = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AsyncThrowingStream<ChatCompletionChunkObject, Error>, Error>) in

                    // Create timeout error
                    let timeoutError = NSError(
                        domain: "ResumeChatProviderError",
                        code: -1001,
                        userInfo: [NSLocalizedDescriptionKey: "Streaming request timed out. Please try again."]
                    )

                    // Main API task
                    Task {
                        do {
                            let stream = try await service.startStreamedChat(parameters: parameters)
                            await coordinator.resumeWithValue(stream, continuation: continuation)
                        } catch {
                            await coordinator.resumeWithError(error, continuation: continuation)
                        }
                    }

                    // Timeout task
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000_000) // 500s timeout
                        await coordinator.resumeWithError(timeoutError, continuation: continuation)
                    }
                }

                // Process the stream
                for try await result in stream {
                    // Safely process each chunk
                    let choices = result.choices ?? []

                    if !choices.isEmpty {
                        let firstChoice = choices[0]

                        if let deltaObj = firstChoice.delta {
                            // Extract content or refusal from delta
                            let contentToAdd = deltaObj.refusal ?? deltaObj.content ?? ""
                            self.message += contentToAdd

                            if firstChoice.finishReason != nil {
                                self.message = self.message.asJsonFormatted()
                            }
                        }
                    }
                }
            } catch let APIError.responseUnsuccessful(description, statusCode) {
                self.errorMessage = "Network error with status code: \(statusCode) and description: \(description)"
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
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
        } catch {
            print("Error formatting JSON: \(error)")
        }
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
