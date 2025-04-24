//
//  CoverLetterRecommendationProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/21/25.
//

import Foundation
import OpenAI
import SwiftUI

/// Provider for selecting the best cover letter among existing ones using OpenAI JSON schema responses
final class CoverLetterRecommendationProvider {
    /// System prompt in generic format for abstraction layer
    let genericSystemMessage = ChatMessage(
        role: .system,
        content: """
        You are an expert career advisor and professional writer specializing in evaluating cover letters. Your task is to analyze a list of cover letters for a specific job application and select the one that best matches the candidate's voice, style, and quality. You will be provided with job details, several cover letter drafts, and writing samples that represent the candidate's preferred style. Return a JSON object strictly conforming to the provided schema.
        """
    )

    // The new abstraction layer client
    private let openAIClient: OpenAIClientProtocol

    private let jobApp: JobApp
    private let writingSamples: String

    /// Response schema for best cover letter selection
    struct BestCoverLetterResponse: Codable, StructuredOutput {
        let strengthAndVoiceAnalysis: String
        let bestLetterUuid: String
        let verdict: String

        // Example instance for schema generation
        static let example: Self = .init(
            strengthAndVoiceAnalysis: "Letter A has strong technical details but formal tone. Letter B has a more conversational style with good examples.",
            bestLetterUuid: "00000000-0000-0000-0000-000000000000",
            verdict: "Letter B has the best balance of professional content and personal voice."
        )
    }

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
        for letter in letters {
            prompt += "id: \(letter.id.uuidString), name: \(letter.sequencedName), content:\n\(letter.content)\n\n"
        }
        prompt += "For reference here are some of \(applicant.name)'s previous cover letters that he's particularly satisfied with:\n"
        prompt += "\(writingSamples)\n\n"
        prompt += "Which of the cover letters is strongest? Which cover letter best matches the style, voice and quality of \(applicant.name)'s previous letters? For your response, please return a brief summary ranking/assessment of each letter's relative strength and the degree to which it captures the author's voice and style, determine the one letter that is the strongest and most convincingly in the author's voice, and a brief reason for your ultimate choice."
        prompt += "\nWhen providing the strength-and-voice-analysis and verdict responses, reference each letter by its name, not its id.\n"
        prompt += "\nYou MUST return a JSON object with exactly these fields:\n"
        prompt += "{\n"
        prompt += "  \"strength-and-voice-analysis\": \"Brief summary ranking/assessment of each letter's strength and voice\",\n"
        prompt += "  \"best-letter-uuid\": \"UUID of the selected best cover letter\",\n"
        prompt += "  \"verdict\": \"Reason for the ultimate choice\"\n"
        prompt += "}\n"

        // Create generic messages for the abstraction layer
        let messages = [
            genericSystemMessage,
            ChatMessage(role: .user, content: prompt),
        ]
        // Debug: show prompt and messages to be sent

        // Get model as string
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
                    responseFormat: .jsonSchema(name: "cover-letter-recommendation", type: BestCoverLetterResponse.self),
                    temperature: 1.0
                )
                // Debug: print converted chat messages

                // Make the API call with structured output
                // Debug: print query details
                // Call API with structured output
                let result = try await macPawClient.openAIClient.chats(query: query)
                // Debug: print raw API result object

                // Extract structured output response
                // For MacPaw/OpenAI structured outputs, we need to check the content string
                // since there's no structured output property directly accessible

                if let content = result.choices.first?.message.content,
                   let data = content.data(using: .utf8)
                {
                    // Debug: print raw content and JSON payload
                    if let jsonString = String(data: data, encoding: .utf8) {}
                    do {
                        let structuredOutput = try JSONDecoder().decode(BestCoverLetterResponse.self, from: data)
                        // Debug: print decoded structured output
                        return structuredOutput
                    } catch {
                        // Debug: decoding failure
                        throw NSError(
                            domain: "CoverLetterRecommendationProvider",
                            code: 1003,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to decode structured output: \(error.localizedDescription)"]
                        )
                    }
                } else {
                    throw NSError(
                        domain: "CoverLetterRecommendationProvider",
                        code: 1002,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to get structured output content"]
                    )
                }
            } else {
                throw NSError(domain: "CoverLetterRecommendationProvider", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Could not convert response to data"])
            }

        } catch {
            throw error
        }
    }
}
