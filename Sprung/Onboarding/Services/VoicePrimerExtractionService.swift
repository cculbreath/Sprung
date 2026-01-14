//
//  VoicePrimerExtractionService.swift
//  Sprung
//
//  Service that extracts voice characteristics from writing samples.
//  Runs in background after writing samples are collected in Phase 1.
//  Results are stored as CoverRef with type .voicePrimer for use in
//  cover letter generation and phase prompts.
//
import Foundation
import SwiftyJSON

/// Service that extracts voice characteristics from writing samples.
/// Triggered when writing samples are collected, runs extraction in background,
/// and stores results as CoverRef for downstream use.
actor VoicePrimerExtractionService {
    // MARK: - Dependencies
    private let eventBus: EventCoordinator
    private let coverRefStore: CoverRefStore
    private var llmFacade: LLMFacade?

    // MARK: - State
    private var isExtracting = false
    private var extractedPrimer: JSON?

    // MARK: - Configuration

    private func getModelId() throws -> String {
        guard let modelId = UserDefaults.standard.string(forKey: "voicePrimerExtractionModelId"), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "voicePrimerExtractionModelId",
                operationName: "Voice Primer Extraction"
            )
        }
        return modelId
    }

    // MARK: - Initialization

    init(eventBus: EventCoordinator, coverRefStore: CoverRefStore, llmFacade: LLMFacade? = nil) {
        self.eventBus = eventBus
        self.coverRefStore = coverRefStore
        self.llmFacade = llmFacade
        Logger.info("🎤 VoicePrimerExtractionService initialized", category: .ai)
    }

    func setLLMFacade(_ facade: LLMFacade) {
        self.llmFacade = facade
    }

    // MARK: - Public API

    /// Extract voice characteristics from writing samples.
    /// This runs in background and does not block the interview.
    /// - Parameter samples: Array of writing sample content strings
    /// - Returns: The extracted voice primer JSON, or nil if extraction failed
    @discardableResult
    func extractVoicePrimer(from samples: [String]) async -> JSON? {
        guard !samples.isEmpty else {
            Logger.warning("🎤 No writing samples provided for voice extraction", category: .ai)
            return nil
        }

        guard !isExtracting else {
            Logger.info("🎤 Voice extraction already in progress", category: .ai)
            return extractedPrimer
        }

        isExtracting = true
        await eventBus.publish(.artifact(.voicePrimerExtractionStarted(sampleCount: samples.count)))

        Logger.info("🎤 Starting voice primer extraction from \(samples.count) sample(s)", category: .ai)

        do {
            let primer = try await performExtraction(samples: samples)
            extractedPrimer = primer

            // Build summary and persist to CoverRefStore
            let summary = buildVoicePrimerSummary()
            let primerJSON = primer.rawString()
            await persistVoicePrimer(summary: summary, primerJSON: primerJSON)

            await eventBus.publish(.artifact(.voicePrimerExtractionCompleted(primer: primer)))
            Logger.info("🎤 Voice primer extraction completed successfully", category: .ai)

            isExtracting = false
            return primer
        } catch {
            await eventBus.publish(.artifact(.voicePrimerExtractionFailed(error: error.localizedDescription)))
            Logger.error("🎤 Voice primer extraction failed: \(error.localizedDescription)", category: .ai)
            isExtracting = false
            return nil
        }
    }

    /// Get the extracted voice primer if available.
    func getVoicePrimer() -> JSON? {
        extractedPrimer
    }

    /// Build a summary string suitable for injection into phase prompts.
    /// Returns a human-readable summary of the voice characteristics.
    func buildVoicePrimerSummary() -> String {
        guard let primer = extractedPrimer else {
            return "No voice analysis available yet. Writing samples have not been collected or analyzed."
        }

        var summary = primer["summary"].stringValue
        if summary.isEmpty {
            summary = "Voice analysis completed."
        }

        // Add key characteristics
        var characteristics: [String] = []

        if let tone = primer["tone"]["description"].string, !tone.isEmpty {
            characteristics.append("Tone: \(tone)")
        }

        if let structure = primer["structure"]["description"].string, !structure.isEmpty {
            characteristics.append("Structure: \(structure)")
        }

        if let vocab = primer["vocabulary"]["description"].string, !vocab.isEmpty {
            characteristics.append("Vocabulary: \(vocab)")
        }

        if let rhetoric = primer["rhetoric"]["description"].string, !rhetoric.isEmpty {
            characteristics.append("Rhetoric: \(rhetoric)")
        }

        // Add strengths
        let strengths = primer["markers"]["strengths"].arrayValue.compactMap { $0.string }
        if !strengths.isEmpty {
            characteristics.append("Strengths: \(strengths.joined(separator: ", "))")
        }

        // Add recommendations
        let recommendations = primer["markers"]["recommendations"].arrayValue.compactMap { $0.string }
        if !recommendations.isEmpty {
            characteristics.append("Recommendations: \(recommendations.joined(separator: "; "))")
        }

        if characteristics.isEmpty {
            return summary
        }

        return """
        \(summary)

        Key Characteristics:
        \(characteristics.map { "• \($0)" }.joined(separator: "\n"))
        """
    }

    // MARK: - Private Methods

    private func performExtraction(samples: [String]) async throws -> JSON {
        guard let facade = llmFacade else {
            throw VoicePrimerError.llmNotConfigured
        }

        // Load the extraction prompt template
        let promptTemplate = loadPromptTemplate()

        // Combine samples with clear separators
        let combinedSamples = samples.enumerated().map { index, sample in
            """
            --- Writing Sample \(index + 1) ---
            \(sample)
            """
        }.joined(separator: "\n\n")

        // Build the full prompt
        let fullPrompt = promptTemplate.replacingOccurrences(of: "{WRITING_SAMPLES}", with: combinedSamples)

        // Get model from settings
        let modelId = try getModelId()

        // Call LLM for extraction using startConversation (one-shot)
        // LLMFacade is @MainActor - async methods can be called directly from actors
        let (_, responseText) = try await facade.startConversation(
            systemPrompt: "You are a voice analysis expert. Return only valid JSON without markdown formatting.",
            userMessage: fullPrompt,
            modelId: modelId,
            temperature: 0.3
        )

        // Try to extract JSON from response (it might be wrapped in markdown code blocks)
        let cleanedResponse = cleanJSONFromMarkdown(responseText)

        guard let cleanedData = cleanedResponse.data(using: .utf8) else {
            throw VoicePrimerError.invalidResponse("Cleaned response was not valid UTF-8")
        }

        do {
            let primer = try JSON(data: cleanedData)
            return primer
        } catch {
            throw VoicePrimerError.invalidResponse("Failed to parse JSON: \(error.localizedDescription)")
        }
    }

    private func loadPromptTemplate() -> String {
        // Try to load from PromptLibrary pattern first
        if let url = Bundle.main.url(forResource: "voice_primer_extraction", withExtension: "txt", subdirectory: "Prompts"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }

        // Fallback to embedded template
        return """
        Analyze the provided writing samples and extract voice characteristics.

        Return JSON with:
        - summary: 2-3 sentence description
        - tone: formality, confidence, warmth, description
        - structure: sentence_length, paragraph_style, description
        - vocabulary: technical_level, sophistication, distinctive_phrases, description
        - rhetoric: opening_style, argument_style, closing_style, description
        - markers: quirks, strengths, recommendations

        Writing Samples:
        {WRITING_SAMPLES}
        """
    }

    private func cleanJSONFromMarkdown(_ response: String) -> String {
        var cleaned = response

        // Remove markdown code block markers
        if cleaned.contains("```json") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        }
        if cleaned.contains("```") {
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func persistVoicePrimer(summary: String, primerJSON: String?) {
        let coverRef = CoverRef(
            name: "Voice Primer",
            content: summary,
            enabledByDefault: true,
            type: .voicePrimer,
            voicePrimerJSON: primerJSON
        )

        coverRefStore.addCoverRef(coverRef)
        Logger.info("🎤 Voice primer persisted to CoverRefStore with structured JSON", category: .ai)
    }

    // MARK: - Errors

    enum VoicePrimerError: Error, LocalizedError {
        case llmNotConfigured
        case invalidResponse(String)
        case noSamples

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM is not configured for voice extraction"
            case .invalidResponse(let reason):
                return "Invalid LLM response: \(reason)"
            case .noSamples:
                return "No writing samples provided"
            }
        }
    }
}
