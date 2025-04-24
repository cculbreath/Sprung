//
//  CoverLetterRecommendationService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import Foundation

/// Service that handles AI-based cover letter recommendations
class CoverLetterRecommendationService {
    // MARK: - Properties

    /// The OpenAI client used for API calls
    private let client: OpenAIClientProtocol

    // MARK: - Initialization

    /// Initializes a new recommendation service
    /// - Parameter client: The OpenAI client to use for API calls
    init(client: OpenAIClientProtocol) {
        self.client = client
    }

    // MARK: - Public Methods

    /// Analyzes multiple cover letters and determines which is best
    /// - Parameters:
    ///   - jobApp: The job application containing the cover letters to analyze
    ///   - writingSamples: Optional writing samples to inform the recommendation
    /// - Returns: The recommendation result with analysis and selected cover letter
    func chooseBestCoverLetter(jobApp: JobApp, writingSamples: String) async throws -> CoverLetterRecommendationProvider.BestCoverLetterResponse {
        // Create the recommendation provider with necessary context
        let provider = CoverLetterRecommendationProvider(
            client: client,
            jobApp: jobApp,
            writingSamples: writingSamples
        )

        // Fetch the recommendation from the provider
        return try await provider.fetchBestCoverLetter()
    }

    /// Returns an analysis of a single cover letter's strengths and weaknesses
    /// - Parameters:
    ///   - coverLetter: The cover letter to analyze
    ///   - jobApp: The associated job application for context
    /// - Returns: A detailed analysis of the cover letter
    func analyzeCoverLetter(coverLetter _: CoverLetter, jobApp _: JobApp) async throws -> CoverLetterAnalysis {
        // This is a placeholder for potential future expansion
        // You would implement a similar pattern to the chooseBestCoverLetter method

        // For now we'll throw a not implemented error
        throw NSError(
            domain: "CoverLetterRecommendationService",
            code: 501,
            userInfo: [NSLocalizedDescriptionKey: "Cover letter analysis not yet implemented"]
        )
    }
}

/// Represents an analysis of a cover letter's strengths and weaknesses
struct CoverLetterAnalysis {
    /// Overall rating of the cover letter (1-10)
    let rating: Int
    /// Description of the cover letter's strengths
    let strengths: String
    /// Description of the cover letter's weaknesses
    let weaknesses: String
    /// Suggestions for improvement
    let suggestions: String
}
