//
//  JobRecommendationProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/20/25.
//  Updated by OpenAI Assistant on 5/XX/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

@Observable class JobRecommendationProvider {
    // MARK: - Properties

    // The system prompt for job recommendation
    let systemPrompt = """
    You are an expert career advisor specializing in job application prioritization. Your task is to analyze a list of job applications and       recommend the one that best matches the candidate's qualifications and career goals. You will be provided with job descriptions, the candidate's   resume, and additional background information. Choose the job that offers the best match in terms of skills, experience, and potential career      growth.

    IMPORTANT: Your response must be a valid JSON object conforming to the JSON schema provided. The recommendedJobId field must contain the exact UUID string from the id field of the chosen job in the job listings JSON array. Do not modify the UUID format in any way.

    IMPORTANT: Output ONLY the JSON object with the fields "recommendedJobId" and "reason". Do not include any additional commentary, explanation, or text outside the JSON.
    """
    // The unified AppLLM client
    private let appLLMClient: AppLLMClientProtocol

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

    /// Initialize with app state to create appropriate client
    /// - Parameters:
    ///   - appState: The application state
    ///   - jobApps: List of job applications
    ///   - resume: The resume to use
    init(appState: AppState, jobApps: [JobApp], resume: Resume?) {
        let modelIdentifier = OpenAIModelFetcher.getPreferredModelString()
        let providerType = AIModels.providerForModel(modelIdentifier)
        self.appLLMClient = AppLLMClientFactory.createClient(for: providerType, appState: appState)
        self.jobApps = jobApps
        self.resume = resume
    }

    /// Direct initializer with OpenAI client
    /// - Parameters:
    ///   - client: An OpenAI client conforming to OpenAIClientProtocol
    ///   - jobApps: List of job applications
    ///   - resume: The resume to use
    convenience init(client: OpenAIClientProtocol, jobApps: [JobApp], resume: Resume?) {
        // Create an app state and delegate to the designated initializer
        let appState = AppState()
        self.init(appState: appState, jobApps: jobApps, resume: resume)
    }

    /// Writes debug content to a file in the Downloads folder if enabled
    /// - Parameters:
    ///   - content: The content to write
    ///   - fileName: The name of the file to write
    private func saveMessageToDebugFile(content: String, fileName: String) {
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

    // MARK: - API Call

    /// Fetches job recommendation using the abstraction layer
    /// - Returns: A tuple containing the recommended job ID and reason
    func fetchRecommendation() async throws -> (UUID, String) {
        guard let resume = resume, let _ = resume.model else {
            throw NSError(domain: "JobRecommendationProvider", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "No resume available"])
        }

        let newJobApps = jobApps.filter { $0.status == .new }
        if newJobApps.isEmpty {
            throw NSError(domain: "JobRecommendationProvider", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "No new job applications available"])
        }

        let prompt = buildPrompt(newJobApps: newJobApps, resume: resume)
        if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
            saveMessageToDebugFile(content: prompt, fileName: "jobRecommendationPrompt.txt")
        }

        let messages: [AppLLMMessage] = [
            AppLLMMessage(role: .system, text: systemPrompt),
            AppLLMMessage(role: .user, text: prompt)
        ]

        let modelIdentifier = OpenAIModelFetcher.getPreferredModelString()
        Logger.info("Using model: \(modelIdentifier) for job recommendation")

        let query = AppLLMQuery(
            messages: messages,
            modelIdentifier: modelIdentifier,
            responseType: JobRecommendation.self
        )

        let response = try await appLLMClient.executeQuery(query)
        let decoder = JSONDecoder()
        switch response {
        case .structured(let data):
            let recommendation = try decoder.decode(JobRecommendation.self, from: data)
            guard let uuid = UUID(uuidString: recommendation.recommendedJobId) else {
                throw NSError(domain: "JobRecommendationProvider", code: 5,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid UUID format in response: \(recommendation.recommendedJobId)"])
            }
            return (uuid, recommendation.reason)
        case .text(let text):
            if let data = text.data(using: .utf8) {
                let recommendation = try decoder.decode(JobRecommendation.self, from: data)
                guard let uuid = UUID(uuidString: recommendation.recommendedJobId) else {
                    throw NSError(domain: "JobRecommendationProvider", code: 5,
                                 userInfo: [NSLocalizedDescriptionKey: "Invalid UUID format in response: \(recommendation.recommendedJobId)"])
                }
                return (uuid, recommendation.reason)
            } else {
                throw AppLLMError.unexpectedResponseFormat
            }
        }
    }

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
}
