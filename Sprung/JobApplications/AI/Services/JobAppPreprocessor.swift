//
//  JobAppPreprocessor.swift
//  Sprung
//
//  Service for preprocessing job applications in the background.
//  Extracts requirements from job descriptions and identifies relevant knowledge cards.
//
//  This runs automatically after a job is created, storing results on the JobApp
//  for instant access during resume customization.
//

import Foundation
import SwiftData

/// Service for preprocessing job applications in the background
/// Extracts requirements and identifies relevant knowledge cards
@MainActor
class JobAppPreprocessor {
    // MARK: - Dependencies

    private weak var llmFacade: LLMFacade?

    // MARK: - Configuration

    /// Model for preprocessing (user-configurable via Settings)
    private var preprocessingModel: String {
        UserDefaults.standard.string(forKey: "backgroundProcessingModelId") ?? "gemini-2.5-flash"
    }

    // MARK: - Initialization

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("🔧 JobAppPreprocessor initialized", category: .ai)
    }

    /// Update the LLM facade reference
    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    // MARK: - Public API

    /// Preprocess a job application: extract requirements and identify relevant cards
    /// - Parameters:
    ///   - jobApp: The job application to preprocess
    ///   - allCards: All available knowledge cards
    ///   - modelContext: SwiftData context for saving
    func preprocessInBackground(
        for jobApp: JobApp,
        allCards: [ResRef],
        modelContext: ModelContext
    ) {
        Task {
            do {
                let result = try await preprocess(
                    jobDescription: jobApp.jobDescription,
                    cards: allCards
                )

                jobApp.extractedRequirements = result.requirements
                jobApp.relevantCardIds = result.relevantCardIds
                try? modelContext.save()
                Logger.info("✅ [JobAppPreprocessor] Preprocessed: \(jobApp.jobPosition) at \(jobApp.companyName)", category: .ai)
            } catch {
                Logger.error("❌ [JobAppPreprocessor] Failed to preprocess \(jobApp.jobPosition): \(error.localizedDescription)", category: .ai)
            }
        }
    }

    // MARK: - Private

    private func preprocess(
        jobDescription: String,
        cards: [ResRef]
    ) async throws -> PreprocessingResult {
        guard let facade = llmFacade else {
            throw PreprocessingError.llmNotAvailable
        }

        // Build card summaries for the LLM
        let cardSummaries = cards.map { "- \($0.id.uuidString): \($0.name)" }.joined(separator: "\n")

        let prompt = """
        Analyze this job posting and identify:
        1. Requirements by priority tier
        2. Which knowledge cards are relevant to this job

        JOB POSTING:
        \(jobDescription)

        AVAILABLE KNOWLEDGE CARDS:
        \(cardSummaries)

        ---

        TASK 1 - REQUIREMENTS:
        Extract requirements into these categories:
        - must_have: Explicitly required, deal-breakers (e.g., "required", "must have", "X years experience")
        - strong_signal: Emphasized or mentioned multiple times
        - preferred: Nice-to-have, mentioned once (e.g., "preferred", "bonus", "plus")
        - cultural: Soft skills, team fit, work style expectations
        - ats_keywords: ALL technical terms, tools, technologies for keyword matching

        TASK 2 - RELEVANT CARDS:
        From the card list above, identify which cards are likely relevant to this job.
        Be INCLUSIVE — when in doubt, include the card. It's better to include a
        marginally relevant card than exclude a useful one.

        Return JSON matching the required structure.
        """

        let response = try await facade.executeStructured(
            prompt: prompt,
            modelId: preprocessingModel,
            as: PreprocessingResponse.self,
            temperature: 0.2,
            backend: .gemini
        )

        return PreprocessingResult(
            requirements: ExtractedRequirements(
                mustHave: response.mustHave,
                strongSignal: response.strongSignal,
                preferred: response.preferred,
                cultural: response.cultural,
                atsKeywords: response.atsKeywords,
                extractedAt: Date(),
                extractionModel: preprocessingModel
            ),
            relevantCardIds: response.relevantCardIds
        )
    }
}

// MARK: - Response Types

private struct PreprocessingResponse: Codable, Sendable {
    let mustHave: [String]
    let strongSignal: [String]
    let preferred: [String]
    let cultural: [String]
    let atsKeywords: [String]
    let relevantCardIds: [String]

    enum CodingKeys: String, CodingKey {
        case mustHave = "must_have"
        case strongSignal = "strong_signal"
        case preferred
        case cultural
        case atsKeywords = "ats_keywords"
        case relevantCardIds = "relevant_card_ids"
    }
}

private struct PreprocessingResult {
    let requirements: ExtractedRequirements
    let relevantCardIds: [String]
}

// MARK: - Errors

enum PreprocessingError: LocalizedError {
    case llmNotAvailable
    case emptyJobDescription

    var errorDescription: String? {
        switch self {
        case .llmNotAvailable:
            return "LLM service is not available for preprocessing"
        case .emptyJobDescription:
            return "Job description is empty"
        }
    }
}
