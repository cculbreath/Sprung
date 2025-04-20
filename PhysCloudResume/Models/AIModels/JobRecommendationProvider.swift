//
//  JobRecommendationProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/20/25.
//

import Foundation
import SwiftOpenAI
import SwiftUI

@Observable class JobRecommendationProvider {
    // MARK: - Properties

    /// Set this to `true` if you want to save a debug file containing the prompt text.
    var saveDebugPrompt: Bool = false
    
    @AppStorage("openAiApiKey") private var openAiApiKey: String = "none"

    let systemMessage = ChatCompletionParameters.Message(
        role: .system,
        content: .text("""
        You are an expert career advisor specializing in job application prioritization. Your task is to analyze a list of job applications and recommend the one that best matches the candidate's qualifications and career goals. You will be provided with job descriptions, the candidate's resume, and additional background information. Choose the job that offers the best match in terms of skills, experience, and potential career growth.
        """)
    )

    private let service: OpenAIService
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

    init(jobApps: [JobApp], resume: Resume?, savePromptToFile: Bool = false) {
        self.jobApps = jobApps
        self.resume = resume
        self.savePromptToFile = savePromptToFile
        
        // Create service using the factory and API key from AppStorage
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 360 // 360 seconds extended timeout
        
        self.service = OpenAIServiceFactory.service(
            apiKey: openAiApiKey, 
            configuration: configuration,
            debugEnabled: false
        )
    }

    // MARK: - API Call Functions

    func fetchRecommendation() async throws -> (UUID, String) {
        guard let resume = resume, let model = resume.model else {
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

        let preferredModel = OpenAIModelFetcher.getPreferredModel()

        let messages = [
            systemMessage,
            ChatCompletionParameters.Message(role: .user, content: .text(prompt)),
        ]

        let parameters = ChatCompletionParameters(
            messages: messages,
            model: preferredModel,
            responseFormat: .text
        )

        do {
            let result = try await service.startChat(parameters: parameters)
            guard let choice = result.choices.first,
                  let content = choice.message.content
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

        var jobListings = ""
        for (index, app) in newJobApps.enumerated() {
            jobListings += """

            JOB #\(index + 1):
            ID: \(app.id)
            Position: \(app.jobPosition)
            Company: \(app.companyName)
            Location: \(app.jobLocation)
            Description:
            \(app.jobDescription)

            """
        }

        let prompt = """
        TASK:
        Analyze the candidate's resume, background information, and the list of new job applications. Recommend the ONE job that is the best match for the candidate's qualifications and career goals.

        CANDIDATE'S RESUME:
        \(resumeText)

        BACKGROUND INFORMATION:
        \(backgroundDocs)

        JOB LISTINGS:
        \(jobListings)

        RESPONSE INSTRUCTIONS:
        1. Evaluate each job against the candidate's skills, experience, and potential fit.
        2. Select the job that offers the best match.
        3. Provide your recommendation as a JSON object with the following structure:
           {
              "recommendedJobId": "the-uuid-of-recommended-job",
              "reason": "A brief explanation of why this job is recommended"
           }
        """

        return prompt
    }

    private func decodeRecommendation(from responseText: String) throws -> (UUID, String) {
        struct Recommendation: Decodable {
            let recommendedJobId: String
            let reason: String
        }

        // Extract JSON from the response if it's wrapped in ```json and ```
        let jsonPattern = #"```(?:json)?\s*(\{.*?\})\s*```"#
        let jsonRegex = try NSRegularExpression(pattern: jsonPattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(responseText.startIndex ..< responseText.endIndex, in: responseText)

        let jsonToUse: String
        if let match = jsonRegex.firstMatch(in: responseText, options: [], range: range),
           let matchRange = Range(match.range(at: 1), in: responseText)
        {
            jsonToUse = String(responseText[matchRange])
        } else {
            jsonToUse = responseText
        }

        let data = jsonToUse.data(using: .utf8)!
        let recommendation = try JSONDecoder().decode(Recommendation.self, from: data)

        guard let uuid = UUID(uuidString: recommendation.recommendedJobId) else {
            throw NSError(domain: "JobRecommendationProvider", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid UUID format in response"])
        }

        return (uuid, recommendation.reason)
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