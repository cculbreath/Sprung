// PhysCloudResume/AI/Models/Services/LLMRequestService.swift

import Foundation
import SwiftUI

/// Service responsible for handling LLM API requests
class LLMRequestService: @unchecked Sendable {
    /// Shared instance of the service
    static let shared = LLMRequestService()
    
    private var openAIClient: OpenAIClientProtocol?
    private var currentRequestID: UUID?
    private let apiQueue = DispatchQueue(label: "com.physcloudresume.apirequest", qos: .userInitiated)
    
    // Private initializer for singleton pattern
    private init() {}
    
    /// Initializes the LLM client for OpenAI
    @MainActor
    func initialize() {
        // Use OpenAI API key for all models
        let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        guard apiKey != "none" else { return }
        // Create a standard OpenAI client
        openAIClient = OpenAIClientFactory.createClient(apiKey: apiKey)
    }
    
    /// Checks if the currently selected model supports images
    func checkIfModelSupportsImages() -> Bool {
        let model = OpenAIModelFetcher.getPreferredModelString().lowercased()
        
        // For OpenAI models
        let openAIVisionModelsSubstrings = ["gpt-4o", "gpt-4-turbo", "gpt-4-vision", "gpt-4.1", "gpt-image", "o4", "cua"]
        return openAIVisionModelsSubstrings.contains { model.contains($0) }
    }

    /// Sends a standard LLM request with text-only content
    @MainActor
    func sendTextRequest(
        promptText: String,
        model: String,
        previousResponseId: String?,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    ) {
        if openAIClient == nil { initialize() }
        guard let client = openAIClient else {
            onComplete(.failure(NSError(domain: "LLMRequestService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "LLM client not initialized"])))
            return
        }
        
        let requestID = UUID(); currentRequestID = requestID
        
        Task {
            do {
                // Don't specify temperature to use model defaults
                let response = try await client.sendResponseRequestAsync(
                    message: promptText,
                    model: model,
                    temperature: nil as Double?,
                    previousResponseId: previousResponseId,
                    schema: nil as String?
                )
                
                // Ensure request is still current
                guard self.currentRequestID == requestID else { return }
                
                onProgress(response.content) // Send full content as one "chunk"
                onComplete(.success(response))
            } catch {
                // Log error details for debugging
                Logger.debug("Error in sendTextRequest: \(error.localizedDescription)")
                
                // Create a user-friendly error message that includes more details
                var userErrorMessage = "Error processing your request. "
                
                if let nsError = error as NSError? {
                    Logger.debug("Error domain: \(nsError.domain), code: \(nsError.code), userInfo: \(nsError.userInfo)")
                    
                    // Check for specific types of errors
                    if nsError.domain == "OpenAIAPI" {
                        userErrorMessage += "API issue: \(nsError.localizedDescription)"
                    } else if nsError.domain.contains("URLError") && nsError.code == -1001 {
                        userErrorMessage += "Request timed out. Please check your network connection and try again."
                    } else if let errorInfo = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                        // Extract meaningful error information
                        if errorInfo.contains("temperature") || errorInfo.contains("parameter") {
                            userErrorMessage = "Model compatibility issue: \(errorInfo). Please try a different model in Settings."
                        } else {
                            userErrorMessage += errorInfo
                        }
                    }
                }
                
                // Send the error as part of the completion handler for display in the UI
                guard self.currentRequestID == requestID else { return }
                onComplete(.failure(NSError(
                    domain: "LLMRequestService",
                    code: 1100,
                    userInfo: [NSLocalizedDescriptionKey: userErrorMessage]
                )))
            }
        }
    }
    
    /// Sends a request that can include an image and/or JSON schema
    func sendMixedRequest(
        promptText: String,
        base64Image: String?,
        previousResponseId: String?,
        schema: (name: String, jsonString: String)?,
        requestID: UUID = UUID(),
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    ) {
        currentRequestID = requestID
        
        apiQueue.async { // Perform network request on a background queue
            // Send request to OpenAI's /v1/responses endpoint
            self.sendOpenAIRequest(
                promptText: promptText,
                base64Image: base64Image,
                previousResponseId: previousResponseId,
                modelString: OpenAIModelFetcher.getPreferredModelString(),
                schema: schema,
                requestID: requestID,
                onComplete: onComplete
            )
        }
    }
    
    /// Sends request to OpenAI's /v1/responses endpoint
    private func sendOpenAIRequest(
        promptText: String,
        base64Image: String?,
        previousResponseId: String?,
        modelString: String,
        schema: (name: String, jsonString: String)?,
        requestID: UUID,
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    ) {
        guard let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey"), apiKey != "none" else {
            DispatchQueue.main.async {
                onComplete(.failure(NSError(domain: "LLMRequestService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key not set."])))
            }
            return
        }

        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            DispatchQueue.main.async {
                onComplete(.failure(NSError(domain: "LLMRequestService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL."])))
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 900.0 // 15 minutes for reasoning models
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the content array correctly
        var userInputContent: [[String: Any]] = [["type": "input_text", "text": promptText]]
        if let img = base64Image {
            // Use correct structure for image data in responses API
            userInputContent.append([
                "type": "input_image",
                "image_url": "data:image/png;base64,\(img)",
                "detail": "high", // Optional: consider making this configurable
            ])
        }

        var requestBodyDict: [String: Any] = [
            "model": modelString,
            "input": [
                ["role": "system", "content": "You are an expert AI assistant."],
                ["role": "user", "content": userInputContent],
            ],
        ]

        if let prevId = previousResponseId, !prevId.isEmpty {
            requestBodyDict["previous_response_id"] = prevId
        }

        if let schemaInfo = schema,
           let schemaData = schemaInfo.jsonString.data(using: .utf8),
           let schemaJson = try? JSONSerialization.jsonObject(with: schemaData, options: []) as? [String: Any]
        {
            // Set the text.format parameter to enforce JSON schema validation server-side
            // Note: 'response_format' has moved to 'text.format' in the Responses API
            requestBodyDict["text"] = [
                "format": [
                    "type": "json_schema",
                    "name": schemaInfo.name,
                    "schema": schemaJson,
                    "strict": true
                ]
            ]
            
            // Log that we're using schema validation
            Logger.debug("OpenAI request includes text.format schema validation for \(schemaInfo.name)")
            Logger.debug("Schema strict mode is enabled to enforce server-side validation")
            Logger.debug("Using updated Responses API format (text.format instead of response_format)")
        }

        // Debug: Print the request body (with image data omitted or truncated)
        var sanitizedRequestBodyDict = requestBodyDict
        if let inputMessages = sanitizedRequestBodyDict["input"] as? [[String: Any]] {
            var sanitizedInputMessages = inputMessages
            for (i, message) in inputMessages.enumerated() {
                if let contentArray = message["content"] as? [[String: Any]] {
                    var sanitizedContentArray = contentArray
                    for (j, contentItem) in contentArray.enumerated() {
                        if contentItem["type"] as? String == "input_image" {
                            var mutableContentItem = contentItem
                            mutableContentItem["image_url"] = "<base64_image_data_omitted>"
                            sanitizedContentArray[j] = mutableContentItem
                        }
                    }
                    var mutableMessage = message
                    mutableMessage["content"] = sanitizedContentArray
                    sanitizedInputMessages[i] = mutableMessage
                }
            }
            sanitizedRequestBodyDict["input"] = sanitizedInputMessages
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: sanitizedRequestBodyDict, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            Logger.debug("OpenAI Request Body for \(schema?.name ?? "General Review") (Image Omitted):\n\(jsonString)")
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBodyDict) else {
            DispatchQueue.main.async {
                onComplete(.failure(NSError(domain: "LLMRequestService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request body."])))
            }
            return
        }
        request.httpBody = httpBody

