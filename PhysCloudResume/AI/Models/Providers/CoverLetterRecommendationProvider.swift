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
final class CoverLetterRecommendationProvider {
    /// System prompt for FPTP cover letter evaluation
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

    // MARK: - Properties
    
    /// The base LLM provider with OpenRouter client
    private let baseLLMProvider: BaseLLMProvider
    
    /// The model ID to use for requests
    private let modelId: String
    
    private let jobApp: JobApp
    private let writingSamples: String
    
    /// Optional model override for multi-model voting
    public var overrideModel: String?
    
    /// Optional voting scheme override
    public var votingScheme: VotingScheme = .firstPastThePost
    
    /// System prompt for score voting evaluation
    let scoreVotingSystemPrompt = """
    You are an expert career advisor and professional writer specializing in evaluating cover letters. Your task is to analyze a list of cover letters for a specific job application and allocate 20 points among them based on their quality and likelihood of securing an interview. You will be provided with job details, several cover letter drafts, and writing samples that represent the candidate's preferred style.

    Your evaluation should consider the following criteria:
    - Voice: How well does the letter reflect the candidate's authentic self?
    - Style: Does the style align with the candidate's writing samples and preferences?
    - Quality: Assess the grammar, coherence, impact, and relevancy of the content towards the job description.

    # Scoring Rules

    1. You have EXACTLY 20 points total to distribute
    2. Each letter can receive between 0 and 20 points
    3. You may give all 20 points to one exceptional letter (and 0 to all others)
    4. You may distribute points among multiple letters (e.g., 10, 7, 3, 0, 0)
    5. You may distribute evenly if letters are similar quality (e.g., 4, 4, 4, 4, 4)
    6. No letter can receive negative points or fractional points
    7. The sum of ALL points across ALL letters MUST equal EXACTLY 20
    
    CRITICAL: If you allocate 15 points to one letter, you have only 5 points left for ALL other letters combined

    # Output Format

    Output the assessment as a JSON object structured as follows:
    ```json
    {
    "strengthAndVoiceAnalysis": "Brief summary ranking/assessment of each letter's strength and voice",
    "bestLetterUuid": "UUID of the letter with the highest score",
    "verdict": "Overall assessment and reason for the score distribution",
    "scoreAllocations": [
        {
            "letterUuid": "UUID of the letter",
            "score": 8,
            "reasoning": "Brief explanation for this score"
        },
        {
            "letterUuid": "UUID of another letter",
            "score": 7,
            "reasoning": "Brief explanation for this score"
        },
        {
            "letterUuid": "UUID of another letter",
            "score": 5,
            "reasoning": "Brief explanation for this score"
        }
    ]
    }
    ```

    # Notes

    - Ensure the sum of all scores equals exactly 20
    - Provide clear reasoning for each score allocation
    - The bestLetterUuid should be the letter with the highest allocated score
    """

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

    /// Initialize with app state and model ID
    /// - Parameters:
    ///   - appState: The application state
    ///   - jobApp: The job application containing cover letters
    ///   - writingSamples: Writing samples for style reference
    ///   - modelId: The OpenRouter model ID to use
    init(appState: AppState, jobApp: JobApp, writingSamples: String, modelId: String) {
        self.baseLLMProvider = BaseLLMProvider(appState: appState)
        self.modelId = modelId
        self.jobApp = jobApp
        self.writingSamples = writingSamples
        
        // Log which model we're using
        Logger.debug("🚀 CoverLetterRecommendationProvider initialized with OpenRouter model: \(modelId)")
    }


    /// Fetch the best cover letter
    /// - Returns: The response containing the best cover letter UUID and reasoning
    func fetchBestCoverLetter() async throws -> BestCoverLetterResponse {
        // Filter out empty/ungenerated letters
        let letters = jobApp.coverLetters.filter { letter in
            // Must have content AND be generated
            return letter.generated && !letter.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard letters.count > 1 else {
            throw NSError(domain: "CoverLetterRecommendationProvider", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "At least two generated cover letters with content are required"])
        }
        let applicant = await MainActor.run { Applicant() }
        var prompt = "\(applicant.name) is applying for this job: \(jobApp.jobPosition) at \(jobApp.companyName).\n\n"
        prompt += "Here are several cover letter options identified by their IDs:\n"
        var letterBundle = ""
        
        // Only use UUIDs - no names or labels that could reveal generation status
        for letter in letters {
            // Extra safety check - should never happen now due to filter above
            guard letter.generated && !letter.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Logger.debug("⚠️ WARNING: Ungenerated/empty letter passed filter! ID: \(letter.id.uuidString), generated: \(letter.generated)")
                continue
            }
            letterBundle += "Letter ID: \(letter.id.uuidString)\nContent:\n\(letter.content)\n\n"
        }
        Logger.debug("================ letter bundle!!")
        Logger.debug(letterBundle)
        prompt += letterBundle
        prompt += "\n\n==================================================\n\n"
        prompt += "**For reference here are some of \(applicant.name)'s previous cover letters that he's particularly satisfied with:\n**"
        prompt += "\(writingSamples)\n\n"
        
