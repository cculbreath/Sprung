import Foundation
import SwiftOpenAI // Will be removed later in the migration
import SwiftUI

/// Provider for selecting the best cover letter among existing ones using OpenAI JSON schema responses
final class CoverLetterRecommendationProvider {
    /// System prompt guiding the AI to evaluate cover letters and return structured JSON in SwiftOpenAI format
    let systemMessage = ChatCompletionParameters.Message(
        role: .system,
        content: .text("""
            You are an expert career advisor and professional writer specializing in evaluating cover letters. Your task is to analyze a list of cover letters for a specific job application and select the one that best matches the candidate's voice, style, and quality. You will be provided with job details, several cover letter drafts, and writing samples that represent the candidate's preferred style. Return a JSON object strictly conforming to the provided schema.
            """
        )
    )
    
    /// System prompt in generic format for abstraction layer
    let genericSystemMessage = ChatMessage(
        role: .system,
        content: """
            You are an expert career advisor and professional writer specializing in evaluating cover letters. Your task is to analyze a list of cover letters for a specific job application and select the one that best matches the candidate's voice, style, and quality. You will be provided with job details, several cover letter drafts, and writing samples that represent the candidate's preferred style. Return a JSON object strictly conforming to the provided schema.
            """
    )
    
    // For backward compatibility
    private let service: OpenAIService?
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
        self.openAIClient = client
        self.service = nil
        self.jobApp = jobApp
        self.writingSamples = writingSamples
    }
    
    /// Legacy initializer using SwiftOpenAI service directly
    /// - Parameters:
    ///   - service: The OpenAIService from SwiftOpenAI
    ///   - jobApp: The job application containing cover letters
    ///   - writingSamples: Writing samples for style reference
    init(service: OpenAIService, jobApp: JobApp, writingSamples: String) {
        self.service = service
        // Get API key from UserDefaults since OpenAIService doesn't expose it
        let apiKey = UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
        self.openAIClient = SwiftOpenAIClient(apiKey: apiKey)
        self.jobApp = jobApp
        self.writingSamples = writingSamples
    }

    /// Fetch the best cover letter using the abstraction layer
    /// - Returns: The response containing the best cover letter UUID and reasoning
    func fetchBestCoverLetterWithGenericClient() async throws -> BestCoverLetterResponse {
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
            ChatMessage(role: .user, content: prompt)
        ]
        
        // Get model as string
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        
        do {
            // Make the API call using our abstraction layer
            let response = try await openAIClient.sendChatCompletionAsync(
                messages: messages,
                model: modelString,
                temperature: 0.2 // Lower temperature for more deterministic structured outputs
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
            print("Error fetching best cover letter with generic client: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Fetch the best cover letter according to AI analysis
    func fetchBestCoverLetter() async throws -> BestCoverLetterResponse {
        // If we don't have a service, use the abstraction layer
        if service == nil {
            return try await fetchBestCoverLetterWithGenericClient()
        }
        
        guard let service = service else {
            return try await fetchBestCoverLetterWithGenericClient()
        }
        
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
        prompt += "Which of the cover letters is strongest? Which cover letter best matches the style, voice and quality of \\(applicant.name)'s previous letters? For your response, please return a brief summary ranking/assessment of each letter's relative strength and the degree to which it captures the author's voice and style, determine the one letter that is the strongest and most convincingly in the author's voice, and a brief reason for your ultimate choice."
        prompt += "\\nWhen providing the strength-and-voice-analysis and verdict responses, reference each letter by its name, not its id.\\n"

        // Define JSON schema for response
        let schema = JSONSchemaResponseFormat(
            name: "best_coverletter_response",
            strict: true,
            schema: JSONSchema(
                type: .object,
                properties: [
                    "strength-and-voice-analysis": JSONSchema(type: .string,
                                                              description: "Brief summary ranking/assessment of each letter's strength and voice"),
                    "best-letter-uuid": JSONSchema(type: .string,
                                                   description: "UUID of the selected best cover letter"),
                    "verdict": JSONSchema(type: .string,
                                          description: "Reason for the ultimate choice"),
                ],
                required: ["strength-and-voice-analysis", "best-letter-uuid", "verdict"],
                additionalProperties: false
            )
        )
        let preferredModel = OpenAIModelFetcher.getPreferredModel()
        let messages: [ChatCompletionParameters.Message] = [
            systemMessage,
            .init(role: .user, content: .text(prompt)),
        ]
        let parameters = ChatCompletionParameters(
            messages: messages,
            model: preferredModel,
            responseFormat: .jsonSchema(schema)
        )
        // Perform the chat request
        let result = try await service.startChat(parameters: parameters)
        guard let choice = result.choices?.first,
              let message = choice.message,
              let content = message.content
        else {
            throw NSError(domain: "CoverLetterRecommendationProvider", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        guard let data = content.data(using: .utf8) else {
            throw NSError(domain: "CoverLetterRecommendationProvider", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not convert response to data"])
        }
        let decoded = try JSONDecoder().decode(BestCoverLetterResponse.self, from: data)
        return decoded
    }
}
