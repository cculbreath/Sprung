 //
//  CoverLetterRecommendationProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/21/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Provider for selecting the best cover letter among existing ones using OpenAI JSON schema responses
final class CoverLetterRecommendationProvider {
    /// System prompt in generic format for abstraction layer
    let genericSystemMessage = ChatMessage(
        role: .system,
        content: """
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
        "strength-and-voice-analysis": "Brief summary ranking/assessment of each letter's strength and voice",
        "best-letter-uuid": "UUID of the selected best cover letter",
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
        "strength-and-voice-analysis": "Draft 1 is strong in voice but lacks style. Draft 2 mirrors the candidate's voice best while maintaining a professional style. Draft 3 is coherent but less engaging.",
        "best-letter-uuid": "UUID-of-Draft-2",
        "verdict": "Draft 2 is selected as it aligns closely with the candidate's unique voice and effectively addresses the job requirements."
        }
        ```

        # Notes

        - Prioritize authentic representation of the candidate's voice while maintaining professional standards.
        - If multiple letters meet the criteria equally, select the one with the most precise alignment to job requirements.
        """
    )

    // The new abstraction layer client
    private let openAIClient: OpenAIClientProtocol

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

    /// Response schema for best cover letter selection
    /// Note: This is now defined in APIResponses.swift for reusability
    typealias BestCoverLetterResponse = PhysCloudResume.BestCoverLetterResponse

    /// Initialize with our abstraction layer client
    /// - Parameters:
    ///   - client: An OpenAI client conforming to OpenAIClientProtocol
    ///   - jobApp: The job application containing cover letters
    ///   - writingSamples: Writing samples for style reference
    init(client: OpenAIClientProtocol, jobApp: JobApp, writingSamples: String) {
        openAIClient = client
        self.jobApp = jobApp
        self.writingSamples = writingSamples
    }

    /// Fetch the best cover letter using the abstraction layer
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
        prompt += "\nWhen providing the strength-and-voice-analysis and verdict responses, reference each letter by its name, not its id.\n"
        prompt += "\nYou MUST return a JSON object with exactly these fields:\n"
        prompt += "{\n"
        prompt += "  \"strength-and-voice-analysis\": \"Brief summary ranking/assessment of each letter's strength and voice\",\n"
        prompt += "  \"best-letter-uuid\": \"UUID of the selected best cover letter\",\n"
        prompt += "  \"verdict\": \"Reason for the ultimate choice\"\n"
        prompt += "}\n"

        // DEBUG: Write the full prompt to a file in Downloads
        Logger.debug("[DEBUG] Writing cover letter recommendation prompt to Downloads folder")
        let fullPromptDebug = "SYSTEM PROMPT:\n\n\(genericSystemMessage.content)\n\nUSER PROMPT:\n\n\(prompt)\n\nJOB DESCRIPTION:\n\n\(jobApp.jobDescription)"
        writeDebugToFile(fullPromptDebug)

        // Create generic messages for the abstraction layer
        let messages = [
            genericSystemMessage,
            ChatMessage(role: .user, content: prompt),
        ]

        // Get model as string
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        do {
            // Use the abstraction layer with structured output
            let structuredOutput = try await openAIClient.sendChatCompletionWithStructuredOutput(
                messages: messages,
                model: modelString,
                temperature: nil,
                structuredOutputType: BestCoverLetterResponse.self
            )

            // DEBUG: Append response to our debug file
            let responseDebug = "\n\nAPI RESPONSE:\n\nPARSED STRUCTURED OUTPUT:\n\(structuredOutput)"
            writeDebugToFile(fullPromptDebug + responseDebug)
            
            return structuredOutput

        } catch {
            let generalErrorDebug = "\n\nGENERAL API ERROR:\n\(error.localizedDescription)"
            writeDebugToFile(fullPromptDebug + generalErrorDebug)
            throw error
        }
    }
}
