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

    /// The LLM client used for API calls
    private let client: AppLLMClientProtocol

    // MARK: - Initialization

    /// Initializes a new recommendation service
    /// - Parameter client: The LLM client to use for API calls
    init(client: AppLLMClientProtocol) {
        self.client = client
    }

    // MARK: - Public Methods

    /// Analyzes multiple cover letters and determines which is best
    /// - Parameters:
    ///   - jobApp: The job application containing the cover letters to analyze
    ///   - writingSamples: Optional writing samples to inform the recommendation
    /// - Returns: The recommendation result with analysis and selected cover letter
    func chooseBestCoverLetter(jobApp: JobApp, writingSamples: String) async throws -> BestCoverLetterResponse {
        // Create the recommendation provider with necessary context
        let provider = CoverLetterRecommendationProvider(
            client: client,
            jobApp: jobApp,
            writingSamples: writingSamples
        )

        // Fetch the recommendation from the provider
        return try await provider.fetchBestCoverLetter()
    }
}
