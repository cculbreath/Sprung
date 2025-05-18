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



    /// Default initializer - uses factory to create client
    /// - Parameters:
    ///   - jobApps: List of job applications
    ///   - resume: The resume to use
    init(jobApps: [JobApp], resume: Resume?) {
        self.jobApps = jobApps
        self.resume = resume

        // Get API key from UserDefaults directly to avoid conflict with @Observable
        let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        
        // Create configuration with relaxed parsing to handle null system_fingerprint
        let configuration = OpenAIConfiguration.relaxedParsing(token: apiKey)
        
        // Create client using our factory with relaxed configuration
        openAIClient = OpenAIClientFactory.createClient(configuration: configuration)
        
        Logger.debug("JobRecommendationProvider initialized")
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
        
        // Always log the model being used
        Logger.info("Using model: \(modelString) for job recommendation")

        do {
            // Check if we're using our custom SystemFingerprintFixClient
            if let fingerprintFixClient = openAIClient as? SystemFingerprintFixClient {
                Logger.debug("Using SystemFingerprintFixClient for job recommendation")
                
                // Send the request directly through our custom client
                let response = try await fingerprintFixClient.sendChatCompletionAsync(
                    messages: messages,
                    model: modelString,
                    temperature: 1.0
                )
                
                // Process the response directly
                Logger.debug("Received response from SystemFingerprintFixClient: \(response.content)")
                
                let content = response.content
                
                // Log the content for debugging
                Logger.error("FULL LLM RESPONSE CONTENT:\n\(content)")
                
                // Always save the raw response to a file for debugging
                savePromptToDownloads(content: content, fileName: "jobRecommendationRawResponse_\(modelString).txt")
                
                // Try to parse the JSON response
                guard let data = content.data(using: .utf8) else {
                    Logger.error("Failed to convert response content to data")
                    throw NSError(domain: "JobRecommendationProvider", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Failed to convert response content to data"])
                }
                
                // Try to parse it as a dictionary first to extract the fields manually
                if let jsonObj = try? JSONSerialization.jsonObject(with: data),
                   let jsonDict = jsonObj as? [String: Any] {
                    
                    // Extract the recommendedJobId field
                    guard let recommendedJobId = jsonDict["recommendedJobId"] as? String else {
                        Logger.error("Missing recommendedJobId in response: \(jsonDict)")
                        throw NSError(domain: "JobRecommendationProvider", code: 1006, userInfo: [NSLocalizedDescriptionKey: "Missing recommendedJobId in response"])
                    }
                    
                    // Extract the reason field, with a default value if it's missing
                    let reason = jsonDict["reason"] as? String ?? "No reason provided"
                    
                    // Check if UUID is valid
                    guard let uuid = UUID(uuidString: recommendedJobId) else {
                        Logger.error("Invalid UUID format in response: \(recommendedJobId)")
                        throw NSError(domain: "JobRecommendationProvider", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid UUID format in response: \(recommendedJobId)"])
                    }
                    
                    // Look for the job with this UUID
                    if let _ = jobApps.first(where: { $0.id == uuid }) {
                        Logger.info("Successfully found matching job with UUID: \(uuid)")
                        return (uuid, reason)
                    } else {
                        // Log all job IDs for debugging
                        let availableIds = jobApps.map { $0.id.uuidString }.joined(separator: ", ")
                        Logger.error("Job with ID \(uuid.uuidString) not found. Available job IDs: \(availableIds)")
                        throw NSError(domain: "JobRecommendationProvider", code: 6, userInfo: [NSLocalizedDescriptionKey: "Job with ID \(uuid.uuidString) not found in job applications"])
                    }
                } else {
                    // If manual parsing fails, try with the decoder as a fallback
                    do {
                        let recommendation = try JSONDecoder().decode(JobRecommendation.self, from: data)
                        
                        // Process the structured output
                        guard let uuid = UUID(uuidString: recommendation.recommendedJobId) else {
                            Logger.error("Invalid UUID format in response: \(recommendation.recommendedJobId)")
                            throw NSError(domain: "JobRecommendationProvider", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid UUID format in response: \(recommendation.recommendedJobId)"])
                        }
                        
                        // Look for the job with this UUID
                        if let _ = jobApps.first(where: { $0.id == uuid }) {
                            Logger.info("Successfully found matching job with UUID: \(uuid)")
                            return (uuid, recommendation.reason)
                        } else {
                            throw NSError(domain: "JobRecommendationProvider", code: 6, userInfo: [NSLocalizedDescriptionKey: "Job with ID \(uuid.uuidString) not found in job applications"])
                        }
                    } catch {
                        Logger.error("Failed to parse response as JSON: \(error)")
                        throw NSError(domain: "JobRecommendationProvider", code: 1007, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response as JSON"])
                    }
                }
            } else {
                // Fallback to the old method for non-custom clients
                Logger.info("Using standard non-custom client for job recommendation")
                let response = try await openAIClient.sendChatCompletionAsync(
                    messages: messages,
                    model: modelString,
                    temperature: 1.0
                )

                // Process the response using the old method
                let decodedResponse = try decodeRecommendation(from: response.content)
                return decodedResponse
            }
        } catch {
            // Log detailed error information at the top level
            Logger.error("Job recommendation API call failed: \(error.localizedDescription)")
            
            // Convert to NSError to access more details
            let nsError = error as NSError
            
            // Log all error details
            let fullErrorDetails = "FULL API ERROR DETAILS:\nDomain: \(nsError.domain)\nCode: \(nsError.code)\nDescription: \(nsError.localizedDescription)\nUserInfo: \(nsError.userInfo)"
            Logger.error(fullErrorDetails)
            
            // Check if this is the specific system_fingerprint error
            if nsError.domain == "NSCocoaErrorDomain" && nsError.code == 4865,
               let _ = nsError.userInfo["NSCodingPath"] as? [Any],
               let debugDesc = nsError.userInfo["NSDebugDescription"] as? String,
               debugDesc.contains("null value") {
                
                Logger.error("This appears to be the system_fingerprint null value error - which means the API call worked but there's a JSON parsing issue")
            }
            
            // Save all error details for debugging
            savePromptToDownloads(content: fullErrorDetails, fileName: "api_error_details.txt")
            
            throw error
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

    private func decodeRecommendation(from responseText: String) throws -> (UUID, String) {
        // Save complete response for debugging
        if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
            savePromptToDownloads(content: responseText, fileName: "jobRecommendationResponse.txt")
        }
        
        // Always save the raw response for debugging this specific issue
        // This will happen even if debug file saving is turned off
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        savePromptToDownloads(content: responseText, fileName: "jobRecommendationResponse_\(modelString)_auto.txt")
        
        // Always log the response for debugging the missing data error
        Logger.debug("API Response to decode: \(responseText)")
        if responseText.isEmpty {
            Logger.warning("Empty response text received from API")
            throw NSError(
                domain: "JobRecommendationProvider",
                code: 4001,
                userInfo: [NSLocalizedDescriptionKey: "Empty response received from API"]
            )
        }

        // Try to parse the JSON response
        guard let data = responseText.data(using: .utf8) else {
            Logger.error("Could not convert API response to data")
            throw NSError(domain: "JobRecommendationProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not convert response to data"])
        }
        
        // Log the data length for debugging
        Logger.debug("API Response data length: \(data.count) bytes")
        if data.count == 0 {
            Logger.warning("Zero-length data from API response")
            throw NSError(
                domain: "JobRecommendationProvider",
                code: 4002,
                userInfo: [NSLocalizedDescriptionKey: "Zero-length data from API response"]
            )
        }
        
        // Try to validate if the response is valid JSON
        do {
            let _ = try JSONSerialization.jsonObject(with: data, options: [])
            Logger.debug("Response is valid JSON structure")
        } catch {
            Logger.error("Response is not valid JSON: \(error.localizedDescription)")
            savePromptToDownloads(content: "Invalid JSON:\n\(responseText)", fileName: "invalid_json_response.txt")
            throw NSError(
                domain: "JobRecommendationProvider",
                code: 4003,
                userInfo: [NSLocalizedDescriptionKey: "Response is not valid JSON: \(error.localizedDescription)"]
            )
        }

        // Decode the recommendation
        let recommendation: JobRecommendation
        do {
            recommendation = try JSONDecoder().decode(JobRecommendation.self, from: data)
        } catch {
            // Log detailed error information
            Logger.debug("🚨 JSON decode error: \(error)")
            
            // Try to decode error response instead
            do {
                let errorResponse = try JSONDecoder().decode([String: String].self, from: data)
                Logger.debug("📝 Error response: \(errorResponse)")
            } catch {
                Logger.debug("🚨 Could not decode as error response either")
            }
            
            // Always save error details for debugging
            let errorDetails = "JSON decode error: \(error)\nError type: \(type(of: error))\n\nResponse data:\n\(responseText)"
            Logger.debug(errorDetails)
            savePromptToDownloads(content: errorDetails, fileName: "jsonError.txt")
            
            // Include the response text in the error for debugging
            var userInfo: [String: Any] = [
                NSLocalizedDescriptionKey: "Failed to decode JSON response: \(error.localizedDescription)"
            ]
            
            // Add the original error
            userInfo[NSUnderlyingErrorKey] = error
            
            // Create a detailed error with the raw response text
            throw NSError(
                domain: "JobRecommendationProvider",
                code: 4,
                userInfo: userInfo
            )
        }

        // Try to create a UUID from the recommendedJobId and find matching job
        guard let uuid = UUID(uuidString: recommendation.recommendedJobId) else {
            throw NSError(
                domain: "JobRecommendationProvider",
                code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid UUID format in response: \(recommendation.recommendedJobId)",
                ]
            )
        }

        // Look for the job with this UUID
        if let _ = jobApps.first(where: { $0.id == uuid }) {
            return (uuid, recommendation.reason)
        }

        throw NSError(
            domain: "JobRecommendationProvider",
            code: 6,
            userInfo: [
                NSLocalizedDescriptionKey: "Job with ID \(uuid.uuidString) not found in job applications",
            ]
        )
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