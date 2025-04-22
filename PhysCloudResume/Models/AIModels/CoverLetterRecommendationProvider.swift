import Foundation
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
    struct BestCoverLetterResponse: Decodable {
        let strengthAndVoiceAnalysis: String
        let bestLetterUuid: String
        let verdict: String

        enum CodingKeys: String, CodingKey {
            case strengthAndVoiceAnalysis = "strength-and-voice-analysis"
            case bestLetterUuid = "best-letter-uuid"
            case verdict
        }
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

        // Get model as string
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        do {
            // Make the API call using our abstraction layer
            let response = try await openAIClient.sendChatCompletionAsync(
                messages: messages,
                model: modelString,
                temperature: 1.0 // Using standard temperature of 1.0 as requested
            )

            // Process the response
            let content = response.content

            guard let data = content.data(using: .utf8) else {
                throw NSError(domain: "CoverLetterRecommendationProvider", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Could not convert response to data"])
            }

            let decoded = try JSONDecoder().decode(BestCoverLetterResponse.self, from: data)
            return decoded
        } catch {
            print("Error fetching best cover letter: \(error.localizedDescription)")
            throw error
        }
    }
}
