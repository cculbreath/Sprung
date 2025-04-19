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

    func startChat(
        parameters: ChatCompletionParameters
    ) async throws {
        do {
            let choices = try await service.startChat(parameters: parameters).choices
            messages = choices.compactMap(\.message.content).map { $0.asJsonFormatted() }
            assert(messages.count == 1)
            print(messages.last ?? "Nothin")

            lastRevNodeArray = convertJsonToNodes(messages.last) ?? []
            messageHist
                .append(
                    .init(role: .assistant, content: .text(choices.last?.message.content ?? ""))
                )
            errorMessage = choices.first?.message.refusal ?? ""
        } catch let APIError.responseUnsuccessful(description, statusCode) {
            self.errorMessage =
                "Network error with status code: \(statusCode) and description: \(description)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startStreamedChat(
        parameters: ChatCompletionParameters
    ) async throws {
        streamTask = Task {
            do {
                let stream = try await service.startStreamedChat(parameters: parameters)
                for try await result in stream {
                    let firstChoiceDelta = result.choices.first?.delta
                    let content = firstChoiceDelta?.refusal ?? firstChoiceDelta?.content ?? ""
                    self.message += content
                    if result.choices.first?.finishReason != nil {
                        self.message = self.message.asJsonFormatted()
                    }
                }
            } catch let APIError.responseUnsuccessful(description, statusCode) {
                self.errorMessage =
                    "Network error with status code: \(statusCode) and description: \(description)"
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
