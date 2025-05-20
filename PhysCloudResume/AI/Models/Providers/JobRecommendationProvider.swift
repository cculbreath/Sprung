//
//  JobRecommendationProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/20/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

@Observable class JobRecommendationProvider {
    // MARK: - Properties

    // The system message in generic format for abstraction layer
    let genericSystemMessage = ChatMessage(
        role: .system,
        content: """
        You are an expert career advisor specializing in job application prioritization. Your task is to analyze a list of job applications and recommend the one that best matches the candidate's qualifications and career goals. You will be provided with job descriptions, the candidate's resume, and additional background information. Choose the job that offers the best match in terms of skills, experience, and potential career growth.

        IMPORTANT: Your response must be a valid JSON object conforming to the JSON schema provided. The recommendedJobId field must contain the exact UUID string from the id field of the chosen job in the job listings JSON array. Do not modify the UUID format in any way.
        
        IMPORTANT: Output ONLY the JSON object with the fields "recommendedJobId" and "reason". Do not include any additional commentary, explanation, or text outside the JSON.
        """
    )

    // The new abstraction layer client
    private let openAIClient: OpenAIClientProtocol

    var jobApps: [JobApp] = []
    var resume: Resume?

    // MARK: - Derived Properties

    var backgroundDocs: String {
        guard let resume = resume else { return "" }

        let bgrefs = resume.enabledSources
        if bgrefs.isEmpty {
            return ""
        } else {
            return bgrefs.map { $0.name + ":\n" + $0.content + "\n\n" }.joined()
        }
    }

    // MARK: - Initialization

    /// Default initializer - uses factory to create client for current model
    /// - Parameters:
    ///   - jobApps: List of job applications
    ///   - resume: The resume to use
    init(jobApps: [JobApp], resume: Resume?) {
        self.jobApps = jobApps
        self.resume = resume

        // Get API keys from UserDefaults
        let openAIKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        let claudeKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? "none"
        let grokKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? "none"
        let geminiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? "none"
        
        // Create a dictionary of API keys by provider
        let apiKeys = [
            AIModels.Provider.openai: openAIKey,
            AIModels.Provider.claude: claudeKey,
            AIModels.Provider.grok: grokKey,
            AIModels.Provider.gemini: geminiKey
        ]
        
        // Get current model string
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        let provider = AIModels.providerForModel(modelString)
        
        Logger.debug("Creating JobRecommendationProvider for model: \(modelString) (Provider: \(provider))")
        
        // Create client for the specific model using the factory
        if let client = OpenAIClientFactory.createClientForModel(model: modelString, apiKeys: apiKeys) {
            openAIClient = client
            Logger.debug("JobRecommendationProvider initialized with model-specific client for \(modelString)")
        } else if let client = OpenAIClientFactory.createClient(apiKey: openAIKey) {
            // Fallback to standard OpenAI client if model-specific client creation fails
            openAIClient = client
            Logger.debug("JobRecommendationProvider initialized with standard OpenAI client (fallback)")
        } else {
            // If all client creation fails, throw a runtime error
            Logger.error("Failed to create client for any provider")
            fatalError("Failed to initialize JobRecommendationProvider: No valid API keys available")
        }
    }

    // MARK: - API Call Functions

