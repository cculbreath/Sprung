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
import SwiftOpenAI

/// Service for preprocessing job applications in the background
/// Extracts requirements and identifies relevant knowledge cards
@MainActor
class JobAppPreprocessor {
    // MARK: - JSON Schema for Structured Output

    /// Schema for preprocessing response - required for Gemini via OpenRouter
    private static let preprocessingSchema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Job requirements extraction and card relevance analysis",
            properties: [
                "must_have": JSONSchema(
                    type: .array,
                    description: "Explicitly required skills/experience (deal-breakers)",
                    items: JSONSchema(type: .string)
                ),
                "strong_signal": JSONSchema(
                    type: .array,
                    description: "Emphasized or frequently mentioned requirements",
                    items: JSONSchema(type: .string)
                ),
                "preferred": JSONSchema(
                    type: .array,
                    description: "Nice-to-have qualifications",
                    items: JSONSchema(type: .string)
                ),
                "cultural": JSONSchema(
                    type: .array,
                    description: "Soft skills and cultural fit indicators",
                    items: JSONSchema(type: .string)
                ),
                "ats_keywords": JSONSchema(
                    type: .array,
                    description: "Technical terms and keywords for ATS matching",
                    items: JSONSchema(type: .string)
                ),
                "relevant_card_ids": JSONSchema(
                    type: .array,
                    description: "IDs of knowledge cards relevant to this job",
                    items: JSONSchema(type: .string)
                )
            ],
            required: ["must_have", "strong_signal", "preferred", "cultural", "ats_keywords", "relevant_card_ids"],
            additionalProperties: false
        )
    }()
    // MARK: - Dependencies

    private weak var llmFacade: LLMFacade?

    // MARK: - Concurrency Control

    /// Semaphore to limit concurrent preprocessing jobs
    private let concurrencyLimit = 5
    private var activeJobCount = 0
    private var pendingJobs: [(jobApp: JobApp, cards: [KnowledgeCard], context: ModelContext)] = []

    // MARK: - Configuration

    /// Model for preprocessing (user-configurable via Settings)
    /// Returns nil if not configured; callers must validate before use
    private var preprocessingModel: String? {
        let modelId = UserDefaults.standard.string(forKey: "backgroundProcessingModelId")
        return (modelId?.isEmpty == false) ? modelId : nil
    }

    // MARK: - Initialization

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
        Logger.info("🔧 JobAppPreprocessor initialized", category: .ai)
    }

    // MARK: - Public API

    /// Preprocess a job application: extract requirements and identify relevant cards
    /// - Parameters:
    ///   - jobApp: The job application to preprocess
    ///   - allCards: All available knowledge cards
    ///   - modelContext: SwiftData context for saving
    func preprocessInBackground(
        for jobApp: JobApp,
        allCards: [KnowledgeCard],
        modelContext: ModelContext
    ) {
        // Queue the job
        pendingJobs.append((jobApp: jobApp, cards: allCards, context: modelContext))
        processNextJobIfAvailable()
    }

    // MARK: - Concurrency Management

    private func processNextJobIfAvailable() {
        guard activeJobCount < concurrencyLimit,
              !pendingJobs.isEmpty else {
            return
        }

        let job = pendingJobs.removeFirst()
        activeJobCount += 1

        Task {
            defer {
                Task { @MainActor in
                    self.activeJobCount -= 1
                    self.processNextJobIfAvailable()
                }
            }

            do {
                let result = try await preprocess(
                    jobDescription: job.jobApp.jobDescription,
                    cards: job.cards
                )

                job.jobApp.extractedRequirements = result.requirements
                job.jobApp.relevantCardIds = result.relevantCardIds
                try? job.context.save()
                Logger.info("✅ [JobAppPreprocessor] Preprocessed: \(job.jobApp.jobPosition) at \(job.jobApp.companyName)", category: .ai)
            } catch {
                Logger.error("❌ [JobAppPreprocessor] Failed to preprocess \(job.jobApp.jobPosition): \(error.localizedDescription)", category: .ai)
            }
        }
    }

    // MARK: - Private

    private func preprocess(
        jobDescription: String,
        cards: [KnowledgeCard]
    ) async throws -> PreprocessingResult {
        guard let facade = llmFacade else {
            throw PreprocessingError.llmNotAvailable
        }

        guard let modelId = preprocessingModel, !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "backgroundProcessingModelId",
                operationName: "Job Requirements Extraction"
            )
        }

        // Build card summaries for the LLM
        let cardSummaries = cards.map { "- \($0.id.uuidString): \($0.title)" }.joined(separator: "\n")

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

        let response = try await facade.executeStructuredWithSchema(
            prompt: prompt,
            modelId: modelId,
            as: PreprocessingResponse.self,
            schema: Self.preprocessingSchema,
            schemaName: "preprocessing_response",
            temperature: 0.2,
            backend: .openRouter
        )

        return PreprocessingResult(
            requirements: ExtractedRequirements(
                mustHave: response.mustHave,
                strongSignal: response.strongSignal,
                preferred: response.preferred,
                cultural: response.cultural,
                atsKeywords: response.atsKeywords,
                extractedAt: Date(),
                extractionModel: modelId
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
