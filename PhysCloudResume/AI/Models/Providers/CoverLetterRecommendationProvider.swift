//
//  CoverLetterRecommendationProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/21/25.
//  Updated by Christopher Culbreath on 5/20/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Provider for selecting the best cover letter among existing ones
@Observable
final class CoverLetterRecommendationProvider: BaseLLMProvider {
    /// System prompt for cover letter evaluation
    let systemPrompt = """
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

    # Examples

    **Example Input:**
    - Job Details: [Details about the job]
    - Candidate's Writing Samples: [Sample 1, Sample 2]
    - Cover Letter Options: [Letter ID: 550e8400-e29b-41d4-a716-446655440000, Letter ID: 650e8400-e29b-41d4-a716-446655440001, Letter ID: 750e8400-e29b-41d4-a716-446655440002]

    **Example Output:**
    ```json
    {
    "strengthAndVoiceAnalysis": "Letter 550e8400-e29b-41d4-a716-446655440000 is strong in voice but lacks style. Letter 650e8400-e29b-41d4-a716-446655440001 mirrors the candidate's voice best while maintaining a professional style. Letter 750e8400-e29b-41d4-a716-446655440002 is coherent but less engaging.",
    "bestLetterUuid": "650e8400-e29b-41d4-a716-446655440001",
    "verdict": "Letter 650e8400-e29b-41d4-a716-446655440001 is selected as it aligns closely with the candidate's unique voice and effectively addresses the job requirements."
    }
    ```

    # Notes

    - Prioritize authentic representation of the candidate's voice while maintaining professional standards.
    - If multiple letters meet the criteria equally, select the one with the most precise alignment to job requirements.
    """

    private let jobApp: JobApp
    private let writingSamples: String
    
    /// Optional model override for multi-model voting
    public var overrideModel: String?

    /// Writes debug information to a file in the Downloads folder
    /// - Parameter content: The content to write
    private func writeDebugToFile(_ content: String) {
        // Only save if debug file saving is enabled in UserDefaults
        guard UserDefaults.standard.bool(forKey: "saveDebugPrompts") else {
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "cover-letter-prompt-debug-\(timestamp).txt"
        
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        let fileURL = downloadsURL.appendingPathComponent(filename)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            Logger.debug("Saved debug file: \(filename)")
        } catch {
            Logger.warning("Failed to save debug file \(filename): \(error.localizedDescription)")
        }
    }

    /// Initialize with app state to create appropriate client
    /// - Parameters:
    ///   - appState: The application state
    ///   - jobApp: The job application containing cover letters
    ///   - writingSamples: Writing samples for style reference
    init(appState: AppState, jobApp: JobApp, writingSamples: String) {
        self.jobApp = jobApp
        self.writingSamples = writingSamples
        super.init(appState: appState)
    }

    /// Initialize with a specific LLM client
    /// - Parameters:
    ///   - client: An LLM client conforming to AppLLMClientProtocol
    ///   - jobApp: The job application containing cover letters
    ///   - writingSamples: Writing samples for style reference
    init(client: AppLLMClientProtocol, jobApp: JobApp, writingSamples: String) {
        self.jobApp = jobApp
        self.writingSamples = writingSamples
        super.init(client: client)
    }


    /// Fetch the best cover letter
    /// - Returns: The response containing the best cover letter UUID and reasoning
    func fetchBestCoverLetter() async throws -> BestCoverLetterResponse {
        let letters = jobApp.coverLetters
        guard letters.count > 1 else {
            throw NSError(domain: "CoverLetterRecommendationProvider", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "At least two cover letters are required"])
        }
        let applicant = await MainActor.run { Applicant() }
        var prompt = "\(applicant.name) is applying for this job: \(jobApp.jobPosition) at \(jobApp.companyName).\n\n"
        prompt += "Here are several cover letter options identified by their IDs:\n"
        var letterBundle = ""
        
        // Only use UUIDs - no names or labels that could reveal generation status
        for letter in letters {
            letterBundle += "Letter ID: \(letter.id.uuidString)\nContent:\n\(letter.content)\n\n"
        }
        Logger.debug("================ letter bundle!!")
        Logger.debug(letterBundle)
        prompt += letterBundle
        prompt += "\n\n==================================================\n\n"
        prompt += "**For reference here are some of \(applicant.name)'s previous cover letters that he's particularly satisfied with:\n**"
        prompt += "\(writingSamples)\n\n"
        prompt += "Which of the cover letters is strongest? Which cover letter best matches the style, voice and quality of \(applicant.name)'s previous letters? For your response, please return a brief summary ranking/assessment of each letter's relative strength and the degree to which it captures the author's voice and style, determine the one letter that is the strongest and most convincingly in the author's voice, and a brief reason for your ultimate choice."
        prompt += "\nWhen providing the strengthAndVoiceAnalysis and verdict responses, reference each letter by its ID.\n"
        prompt += "\nYou MUST return a JSON object with exactly these fields:\n"
        prompt += "{\n"
        prompt += "  \"strengthAndVoiceAnalysis\": \"Brief summary ranking/assessment of each letter's strength and voice\",\n"
        prompt += "  \"bestLetterUuid\": \"The exact UUID string of the selected best cover letter (must be one of the IDs provided above)\",\n"
        prompt += "  \"verdict\": \"Reason for the ultimate choice\"\n"
        prompt += "}\n"

        // DEBUG: Write the full prompt to a file in Downloads
        Logger.debug("[DEBUG] Writing cover letter recommendation prompt to Downloads folder")
        let fullPromptDebug = "SYSTEM PROMPT:\n\n\(systemPrompt)\n\nUSER PROMPT:\n\n\(prompt)\n\nJOB DESCRIPTION:\n\n\(jobApp.jobDescription)"
        writeDebugToFile(fullPromptDebug)

        // Initialize a conversation with the system prompt and user prompt
        initializeConversation(systemPrompt: systemPrompt, userPrompt: prompt)

        // Get model identifier - use override if provided
        let modelIdentifier = overrideModel ?? OpenAIModelFetcher.getPreferredModelString()

        // Ensure we have an appState for client creation
        if self.appState == nil {
            // Create a temporary app state if we don't have one
            self.appState = AppState()
            self.appState?.settings.preferredLLMProvider = AIModels.providerFor(modelName: modelIdentifier)
        }

        do {
            // Create query for structured output
            let query = AppLLMQuery(
                messages: conversationHistory,
                modelIdentifier: modelIdentifier,
                responseType: BestCoverLetterResponse.self
            )
            
            // Execute query using executeQueryWithTimeout which will update the client as needed
            let response = try await executeQueryWithTimeout(query)
            
            // Process structured response using BaseLLMProvider's method
            return try processStructuredResponse(response, as: BestCoverLetterResponse.self)
        } catch {
            // Log error and rethrow
            let generalErrorDebug = "\n\nGENERAL API ERROR:\n\(error.localizedDescription)"
            writeDebugToFile(fullPromptDebug + generalErrorDebug)
            errorMessage = error.localizedDescription
            throw error
        }
    }
}

