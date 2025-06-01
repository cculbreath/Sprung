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

    /// The app state for creating OpenRouter clients
    private let appState: AppState
    
    /// The model ID to use for recommendations
    private let modelId: String

    // MARK: - Initialization

    /// Initializes a new recommendation service
    /// - Parameters:
    ///   - appState: The application state
    ///   - modelId: The OpenRouter model ID to use
    init(appState: AppState, modelId: String) {
        self.appState = appState
        self.modelId = modelId
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
            appState: appState,
            jobApp: jobApp,
            writingSamples: writingSamples,
            modelId: modelId
        )

        // Fetch the recommendation from the provider
        return try await provider.fetchBestCoverLetter()
    }
}
