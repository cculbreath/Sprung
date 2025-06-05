//
//  JobRecommendationService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/4/25.
//

import Foundation

/// Service for job recommendation using the unified LLM architecture
/// Replaces JobRecommendationProvider with cleaner LLMService integration
@MainActor
class JobRecommendationService {
    
    // MARK: - Dependencies
    private let llmService: LLMService
    
    // MARK: - Configuration
    private let systemPrompt = """
    You are an expert career advisor specializing in job application prioritization. Your task is to analyze a list of job applications and recommend the one that best matches the candidate's qualifications and career goals. You will be provided with job descriptions, the candidate's resume, and additional background information. Choose the job that offers the best match in terms of skills, experience, and potential career growth.

    IMPORTANT: Your response must be a valid JSON object conforming to the JSON schema provided. The recommendedJobId field must contain the exact UUID string from the id field of the chosen job in the job listings JSON array. Do not modify the UUID format in any way.

    IMPORTANT: Output ONLY the JSON object with the fields "recommendedJobId" and "reason". Do not include any additional commentary, explanation, or text outside the JSON.
    """
    
    init(llmService: LLMService = LLMService.shared) {
        self.llmService = llmService
    }
    
    // MARK: - Public Interface
    
    /// Fetch job recommendation using LLMService
    /// - Parameters:
    ///   - jobApps: Array of job applications to consider
    ///   - resume: The candidate's resume
    ///   - modelId: The model to use for recommendation
    /// - Returns: Tuple containing recommended job ID and reason
    func fetchRecommendation(
        jobApps: [JobApp],
        resume: Resume,
        modelId: String
    ) async throws -> (UUID, String) {
        
        // Validate inputs
        guard resume.model != nil else {
            throw JobRecommendationError.noResumeAvailable
        }
        
        let newJobApps = jobApps.filter { $0.status == .new }
        guard !newJobApps.isEmpty else {
            throw JobRecommendationError.noNewJobApplications
        }
        
        // Validate model capabilities
        try llmService.validateModel(modelId: modelId, for: [])
        
        // Build the recommendation prompt
        let prompt = buildPrompt(newJobApps: newJobApps, resume: resume)
        
        // Debug logging if enabled
        if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
            saveDebugPrompt(content: prompt, fileName: "jobRecommendationPrompt.txt")
        }
        
        Logger.debug("🎯 Requesting job recommendation with \(newJobApps.count) new jobs")
        
        // Execute structured request
        let recommendation = try await llmService.executeStructured(
            prompt: "\(systemPrompt)\n\n\(prompt)",
            modelId: modelId,
            responseType: JobRecommendation.self
        )
        
        // Validate response
        guard recommendation.validate() else {
            throw JobRecommendationError.invalidResponse("Failed validation")
        }
        
        guard let uuid = UUID(uuidString: recommendation.recommendedJobId) else {
            throw JobRecommendationError.invalidUUID(recommendation.recommendedJobId)
        }
        
        Logger.debug("✅ Job recommendation successful: \(recommendation.recommendedJobId)")
        return (uuid, recommendation.reason)
    }
    
    // MARK: - Private Helpers
    
    /// Build the recommendation prompt with job listings and resume data
    private func buildPrompt(newJobApps: [JobApp], resume: Resume) -> String {
        let resumeText = resume.textRes.isEmpty ? 
            resume.model?.renderedResumeText ?? "" : 
            resume.textRes
        
        // Build background documentation
        let backgroundDocs = buildBackgroundDocs(from: resume)
        
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

        RESPONSE REQUIREMENTS:
        - You MUST respond with a valid JSON object containing exactly these fields:
          "recommendedJobId": The exact UUID string from the 'id' field of the best matching job
          "reason": A brief explanation of why this job is the best match

        - The recommendedJobId MUST be copied exactly from the job listing, character-for-character
        - Do not include any text, comments, or explanations outside the JSON object
        - Your entire response must be a valid JSON structure

        Example response format:
        {
          "recommendedJobId": "00000000-0000-0000-0000-000000000000",
          "reason": "This job aligns with the candidate's experience in..."
        }
        """
        
        return prompt
    }
    
    /// Build background documentation from resume sources
    private func buildBackgroundDocs(from resume: Resume) -> String {
        let enabledSources = resume.enabledSources
        if enabledSources.isEmpty {
            return ""
        } else {
            return enabledSources.map { $0.name + ":\n" + $0.content + "\n\n" }.joined()
        }
    }
    
    /// Save debug prompt to file if debug mode is enabled
    private func saveDebugPrompt(content: String, fileName: String) {
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            Logger.debug("💾 Saved debug file: \(fileName)")
        } catch {
            Logger.warning("⚠️ Failed to save debug file \(fileName): \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Types

/// Errors specific to job recommendation service
enum JobRecommendationError: LocalizedError {
    case noResumeAvailable
    case noNewJobApplications
    case invalidResponse(String)
    case invalidUUID(String)
    
    var errorDescription: String? {
        switch self {
        case .noResumeAvailable:
            return "No resume available"
        case .noNewJobApplications:
            return "No new job applications available"
        case .invalidResponse(let details):
            return "Invalid recommendation format: \(details)"
        case .invalidUUID(let uuid):
            return "Invalid UUID format in response: \(uuid)"
        }
    }
}

/// Job recommendation response structure (reusing existing type from JobRecommendationProvider)
struct JobRecommendation: Codable, StructuredOutput {
    let recommendedJobId: String
    let reason: String
    
    /// Validate that the recommendedJobId is a valid UUID
    func validate() -> Bool {
        return UUID(uuidString: recommendedJobId) != nil
    }
}