        // Send the request to OpenAI
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // Ensure the callback is on the main thread
            DispatchQueue.main.async {
                guard self.currentRequestID == requestID else {
                    Logger.debug("Request \(requestID) was cancelled or superseded.")
                    return
                }

                if let error = error {
                    onComplete(.failure(error))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    onComplete(.failure(NSError(domain: "LLMRequestService", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response."])))
                    return
                }

                guard let responseData = data else {
                    onComplete(.failure(NSError(domain: "LLMRequestService", code: 1006, userInfo: [NSLocalizedDescriptionKey: "No data in API response."])))
                    return
                }

                if let responseString = String(data: responseData, encoding: .utf8) {
                    Logger.debug("OpenAI Raw Response for \(schema?.name ?? "General Review") (Status: \(httpResponse.statusCode)):\n\(responseString)")
                }

                if !(200 ... 299).contains(httpResponse.statusCode) {
                    var errorMessage = "API Error: \(httpResponse.statusCode)."
                    if let errorData = data, let errorDetails = String(data: errorData, encoding: .utf8) {
                        errorMessage += " Details: \(errorDetails)"
                    }
                    onComplete(.failure(NSError(domain: "LLMRequestService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                    return
                }

                do {
                    let decodedWrapper = try JSONDecoder().decode(ResponsesAPIResponseWrapper.self, from: responseData)
                    
                    // Add detailed logging about the structure of the response
                    if let outputMessages = decodedWrapper.output {
                        Logger.debug("Response contains \(outputMessages.count) messages")
                        for (index, message) in outputMessages.enumerated() {
                            Logger.debug("Message \(index + 1): type=\(message.type), role=\(message.role ?? "none")")
                            if let content = message.content {
                                Logger.debug("  - Message \(index + 1) has \(content.count) content items")
                                for (contentIndex, item) in content.enumerated() {
                                    Logger.debug("    - Content \(contentIndex + 1): type=\(item.type), has text=\(item.text != nil), text length=\(item.text?.count ?? 0)")
                                }
                            } else {
                                Logger.debug("  - Message \(index + 1) has no content items")
                            }
                        }
                    } else if !decodedWrapper.content.isEmpty {
                        Logger.debug("Response contains direct content (length: \(decodedWrapper.content.count))")
                    }
                    
                    // Extract content and log its length
                    let extractedContent = decodedWrapper.content
                    Logger.debug("Extracted content length: \(extractedContent.count)")
                    
                    onComplete(.success(decodedWrapper.toResponsesAPIResponse()))
                } catch let decodingError {
                    Logger.debug("Error decoding OpenAI Response: \(decodingError)")
                    onComplete(.failure(decodingError))
                }
            }
        }
        task.resume()
    }
    
    /// Cancels the current request
    func cancelRequest() {
        currentRequestID = nil // This will cause ongoing callbacks to be ignored
    }
}
