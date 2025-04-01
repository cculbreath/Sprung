//
//  ChatProvider.swift
//  SwiftOpenAIExample
//
//  Created by James Rochabrun on 8/10/24.
//

import Foundation
import SwiftOpenAI

/// Helper to fetch available OpenAI models and convert model IDs to SwiftOpenAI Model enum
class OpenAIModelFetcher {
    /// Get the configured preferred model from UserDefaults
    static func getPreferredModel() -> Model {
        let modelString = UserDefaults.standard.string(forKey: "preferredOpenAIModel") ?? "gpt-4o-2024-08-06"
        let model = modelFromString(modelString)
        print("Retrieved preferred model: \(modelString) → \(model)")
        return model
    }
    static func fetchAvailableModels(apiKey: String) async -> [String] {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Error fetching models: invalid response")
                return []
            }
            
            struct ModelResponse: Codable {
                struct Model: Codable {
                    let id: String
                }
                let data: [Model]
            }
            
            let modelResponse = try JSONDecoder().decode(ModelResponse.self, from: data)
            let chatModels = modelResponse.data
                .map { $0.id }
                .filter { $0.contains("gpt") || $0.contains("o1") || $0.contains("o3") } 
                .sorted()
            
            return chatModels
        } catch {
            print("Error fetching models: \(error)")
            return []
        }
    }
    
    /// Convert a model string to the corresponding SwiftOpenAI Model enum
    static func modelFromString(_ modelString: String) -> Model {
        // The mapping is based on the difference between OpenAI's API model names
        // and SwiftOpenAI's enum case names
        
        // Handle based on model name patterns
        switch modelString {
        // GPT-4o models
        case "gpt-4o-2024-08-06", "gpt-4o-2024-08-6", "gpt4o20240806":
            return .gpt4o20240806
        case "gpt-4o-2024-11-20", "gpt4o20241120":
            return .gpt4o20241120
        case "gpt-4o-2024-05-13", "gpt4o20240513":
            return .gpt4o20240513
        case "gpt-4o", "gpt4o":
            return .gpt4o
            
        // GPT-4 Turbo models
        case "gpt-4-turbo-2024-04-09", "gpt4turbo20240409":
            return .custom("gpt-4-turbo-2024-04-09")
        case "gpt-4-turbo-preview", "gpt4turbopreview":
            return .custom("gpt-4-turbo-preview")
        case "gpt-4-turbo", "gpt4turbo":
            return .gpt4turbo
            
        // GPT-4 models
        case "gpt-4-0125-preview", "gpt40125preview":
            return .custom("gpt-4-0125-preview")
        case "gpt-4-1106-preview", "gpt41106preview":
            return .custom("gpt-4-1106-preview")
        case "gpt-4-0613", "gpt40613":
            return .custom("gpt-4-0613")
        case "gpt-4", "gpt4":
            return .gpt4
            
        // GPT-3.5 Turbo models
        case "gpt-3.5-turbo-0125", "gpt35turbo0125":
            return .custom("gpt-3.5-turbo-0125")
        case "gpt-3.5-turbo-1106", "gpt35turbo1106":
            return .custom("gpt-3.5-turbo-1106")
        case "gpt-3.5-turbo-instruct", "gpt35turboinstruct":
            return .custom("gpt-3.5-turbo-instruct")
        case "gpt-3.5-turbo-16k", "gpt35turbo16k":
            return .custom("gpt-3.5-turbo-16k")
        case "gpt-3.5-turbo", "gpt35turbo":
            return .custom("gpt-3.5-turbo")
            
        // O1 series
        case "o1-mini-2024-09-12", "o1mini20240912":
            return .custom("o1-mini-2024-09-12")
        case "o1-mini", "o1mini":
            return .custom("o1-mini")
        case "o1-preview-2024-09-12", "o1preview20240912":
            return .custom("o1-preview-2024-09-12")
        case "o1-preview", "o1preview": 
            return .custom("o1-preview")
        case "o1-2024-12-17", "o120241217":
            return .custom("o1-2024-12-17")
        case "o1":
            return .custom("o1")
            
        // O3 series
        case "o3-mini-2025-01-31", "o3mini20250131":
            return .custom("o3-mini-2025-01-31")
        case "o3-mini", "o3mini":
            return .custom("o3-mini")
            
        // GPT-4o mini models
        case "gpt-4o-mini-2024-07-18", "gpt4omini20240718":
            return .custom("gpt-4o-mini-2024-07-18")
        case "gpt-4o-mini", "gpt4omini":
            return .gpt4omini
            
        // Real-time and audio models
        case "gpt-4o-realtime-preview-2024-12-17", "gpt4orealtimepreview20241217":
            return .custom("gpt-4o-realtime-preview-2024-12-17")
        case "gpt-4o-realtime-preview", "gpt4orealtimepreview":
            return .custom("gpt-4o-realtime-preview")
        case "gpt-4o-realtime-preview-2024-10-01", "gpt4orealtimepreview20241001":
            return .custom("gpt-4o-realtime-preview-2024-10-01")
        case "gpt-4o-audio-preview-2024-12-17", "gpt4oaudiopreview20241217":
            return .custom("gpt-4o-audio-preview-2024-12-17")
        case "gpt-4o-audio-preview", "gpt4oaudiopreview":
            return .custom("gpt-4o-audio-preview")
        case "gpt-4o-audio-preview-2024-10-01", "gpt4oaudiopreview20241001":
            return .custom("gpt-4o-audio-preview-2024-10-01")
            
        // Special cases
        case "gpt-4.5-preview", "gpt45preview":
            return .custom("gpt-4.5-preview")
        case "gpt-4.5-preview-2025-02-27", "gpt45preview20250227":
            return .custom("gpt-4.5-preview-2025-02-27")
            
        // Default case for any model not explicitly mapped
        default:
            // For any other model, use the custom case with the raw model string
            return .custom(modelString)
        }
    }
}

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
            lastRevNodeArray = nodes
            return nodes
        } else {
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
