//
//  BestCoverLetterService.swift
//  PhysCloudResume
//
//  Created by Claude on 6/5/25.
//

import Foundation

/// Service for best cover letter selection using the unified LLM architecture
/// Replaces single-model usage of CoverLetterRecommendationProvider with cleaner LLMService integration
@MainActor
class BestCoverLetterService {
    
    // MARK: - Dependencies
    private let llmService: LLMService
    
    // MARK: - Configuration
    private let systemPrompt = """
    You are an expert career advisor and professional writer specializing in evaluating cover letters. Your task is to analyze a list of cover letters for a specific job application and select the one which you believe has the best chance of securing the applicant an interview for this job opening. You will be provided with job details, several cover letter drafts, and writing samples that represent the candidate's preferred style.

    Your evaluation should consider the following criteria:
    - Voice: How well does the letter reflect the candidate's authentic self?
    - Style: Does the style align with the candidate's writing samples and preferences?
    - Quality: Assess the grammar, coherence, impact, and relevancy of the content towards the job description.

    # Steps

    1. Review the provided job details and understand the requirements of the position.
    2. Analyze the writing samples to identify the candidate's preferred style and voice.
    3. Evaluate each cover letter draft against the established criteria: voice, style, and quality.
    4. Compare your findings to determine which letter has the best chance of securing the applicant an interview for the job.

    # Output Format

    Output the assessment as a JSON object structured as follows:
    ```json
    {
    "strengthAndVoiceAnalysis": "Brief summary ranking/assessment of each letter's strength and voice",
    "bestLetterUuid": "UUID of the selected best cover letter",
    "verdict": "Reason for the ultimate choice"
    }
    ```

    IMPORTANT: The bestLetterUuid field must contain the exact UUID string from the cover letter you select. Do not modify the UUID format in any way. Output ONLY the JSON object with the specified fields.
    """
    
    init(llmService: LLMService) {
        self.llmService = llmService
    }
    
    // MARK: - Public Interface
    
    /// Select the best cover letter from available options
    /// - Parameters:
    ///   - jobApp: The job application containing cover letters to evaluate
    ///   - modelId: The model to use for selection
    /// - Returns: The best cover letter response with analysis
    func selectBestCoverLetter(
        jobApp: JobApp,
        modelId: String
    ) async throws -> BestCoverLetterResponse {
        
        // Get generated cover letters
        let coverLetters = jobApp.coverLetters.filter { $0.generated }
        guard coverLetters.count >= 2 else {
            throw BestCoverLetterError.notEnoughCoverLetters
        }
        
        // Validate model capabilities
        try llmService.validateModel(modelId: modelId, for: [.structuredOutput])
        
        // Build the selection prompt
        let prompt = buildPrompt(jobApp: jobApp, coverLetters: coverLetters)
        
        // Debug logging if enabled
        if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
            saveDebugPrompt(content: prompt, fileName: "bestCoverLetterPrompt.txt")
        }
        
        Logger.debug("🏆 Requesting best cover letter selection from \(coverLetters.count) letters")
        
        // Execute structured request
        let response = try await llmService.executeStructured(
            prompt: "\(systemPrompt)\n\n\(prompt)",
            modelId: modelId,
            responseType: BestCoverLetterResponse.self
        )
        
        // Validate response
        guard let uuid = UUID(uuidString: response.bestLetterUuid) else {
            throw BestCoverLetterError.invalidUUID(response.bestLetterUuid)
        }
        
        // Verify the selected UUID exists in the cover letters
        guard coverLetters.contains(where: { $0.id == uuid }) else {
            throw BestCoverLetterError.letterNotFound(response.bestLetterUuid)
        }
        
        Logger.debug("✅ Best cover letter selection successful: \(response.bestLetterUuid)")
        return response
    }
    
    // MARK: - Private Helpers
    
    /// Build the selection prompt with job details and cover letters
    private func buildPrompt(jobApp: JobApp, coverLetters: [CoverLetter]) -> String {
        var prompt = """
        **Job Details:**
        Company: \(jobApp.companyName)
        Position: \(jobApp.jobPosition)
        
        """
        
        // Add job description if available
        if !jobApp.jobListingString.isEmpty {
            prompt += """
            Job Description:
            \(jobApp.jobListingString)
            
            """
        }
        
        // Add writing samples from reference docs if available
        if let resume = jobApp.selectedRes {
            let writingSamples = resume.enabledSources
                .filter { !$0.content.isEmpty }
                .map { "\($0.name):\n\($0.content)" }
                .joined(separator: "\n\n")
            
            if !writingSamples.isEmpty {
                prompt += """
                **Writing Samples:**
                \(writingSamples)
                
                """
            }
        }
        
        // Add cover letters for evaluation
        prompt += "**Cover Letter Options:**\n"
        for (index, letter) in coverLetters.enumerated() {
            prompt += """
            
            Letter \(index + 1) (ID: \(letter.id.uuidString)):
            \(letter.content)
            
            """
        }
        
        prompt += """
        
        Please evaluate these cover letters and select the best one for this job application.
        """
        
        return prompt
    }
    
    /// Save debug prompt to Downloads folder
    private func saveDebugPrompt(content: String, fileName: String) {
        let fileManager = FileManager.default
        guard let downloadsURL = fileManager.urls(for: .downloadsDirectory, 
                                                  in: .userDomainMask).first else { return }
        
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - Error Types

enum BestCoverLetterError: LocalizedError {
    case notEnoughCoverLetters
    case invalidUUID(String)
    case letterNotFound(String)
    case modelValidationFailed
    
    var errorDescription: String? {
        switch self {
        case .notEnoughCoverLetters:
            return "At least 2 generated cover letters are required for selection"
        case .invalidUUID(let uuid):
            return "Invalid UUID format in response: \(uuid)"
        case .letterNotFound(let uuid):
            return "Selected cover letter UUID not found: \(uuid)"
        case .modelValidationFailed:
            return "Selected model does not support required capabilities"
        }
    }
}