//
//  JobRecommendationProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/20/25.
//

import Foundation
import SwiftOpenAI // Will be removed later in the migration
import SwiftUI

@Observable class JobRecommendationProvider {
    // MARK: - Properties

    /// Set this to `true` if you want to save a debug file containing the prompt text.
    var saveDebugPrompt: Bool = false
    
    // The system message in SwiftOpenAI format (for backward compatibility)
    let systemMessage = ChatCompletionParameters.Message(
        role: .system,
        content: .text("""
        You are an expert career advisor specializing in job application prioritization. Your task is to analyze a list of job applications and recommend the one that best matches the candidate's qualifications and career goals. You will be provided with job descriptions, the candidate's resume, and additional background information. Choose the job that offers the best match in terms of skills, experience, and potential career growth.

        IMPORTANT: Your response must be a valid JSON object conforming to the JSON schema provided. The recommendedJobId field must contain the exact UUID string from the id field of the chosen job in the job listings JSON array. Do not modify the UUID format in any way.
        """)
    )
    
    // The system message in generic format (for abstraction layer)
    let genericSystemMessage = ChatMessage(
        role: .system,
        content: """
        You are an expert career advisor specializing in job application prioritization. Your task is to analyze a list of job applications and recommend the one that best matches the candidate's qualifications and career goals. You will be provided with job descriptions, the candidate's resume, and additional background information. Choose the job that offers the best match in terms of skills, experience, and potential career growth.

        IMPORTANT: Your response must be a valid JSON object conforming to the JSON schema provided. The recommendedJobId field must contain the exact UUID string from the id field of the chosen job in the job listings JSON array. Do not modify the UUID format in any way.
        """
    )

    // For backward compatibility during migration
    private let service: OpenAIService?
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
        self.openAIClient = client
        self.service = nil
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

        // For backward compatibility
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 360 // 360 seconds extended timeout

        self.service = OpenAIServiceFactory.service(
            apiKey: apiKey,
            configuration: configuration,
            debugEnabled: false
        )
        
        // Create client using our factory
        self.openAIClient = OpenAIClientFactory.createClient(apiKey: apiKey)
    }

    // MARK: - API Call Functions
    
    /// Fetches job recommendation using the abstraction layer directly
    /// - Returns: A tuple containing the recommended job ID and reason
    func fetchRecommendationWithGenericClient() async throws -> (UUID, String) {
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
            ChatMessage(role: .user, content: prompt)
        ]
        
        // Get the model string
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        
        do {
            // Make the API call using our abstraction layer
            let response = try await openAIClient.sendChatCompletionAsync(
                messages: messages,
                model: modelString,
                temperature: 0.2 // Lower temperature for more deterministic results with structured outputs
            )
            
            // Process the response
            let decodedResponse = try decodeRecommendation(from: response.content)
            return decodedResponse
        } catch {
            print("Error fetching recommendation with generic client: \(error.localizedDescription)")
            throw error
        }
    }

    /// Legacy method that uses SwiftOpenAI directly
    func fetchRecommendation() async throws -> (UUID, String) {
        // If we have our abstraction layer set up but no service, use the generic client
        if service == nil {
            return try await fetchRecommendationWithGenericClient()
        }
        
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
        
        // For backward compatibility
        guard let service = service else {
            return try await fetchRecommendationWithGenericClient()
        }

        let preferredModel = OpenAIModelFetcher.getPreferredModel()

        let messages = [
            systemMessage,
            ChatCompletionParameters.Message(role: .user, content: .text(prompt)),
        ]

        // Create a JSON schema for the recommended job response
        let recommendationSchema = JSONSchemaResponseFormat(
            name: "job_recommendation_response",
            strict: true,
            schema: JSONSchema(
                type: .object,
                properties: [
                    "recommendedJobId": JSONSchema(
                        type: .string,
                        description: "The exact UUID string from the id field of the recommended job"
                    ),
                    "reason": JSONSchema(
                        type: .string,
                        description: "A brief explanation of why this job is recommended"
                    ),
                ],
                required: ["recommendedJobId", "reason"],
                additionalProperties: false
            )
        )

        // Set response format to use the JSON schema
        let parameters = ChatCompletionParameters(
            messages: messages,
            model: preferredModel,
            responseFormat: .jsonSchema(recommendationSchema)
        )

        do {
            let result = try await service.startChat(parameters: parameters)
            guard let choices = result.choices,
                  let choice = choices.first,
                  let message = choice.message,
                  let content = message.content
            else {
                throw NSError(domain: "JobRecommendationProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
            }

            let decodedResponse = try decodeRecommendation(from: content)
            return decodedResponse
        } catch {
            print("Error fetching recommendation: \(error.localizedDescription)")
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

    private func decodeRecommendation(from responseText: String) throws -> (UUID, String) {
        struct Recommendation: Decodable {
            let recommendedJobId: String
            let reason: String
        }

        // Save complete response for debugging
        if savePromptToFile {
            savePromptToDownloads(content: responseText, fileName: "jobRecommendationResponse.txt")
        }

        // With JSONSchemaResponseFormat, the response should already be valid JSON
        guard let data = responseText.data(using: .utf8) else {
            throw NSError(domain: "JobRecommendationProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not convert response to data"])
        }

        // Decode the recommendation
        let recommendation: Recommendation
        do {
            recommendation = try JSONDecoder().decode(Recommendation.self, from: data)
        } catch {
            print("JSON decode error: \(error.localizedDescription)")
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

        print("Received recommendedJobId: \(recommendation.recommendedJobId)")

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
        print("Available job IDs: \(availableIds)")
        print("Looking for ID: \(uuid)")

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
            print("Prompt saved to \(fileURL.path)")
        } catch {
            print("Error writing prompt to file: \(error.localizedDescription)")
        }
    }
}
