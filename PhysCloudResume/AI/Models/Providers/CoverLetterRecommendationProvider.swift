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
final class CoverLetterRecommendationProvider {
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
    - Cover Letter Drafts: [Draft 1, Draft 2, Draft 3]

    **Example Output:**
    ```json
    {
    "strengthAndVoiceAnalysis": "Draft 1 is strong in voice but lacks style. Draft 2 mirrors the candidate's voice best while maintaining a professional style. Draft 3 is coherent but less engaging.",
    "bestLetterUuid": "UUID-of-Draft-2",
    "verdict": "Draft 2 is selected as it aligns closely with the candidate's unique voice and effectively addresses the job requirements."
    }
    ```

    # Notes

    - Prioritize authentic representation of the candidate's voice while maintaining professional standards.
    - If multiple letters meet the criteria equally, select the one with the most precise alignment to job requirements.
    """

    // The unified AppLLMClient
    private let appLLMClient: AppLLMClientProtocol

    private let jobApp: JobApp
    private let writingSamples: String

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
        // Get the preferred model identifier
        let modelId = OpenAIModelFetcher.getPreferredModelString()
        // Determine provider from model
        let providerType = AIModels.providerForModel(modelId)
        self.appLLMClient = AppLLMClientFactory.createClient(for: providerType, appState: appState)
        self.jobApp = jobApp
        self.writingSamples = writingSamples
    }
    
    /// Direct initializer with OpenAI client
    /// - Parameters:
    ///   - client: An OpenAI client conforming to OpenAIClientProtocol
    ///   - jobApp: The job application containing cover letters
    ///   - writingSamples: Writing samples for style reference
    init(client: OpenAIClientProtocol, jobApp: JobApp, writingSamples: String) {
        // Create appropriate adapter through the factory if possible
        if let appState = (NSApplication.shared.delegate as? AppDelegate)?.appState {
            self.appLLMClient = AppLLMClientFactory.createClient(for: AIModels.Provider.openai, appState: appState)
        } else {
            // Create a direct adapter with default settings
            let config = LLMProviderConfig.forOpenAI(apiKey: client.apiKey)
            self.appLLMClient = SwiftOpenAIAdapterForOpenAI(config: config, appState: AppState())
        }
        
        self.jobApp = jobApp
        self.writingSamples = writingSamples
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
        prompt += "Here are several cover letter options:\n"
        var letterBundle = ""
        for letter in letters {
            letterBundle += "id: \(letter.id.uuidString), name: \(letter.sequencedName), content:\n\(letter.content)\n\n"
        }
        Logger.debug("================ letter bundle!!")
        Logger.debug(letterBundle)
        prompt += letterBundle
        prompt += "\n\n==================================================\n\n"
        prompt += "**For reference here are some of \(applicant.name)'s previous cover letters that he's particularly satisfied with:\n**"
        prompt += "\(writingSamples)\n\n"
        prompt += "Which of the cover letters is strongest? Which cover letter best matches the style, voice and quality of \(applicant.name)'s previous letters? For your response, please return a brief summary ranking/assessment of each letter's relative strength and the degree to which it captures the author's voice and style, determine the one letter that is the strongest and most convincingly in the author's voice, and a brief reason for your ultimate choice."
        prompt += "\nWhen providing the strengthAndVoiceAnalysis and verdict responses, reference each letter by its name, not its id.\n"
        prompt += "\nYou MUST return a JSON object with exactly these fields:\n"
        prompt += "{\n"
        prompt += "  \"strengthAndVoiceAnalysis\": \"Brief summary ranking/assessment of each letter's strength and voice\",\n"
        prompt += "  \"bestLetterUuid\": \"UUID of the selected best cover letter\",\n"
        prompt += "  \"verdict\": \"Reason for the ultimate choice\"\n"
        prompt += "}\n"

        // DEBUG: Write the full prompt to a file in Downloads
        Logger.debug("[DEBUG] Writing cover letter recommendation prompt to Downloads folder")
        let fullPromptDebug = "SYSTEM PROMPT:\n\n\(systemPrompt)\n\nUSER PROMPT:\n\n\(prompt)\n\nJOB DESCRIPTION:\n\n\(jobApp.jobDescription)"
        writeDebugToFile(fullPromptDebug)

        // Create messages for the query
        let messages = [
            AppLLMMessage(role: .system, text: systemPrompt),
            AppLLMMessage(role: .user, text: prompt)
        ]

        // Get model identifier
        let modelIdentifier = OpenAIModelFetcher.getPreferredModelString()

        do {
            // Create query for structured output
            let query = AppLLMQuery(
                messages: messages,
                modelIdentifier: modelIdentifier,
                responseType: BestCoverLetterResponse.self
            )
            
            // Execute query
            let response = try await appLLMClient.executeQuery(query)
            
            // Create decoder
            let decoder = JSONDecoder()
            
            // Process response
            switch response {
            case .structured(let data):
                // Decode structured response
                do {
                    let bestCoverLetterResponse = try decoder.decode(BestCoverLetterResponse.self, from: data)
                    
                    // DEBUG: Append response to our debug file
                    let responseDebug = "\n\nAPI RESPONSE:\n\nPARSED STRUCTURED OUTPUT:\n\(bestCoverLetterResponse)"
                    writeDebugToFile(fullPromptDebug + responseDebug)
                    
                    return bestCoverLetterResponse
                } catch {
                    Logger.error("Decoding error: \(error.localizedDescription)")
                    // Try to log the raw data for debugging
                    if let jsonString = String(data: data, encoding: .utf8) {
                        Logger.error("Raw JSON: \(jsonString)")
                        writeDebugToFile(fullPromptDebug + "\n\nDECODING ERROR: \(error)\n\nRAW JSON: \(jsonString)")
                    }
                    throw error
                }
                
            case .text(let text):
                // Try to decode text as JSON
                if let data = text.data(using: .utf8) {
                    do {
                        let bestCoverLetterResponse = try decoder.decode(BestCoverLetterResponse.self, from: data)
                        
                        // DEBUG: Append response to our debug file
                        let responseDebug = "\n\nAPI RESPONSE (TEXT MODE):\n\nPARSED JSON:\n\(bestCoverLetterResponse)"
                        writeDebugToFile(fullPromptDebug + responseDebug)
                        
                        return bestCoverLetterResponse
                    } catch {
                        Logger.error("Text decoding error: \(error.localizedDescription)")
                        // Try to log the raw text for debugging
                        Logger.error("Raw text: \(text)")
                        writeDebugToFile(fullPromptDebug + "\n\nTEXT DECODING ERROR: \(error)\n\nRAW TEXT: \(text)")
                        
                        // Attempt to manually extract and construct the response
                        do {
                            // Try to extract the JSON portion from the text
                            if let jsonStartIndex = text.range(of: "{")?.lowerBound,
                               let jsonEndIndex = text.range(of: "}", options: .backwards)?.upperBound {
                                let jsonSubstring = text[jsonStartIndex..<jsonEndIndex]
                                let jsonString = String(jsonSubstring)
                                
                                Logger.debug("Extracted JSON: \(jsonString)")
                                
                                if let jsonData = jsonString.data(using: .utf8) {
                                    let extractedResponse = try decoder.decode(BestCoverLetterResponse.self, from: jsonData)
                                    
                                    // DEBUG: Append extracted response to our debug file
                                    let extractedDebug = "\n\nEXTRACTED JSON RESPONSE:\n\(extractedResponse)"
                                    writeDebugToFile(fullPromptDebug + extractedDebug)
                                    
                                    return extractedResponse
                                }
                            }
                        } catch {
                            Logger.error("Manual extraction also failed: \(error.localizedDescription)")
                            writeDebugToFile(fullPromptDebug + "\n\nMANUAL EXTRACTION FAILED: \(error)")
                        }
                        
                        throw AppLLMError.unexpectedResponseFormat
                    }
                } else {
                    throw AppLLMError.unexpectedResponseFormat
                }
            }
        } catch {
            let generalErrorDebug = "\n\nGENERAL API ERROR:\n\(error.localizedDescription)"
            writeDebugToFile(fullPromptDebug + generalErrorDebug)
            throw error
        }
    }
}

