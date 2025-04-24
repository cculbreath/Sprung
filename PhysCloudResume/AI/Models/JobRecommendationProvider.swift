//
//  JobRecommendationProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/20/25.
//

import Foundation
import OpenAI
import SwiftUI

@Observable class JobRecommendationProvider {
    // MARK: - Properties

    /// Set this to `true` if you want to save a debug file containing the prompt text.
    var saveDebugPrompt: Bool = false

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

    var savePromptToFile: Bool
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

    /// Initialize with specific OpenAI client
    /// - Parameters:
    ///   - jobApps: List of job applications
    ///   - resume: The resume to use
    ///   - client: Custom OpenAI client to use
    ///   - savePromptToFile: Whether to save debug files
    init(jobApps: [JobApp], resume: Resume?, client: OpenAIClientProtocol, savePromptToFile: Bool = false) {
        self.jobApps = jobApps
        self.resume = resume
        self.savePromptToFile = savePromptToFile
        openAIClient = client
    }

    /// Default initializer - uses factory to create client
    /// - Parameters:
    ///   - jobApps: List of job applications
    ///   - resume: The resume to use
    ///   - savePromptToFile: Whether to save debug files
    init(jobApps: [JobApp], resume: Resume?, savePromptToFile: Bool = false) {
        self.jobApps = jobApps
        self.resume = resume
        self.savePromptToFile = savePromptToFile

        // Get API key from UserDefaults directly to avoid conflict with @Observable
        let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"

        // Create client using our factory
        openAIClient = OpenAIClientFactory.createClient(apiKey: apiKey)
    }

    // MARK: - API Call Functions

    /// Fetches job recommendation using the abstraction layer
    /// - Returns: A tuple containing the recommended job ID and reason
    func fetchRecommendation() async throws -> (UUID, String) {
        guard let resume = resume, let resumeModel = resume.model else {
            throw NSError(domain: "JobRecommendationProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "No resume available"])
        }

        let newJobApps = jobApps.filter { $0.status == .new }
        if newJobApps.isEmpty {
            throw NSError(domain: "JobRecommendationProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "No new job applications available"])
        }

        let prompt = buildPrompt(newJobApps: newJobApps, resume: resume)

        if savePromptToFile {
            savePromptToDownloads(content: prompt, fileName: "jobRecommendationPrompt.txt")
        }

        // Use our generic message format with the abstraction layer
        let messages = [
            genericSystemMessage,
            ChatMessage(role: .user, content: prompt),
        ]

        // Get the model string
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        do {
            // Check if we're using the MacPaw client
            if let macPawClient = openAIClient as? MacPawOpenAIClient {
                // Convert our messages to MacPaw's format
                let chatMessages = messages.compactMap { macPawClient.convertMessage($0) }

                // Create the query with structured output format
                let query = ChatQuery(
                    messages: chatMessages,
                    model: modelString,
                    responseFormat: .jsonSchema(name: "job-recommendation", type: JobRecommendation.self),
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
                        domain: "JobRecommendationProvider",
                        code: 1002,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to get structured output content"]
                    )
                }

                do {
                    let structuredOutput = try JSONDecoder().decode(JobRecommendation.self, from: data)
                    // Process the structured output
                    guard let uuid = UUID(uuidString: structuredOutput.recommendedJobId) else {
                        throw NSError(
                            domain: "JobRecommendationProvider",
                            code: 5,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Invalid UUID format in response: \(structuredOutput.recommendedJobId)",
                            ]
                        )
                    }

                    // Look for the job with this UUID
                    if let _ = jobApps.first(where: { $0.id == uuid }) {
                        return (uuid, structuredOutput.reason)
                    } else {
                        // Log all job IDs for debugging
                        let availableIds = jobApps.map { $0.id.uuidString }

                        throw NSError(
                            domain: "JobRecommendationProvider",
                            code: 6,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Job with ID \(uuid.uuidString) not found in job applications",
                            ]
                        )
                    }
                } catch {
                    throw NSError(
                        domain: "JobRecommendationProvider",
                        code: 1003,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to decode structured output: \(error.localizedDescription)"]
                    )
                }
            } else {
                // Fallback to the old method for non-MacPaw clients
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
            throw error
        }
    }

    // MARK: - Helper Functions

    private func buildPrompt(newJobApps: [JobApp], resume: Resume) -> String {
        let resumeText = resume.model?.renderedResumeText ?? ""

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

        static let example: Self = .init(
            recommendedJobId: "00000000-0000-0000-0000-000000000000",
            reason: "This job aligns with the candidate's experience in software development and interests in AI"
        )
    }

    private func decodeRecommendation(from responseText: String) throws -> (UUID, String) {
        // Save complete response for debugging
        if savePromptToFile {
            savePromptToDownloads(content: responseText, fileName: "jobRecommendationResponse.txt")
        }

        // Try to parse the JSON response
        guard let data = responseText.data(using: .utf8) else {
            throw NSError(domain: "JobRecommendationProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not convert response to data"])
        }

        // Decode the recommendation
        let recommendation: JobRecommendation
        do {
            recommendation = try JSONDecoder().decode(JobRecommendation.self, from: data)
        } catch {
            if savePromptToFile {
                savePromptToDownloads(content: "JSON decode error: \(error)\nJSON: \(responseText)", fileName: "jsonError.txt")
            }
            throw NSError(
                domain: "JobRecommendationProvider",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to decode JSON response",
                ]
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

        // Log all job IDs for debugging
        let availableIds = jobApps.map { $0.id.uuidString }

        throw NSError(
            domain: "JobRecommendationProvider",
            code: 6,
            userInfo: [
                NSLocalizedDescriptionKey: "Job with ID \(uuid.uuidString) not found in job applications",
            ]
        )
    }

    /// Saves the provided prompt text to the user's `Downloads` folder for debugging purposes.
    private func savePromptToDownloads(content: String, fileName: String) {
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        let fileURL = downloadsURL.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {}
    }
}