        // Choose system prompt and adjust user prompt based on voting scheme
        let selectedSystemPrompt: String
        if votingScheme == .scoreVoting {
            selectedSystemPrompt = scoreVotingSystemPrompt
            prompt += "Please evaluate the \(letters.count) cover letters presented above and allocate EXACTLY 20 points total among them. "
            prompt += "You may give all 20 points to the single best letter (scoring others 0), or distribute the 20 points among multiple letters. "
            prompt += "The letter that best matches the style, voice and quality of \(applicant.name)'s previous letters should receive the most points. "
            prompt += "Remember: The sum of all your allocated points MUST equal 20, no more, no less.\n"
            prompt += "\nWhen providing the strengthAndVoiceAnalysis and verdict responses, reference each letter by its ID.\n"
            prompt += "\nYou MUST return a JSON object with exactly these fields:\n"
            prompt += "{\n"
            prompt += "  \"strengthAndVoiceAnalysis\": \"Brief summary ranking/assessment of each letter's strength and voice\",\n"
            prompt += "  \"bestLetterUuid\": \"The exact UUID string of the letter with the highest score\",\n"
            prompt += "  \"verdict\": \"Overall assessment and reason for the score distribution\",\n"
            prompt += "  \"scoreAllocations\": [\n"
            for (index, letter) in letters.enumerated() {
                let comma = index < letters.count - 1 ? "," : ""
                prompt += "    { \"letterUuid\": \"\(letter.id.uuidString)\", \"score\": <points>, \"reasoning\": \"<explanation>\" }\(comma)\n"
            }
            prompt += "  ]\n"
            prompt += "}\n"
            prompt += "\nCRITICAL REQUIREMENTS:\n"
            prompt += "- Each score must be a non-negative integer (0, 1, 2, ..., 20)\n"
            prompt += "- The sum of ALL scores across ALL letters must equal EXACTLY 20\n"
            prompt += "- Example valid distributions: [20,0,0], [10,10,0], [8,7,5], [4,4,4,4,4]\n"
            prompt += "- Example INVALID distributions: [10,5,3] (sum=18), [15,10,0] (sum=25)\n"
        } else {
            selectedSystemPrompt = systemPrompt
            prompt += "Which of the cover letters is strongest? Which cover letter best matches the style, voice and quality of \(applicant.name)'s previous letters? For your response, please return a brief summary ranking/assessment of each letter's relative strength and the degree to which it captures the author's voice and style, determine the one letter that is the strongest and most convincingly in the author's voice, and a brief reason for your ultimate choice."
            prompt += "\nWhen providing the strengthAndVoiceAnalysis and verdict responses, reference each letter by its ID.\n"
            prompt += "\nYou MUST return a JSON object with exactly these fields:\n"
            prompt += "{\n"
            prompt += "  \"strengthAndVoiceAnalysis\": \"Brief summary ranking/assessment of each letter's strength and voice\",\n"
            prompt += "  \"bestLetterUuid\": \"The exact UUID string of the selected best cover letter (must be one of the IDs provided above)\",\n"
            prompt += "  \"verdict\": \"Reason for the ultimate choice\"\n"
            prompt += "}\n"
        }

        // DEBUG: Write the full prompt to a file in Downloads
        Logger.debug("[DEBUG] Writing cover letter recommendation prompt to Downloads folder")
        let fullPromptDebug = "VOTING SCHEME: \(votingScheme.rawValue)\n\nSYSTEM PROMPT:\n\n\(selectedSystemPrompt)\n\nUSER PROMPT:\n\n\(prompt)\n\nJOB DESCRIPTION:\n\n\(jobApp.jobDescription)"
        writeDebugToFile(fullPromptDebug)

        // Get model identifier - use override if provided, or use the instance modelId
        let modelIdentifier = overrideModel ?? modelId

        // Create messages for the query
        let messages: [AppLLMMessage] = [
            AppLLMMessage(role: .system, text: selectedSystemPrompt),
            AppLLMMessage(role: .user, text: prompt)
        ]

        do {
            Logger.info("🎯 Executing cover letter recommendation with OpenRouter model: \(modelIdentifier)")
            
            // Create query for structured output
            let query = AppLLMQuery(
                messages: messages,
                modelIdentifier: modelIdentifier,
                responseType: BestCoverLetterResponse.self
            )
            
            // Execute query using baseLLMProvider
            let response = try await baseLLMProvider.executeQuery(query)
            
            // Process structured response using BaseLLMProvider's method
            return try baseLLMProvider.processStructuredResponse(response, as: BestCoverLetterResponse.self)
        } catch {
            // Log error and rethrow
            let generalErrorDebug = "\n\nGENERAL API ERROR:\n\(error.localizedDescription)"
            writeDebugToFile(fullPromptDebug + generalErrorDebug)
            Logger.error("Cover letter recommendation error: \(error.localizedDescription)")
            throw error
        }
    }
}