    /// Fetches job recommendation using the abstraction layer
    /// - Returns: A tuple containing the recommended job ID and reason
    func fetchRecommendation() async throws -> (UUID, String) {
        guard let resume = resume, let _ = resume.model else {
            throw NSError(domain: "JobRecommendationProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "No resume available"])
        }

        let newJobApps = jobApps.filter { $0.status == .new }
        if newJobApps.isEmpty {
            throw NSError(domain: "JobRecommendationProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "No new job applications available"])
        }

        let prompt = buildPrompt(newJobApps: newJobApps, resume: resume)

        if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
            savePromptToDownloads(content: prompt, fileName: "jobRecommendationPrompt.txt")
        }

        // Use our generic message format with the abstraction layer
        let messages = [
            genericSystemMessage,
            ChatMessage(role: .user, content: prompt),
        ]

        // Get the model string
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        let provider = AIModels.providerForModel(modelString)
        
        // Always log the model being used
        Logger.info("Using model: \(modelString) for job recommendation")
        
        do {
            Logger.debug("Using \(provider) client for job recommendation with model: \(modelString)")
            
            // For Gemini models, test the connection first
            if provider == AIModels.Provider.gemini {
                // Get Gemini API key
                guard let geminiApiKey = UserDefaults.standard.string(forKey: "geminiApiKey"),
                      !geminiApiKey.isEmpty, geminiApiKey != "none" else {
                    throw NSError(domain: "JobRecommendationProvider", code: 1000, 
                                  userInfo: [NSLocalizedDescriptionKey: "No Gemini API key available"])
                }
                
            
            }
            
            // For Claude models, fall back to direct API call if SwiftOpenAI client fails
            if provider == AIModels.Provider.claude {
                // Try the built-in client first, but prepare to fall back to direct API call
                do {
                    // Format the model name correctly
                    var formattedModel = modelString
                    if !modelString.contains("-2024") {
                        // If it's a base model without date, use the default dated version
                        switch modelString.lowercased() {
                        case "claude-3-opus":
                            formattedModel = "claude-3-opus-20240229"
                        case "claude-3-sonnet":
                            formattedModel = "claude-3-sonnet-20240229"
                        case "claude-3-haiku":
                            formattedModel = "claude-3-haiku-20240307"
                        case "claude-3-5-sonnet":
                            formattedModel = "claude-3-5-sonnet-20240620"
                        default:
                            formattedModel = modelString
                        }
                    }
                    Logger.debug("Formatted Claude model: \(modelString) -> \(formattedModel)")
                    
                    // First try using the client
                    return try await useGenericClient(
                        messages: messages,
                        model: formattedModel
                    )
                } catch {
                    // If client fails, try direct API call as fallback
                    Logger.debug("⚠️ SwiftOpenAI client failed for Claude, falling back to direct API call")
                    Logger.debug("Error was: \(error.localizedDescription)")
                    
                    // Get Claude API key
                    guard let claudeApiKey = UserDefaults.standard.string(forKey: "claudeApiKey"),
                          !claudeApiKey.isEmpty, claudeApiKey != "none" else {
                        throw NSError(domain: "JobRecommendationProvider", code: 1000, 
                                     userInfo: [NSLocalizedDescriptionKey: "No Claude API key available"])
                    }
                    
                    // Fall back to OpenAI model
                    Logger.debug("⚠️ Falling back to OpenAI model")
                    let openaiModel = "gpt-4o"
                    return try await useGenericClient(
                        messages: messages,
                        model: openaiModel
                    )
                }
            } else {
                // For non-Claude models, use the standard client approach
                return try await useGenericClient(
                    messages: messages,
                    model: modelString
                )
            }
        } catch {
            // Any errors not caught by the above will be propagated here
            throw error
        }
    }
    
    // Helper method for using the generic client
    private func useGenericClient(messages: [ChatMessage], model: String) async throws -> (UUID, String) {
        // Get the provider for the model
        let provider = AIModels.providerForModel(model)
        
        // Determine effective messages (drop system for non-GPT chat models like reasoning models)
        var effectiveMessages = messages
        let modelLower = model.lowercased()
        if provider == AIModels.Provider.openai, !modelLower.starts(with: "gpt") {
            effectiveMessages = messages.filter { $0.role != .system }
            Logger.debug("Stripped system messages for non-GPT chat model: \(model)")
        }
        // Use the standard library's jsonObject response format
        // This uses our AIResponseFormat
        let responseFormat: AIResponseFormat = .jsonObject
        
        // Log that we're using JSON mode
        Logger.debug("Using JSON mode for job recommendation with model: \(model) (Provider: \(provider))")
        
        // Special handling for Gemini models using OpenAI-compatible endpoint
        if provider == AIModels.Provider.gemini {
            Logger.debug("📝 Using OpenAI-compatible endpoint for Gemini job recommendation")
            // For Gemini, we need to ensure we're using the correct format for JSON response
            // Our modifications above with OpenAI-compatible endpoint should handle this properly
        }
        
        // Use sendChatCompletionAsync with responseFormat parameter
        let response = try await openAIClient.sendChatCompletionAsync(
            messages: effectiveMessages,
            model: model,
            responseFormat: responseFormat,
            temperature: nil
        )
        
        // Process the response
        Logger.debug("Received response from AI client: \(response.content)")
        
        // Continue with JSON parsing and uuid extraction
        return try processApiResponse(content: response.content)
    }
    
    // Helper method for direct Claude API calls as a fallback
    private func useDirectClaudeApi(messages: [ChatMessage], model: String, apiKey: String) async throws -> (UUID, String) {
        Logger.debug("🤖 Making direct Claude API call for model: \(model)")
        
        // Build Claude-specific message format
        var claudeMessages: [[String: Any]] = []
        var systemPrompt: String? = nil
        
        // Process messages and separate system messages
        for message in messages {
            switch message.role {
            case .system:
                // Store system message separately for top-level parameter
                systemPrompt = message.content
                Logger.debug("📝 Found system message for Claude API")
            case .user:
                claudeMessages.append([
                    "role": "user",
                    "content": message.content
                ])
            case .assistant:
                claudeMessages.append([
                    "role": "assistant",
                    "content": message.content
                ])
            }
        }
        
        // Ensure the last message is from the user (Claude requires this)
        if let lastMessage = claudeMessages.last, 
           let lastRole = lastMessage["role"] as? String, 
           lastRole != "user" {
            Logger.debug("⚠️ Claude API: Last message must be from user, adding empty user message")
            claudeMessages.append([
                "role": "user",
                "content": "Please continue."
            ])
        }
        
        // Prepare request body
        var requestBody: [String: Any] = [
            "model": model,
            "messages": claudeMessages,
            "temperature": 0.7,
            "max_tokens": 4096
        ]
        
        // Add system message as a top-level parameter (Claude API requirement)
        if let systemPrompt = systemPrompt {
            requestBody["system"] = systemPrompt
            Logger.debug("📝 Claude API: Adding system message as top-level parameter")
        }
        
        // Convert to JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw NSError(domain: "JobRecommendationProvider", code: 1001,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to encode Claude API request"])
        }
        
        // Create URL request
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        
        // Set headers - crucial for Claude API
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "JobRecommendationProvider", code: 1002,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid Claude API response type"])
        }
        
        // Log response details
        Logger.debug("Claude API response status: \(httpResponse.statusCode)")
        
        // Check for error responses
        guard httpResponse.statusCode == 200 else {
            // Try to extract error details from response
            var errorMessage = "Claude API error: status code \(httpResponse.statusCode)"
            if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorResponse["error"] as? [String: Any],
               let message = error["message"] as? String {
                errorMessage += " - \(message)"
            }
            
            Logger.error(errorMessage)
            throw NSError(domain: "ClaudeAPI", code: httpResponse.statusCode,
                         userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        // Parse the successful response
        guard let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = responseDict["content"] as? [[String: Any]],
              let firstContentBlock = content.first,
              let text = firstContentBlock["text"] as? String else {
            throw NSError(domain: "JobRecommendationProvider", code: 1003,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse Claude API response"])
        }
        
        Logger.debug("✅ Claude API call successful, processing response")
        
        // Save raw response for debugging if needed
        if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
            savePromptToDownloads(content: text, fileName: "claudeApiRawResponse.txt")
        }
        
        // Process response using the same JSON parsing logic
        return try processApiResponse(content: text)
    }
    
    // Common response processing logic
    private func processApiResponse(content: String) throws -> (UUID, String) {
        // Strip any markdown code block formatting (```json and ```) from the content
        var processedContent = content
        
        // Remove opening markdown code block markers (```json, ```javascript, etc.)
        if let openingBlockRange = processedContent.range(of: "```[a-zA-Z]*\\s*", options: .regularExpression) {
            processedContent.removeSubrange(openingBlockRange)
        }
        
        // Remove closing markdown code block markers
        if let closingBlockRange = processedContent.range(of: "\\s*```", options: .regularExpression) {
            processedContent.removeSubrange(closingBlockRange)
        }
        // Extract JSON substring if surrounded by explanatory text
        if let firstBrace = processedContent.firstIndex(of: "{"), let lastBrace = processedContent.lastIndex(of: "}") {
            processedContent = String(processedContent[firstBrace...lastBrace])
        }
        
        // Try to parse the JSON response
        guard let data = processedContent.data(using: .utf8) else {
            Logger.error("Failed to convert response content to data")
            throw NSError(domain: "JobRecommendationProvider", code: 1005, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to convert response content to data"])
        }
        
        // Always save the raw and processed responses to files for debugging
        if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
            savePromptToDownloads(content: content, fileName: "jobRecommendationRawResponse.txt")
            savePromptToDownloads(content: processedContent, fileName: "jobRecommendationProcessedResponse.txt")
        }
        
        // Try to parse it as a dictionary first to extract the fields manually
        if let jsonObj = try? JSONSerialization.jsonObject(with: data),
           let jsonDict = jsonObj as? [String: Any] {
            
            // Extract the recommendedJobId field
            guard let recommendedJobId = jsonDict["recommendedJobId"] as? String else {
                Logger.error("Missing recommendedJobId in response: \(jsonDict)")
                throw NSError(domain: "JobRecommendationProvider", code: 1006, 
                             userInfo: [NSLocalizedDescriptionKey: "Missing recommendedJobId in response"])
            }
            
            // Extract the reason field, with a default value if it's missing
            let reason = jsonDict["reason"] as? String ?? "No reason provided"
            
            // Check if UUID is valid
            guard let uuid = UUID(uuidString: recommendedJobId) else {
                Logger.error("Invalid UUID format in response: \(recommendedJobId)")
                throw NSError(domain: "JobRecommendationProvider", code: 5, 
                             userInfo: [NSLocalizedDescriptionKey: "Invalid UUID format in response: \(recommendedJobId)"])
            }
            
            // Look for the job with this UUID
            if let _ = jobApps.first(where: { $0.id == uuid }) {
                Logger.info("Successfully found matching job with UUID: \(uuid)")
                return (uuid, reason)
            } else {
                // Log all job IDs for debugging
                let availableIds = jobApps.map { $0.id.uuidString }.joined(separator: ", ")
                Logger.error("Job with ID \(uuid.uuidString) not found. Available job IDs: \(availableIds)")
                throw NSError(domain: "JobRecommendationProvider", code: 6, 
                             userInfo: [NSLocalizedDescriptionKey: "Job with ID \(uuid.uuidString) not found in job applications"])
            }
        } else {
            // If manual parsing fails, try with the decoder as a fallback
            do {
                let recommendation = try JSONDecoder().decode(JobRecommendation.self, from: data)
                
                // Process the structured output
                guard let uuid = UUID(uuidString: recommendation.recommendedJobId) else {
                    Logger.error("Invalid UUID format in response: \(recommendation.recommendedJobId)")
                    throw NSError(domain: "JobRecommendationProvider", code: 5, 
                                 userInfo: [NSLocalizedDescriptionKey: "Invalid UUID format in response: \(recommendation.recommendedJobId)"])
                }
                
                // Look for the job with this UUID
                if let _ = jobApps.first(where: { $0.id == uuid }) {
                    Logger.info("Successfully found matching job with UUID: \(uuid)")
                    return (uuid, recommendation.reason)
                } else {
                    throw NSError(domain: "JobRecommendationProvider", code: 6, 
                                 userInfo: [NSLocalizedDescriptionKey: "Job with ID \(uuid.uuidString) not found in job applications"])
                }
            } catch {
                Logger.error("Failed to parse response as JSON: \(error)")
                throw NSError(domain: "JobRecommendationProvider", code: 1007, 
                             userInfo: [NSLocalizedDescriptionKey: "Failed to parse response as JSON"])
            }
        }
    }

    // MARK: - Helper Functions

    private func buildPrompt(newJobApps: [JobApp], resume: Resume) -> String {
        let resumeText = resume.textRes == "" ? resume.model?.renderedResumeText ?? "" : resume.textRes

        // Create JSON array of job listings
        var jobsArray: [[String: Any]] = []
        for app in newJobApps {
            let jobDict: [String: Any] = [
                "id": app.id.uuidString,
                "position": app.jobPosition,
                "company": app.companyName,
                "location": app.jobLocation,
                "description": app.jobDescription,
            ]
            jobsArray.append(jobDict)
        }

        // Convert to JSON string
        let jsonData = try? JSONSerialization.data(withJSONObject: jobsArray, options: [.prettyPrinted])
        let jsonString = jsonData != nil ? String(data: jsonData!, encoding: .utf8) ?? "" : ""

        let prompt = """
        TASK:
        Analyze the candidate's resume, background information, and the list of new job applications. Recommend the ONE job that is the best match for the candidate's qualifications and career goals.

        CANDIDATE'S RESUME:
        \(resumeText)

        BACKGROUND INFORMATION:
        \(backgroundDocs)

        JOB LISTINGS (JSON FORMAT):
        \(jsonString)

        RESPONSE INSTRUCTIONS:
        You must return a valid JSON object with exactly these two fields:
        1. "recommendedJobId": The exact UUID string from the 'id' field of the best matching job
        2. "reason": A brief explanation of why this job is the best match

        Example response format:
        {
          "recommendedJobId": "00000000-0000-0000-0000-000000000000",
          "reason": "This job aligns with the candidate's experience in..."
        }

        IMPORTANT: The recommendedJobId MUST be copied exactly, character-for-character from the 'id' field of the job listing you select.
        """

        return prompt
    }

    // Define structured output schema for job recommendations
    struct JobRecommendation: Codable, StructuredOutput {
        let recommendedJobId: String
        let reason: String
    }

    private func savePromptToDownloads(content: String, fileName: String) {
        // Only save if debug file saving is enabled in UserDefaults
        guard UserDefaults.standard.bool(forKey: "saveDebugPrompts") else {
            return
        }
        
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            Logger.debug("Saved debug file: \(fileName)")
        } catch {
            Logger.warning("Failed to save debug file \(fileName): \(error.localizedDescription)")
        }
    }
}
