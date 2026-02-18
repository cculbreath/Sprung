//
//  TitleSetGenerationService.swift
//  Sprung
//
//  AI generation service for professional identity title sets.
//  Encapsulates prompt construction, backend routing, LLM calls, and response parsing.
//

import Foundation
import SwiftOpenAI

// MARK: - Response Types

struct TitleGenerationResponse: Codable {
    let words: [String]
    let comment: String
}

struct BulkTitleResponse: Codable {
    let sets: [BulkTitleSet]

    struct BulkTitleSet: Codable {
        let words: [String]
    }
}

// MARK: - Service

@Observable
@MainActor
final class TitleSetGenerationService {

    private let llmFacade: LLMFacade

    init(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }

    // MARK: - Single Generation

    func generate(
        currentWords: [TitleWord],
        instructions: String,
        conversationHistory: [GenerationTurn],
        approvedSets: [TitleSetRecord],
        skills: [Skill]
    ) async throws -> TitleGenerationResponse {
        let (modelId, backend) = getModelConfig()
        guard !modelId.isEmpty else {
            throw TitleSetGenerationError.modelNotConfigured
        }

        let experienceContext = buildExperienceContext(skills: skills)
        let historyContext = buildHistoryContext(history: conversationHistory)
        let approvedContext = buildApprovedContext(approvedSets: approvedSets)

        let lockedWords = currentWords.enumerated()
            .filter { $0.element.isLocked }
            .map { (index: $0.offset, word: $0.element.text) }

        let lockedDescription = lockedWords.isEmpty
            ? "No words are locked."
            : "Locked words (must include these): " + lockedWords.map { $0.word }.joined(separator: ", ")

        let prompt = """
            Generate professional identity words for a resume title line.

            \(experienceContext)

            \(approvedContext)

            \(historyContext)

            Current state:
            \(lockedDescription)

            \(instructions.isEmpty ? "" : "User instructions: \(instructions)")

            Generate \(4 - lockedWords.count) new professional identity words to complement the locked words.
            These should be single words or short phrases like "Physicist", "Software Developer", "Educator", "Machinist".
            They should work together as a cohesive professional identity.
            IMPORTANT: Create a DISTINCT combination that differs meaningfully from the approved sets listed above.

            Arrange all 4 words (locked + new) in the best order for flow and impact.

            Return JSON:
            {
                "words": ["word1", "word2", "word3", "word4"],
                "comment": "Brief suggestion or observation about this combination"
            }

            Include all 4 words in the response, including the locked words in any position.
            """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "words": ["type": "array", "items": ["type": "string"]],
                "comment": ["type": "string"]
            ],
            "required": ["words", "comment"],
            "additionalProperties": false
        ]

        if backend == .anthropic {
            let systemBlock = SwiftOpenAI.AnthropicSystemBlock(
                text: "You are a professional identity consultant helping craft compelling resume title lines."
            )
            return try await llmFacade.executeStructuredWithAnthropicCaching(
                systemContent: [systemBlock],
                userPrompt: prompt,
                modelId: modelId,
                responseType: TitleGenerationResponse.self,
                schema: schema
            )
        } else {
            return try await llmFacade.executeStructuredWithDictionarySchema(
                prompt: prompt,
                modelId: modelId,
                as: TitleGenerationResponse.self,
                schema: schema,
                schemaName: "title_generation",
                backend: backend
            )
        }
    }

    // MARK: - Bulk Generation

    func bulkGenerate(
        count: Int,
        currentWords: [TitleWord],
        instructions: String,
        approvedSets: [TitleSetRecord],
        skills: [Skill]
    ) async throws -> BulkTitleResponse {
        let (modelId, backend) = getModelConfig()
        guard !modelId.isEmpty else {
            throw TitleSetGenerationError.modelNotConfigured
        }

        let experienceContext = buildExperienceContext(skills: skills)
        let approvedContext = buildApprovedContext(approvedSets: approvedSets)

        let lockedWords = currentWords.filter { $0.isLocked && !$0.text.isEmpty }
        let lockedTexts = lockedWords.map { $0.text }
        let wordsToGenerate = 4 - lockedTexts.count

        let lockedInstruction: String
        if lockedTexts.isEmpty {
            lockedInstruction = ""
        } else {
            lockedInstruction = """
                LOCKED WORDS REQUIREMENT:
                Each set MUST include: \(lockedTexts.joined(separator: ", "))
                Place locked words in ANY position (not always first) - vary the order for natural flow.
                Generate \(wordsToGenerate) additional words to complement the locked words.
                """
        }

        let prompt = """
            Generate \(count) distinct sets of 4 professional identity words for resume title lines.

            \(experienceContext)

            \(approvedContext)

            \(lockedInstruction)

            Each set should:
            - Contain exactly 4 words/phrases like "Physicist", "Software Developer", "Educator", "Machinist"
            - Arrange words in the best order for flow and impact (locked words can go anywhere)
            - Work together as a cohesive professional identity
            - Be distinct from other sets AND from the already approved sets listed above
            - Accurately reflect the candidate's actual background shown above

            \(instructions.isEmpty ? "" : "User guidance: \(instructions)")

            Return JSON:
            {
                "sets": [
                    {"words": ["word1", "word2", "word3", "word4"]},
                    {"words": ["word1", "word2", "word3", "word4"]}
                ]
            }
            """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "sets": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "words": ["type": "array", "items": ["type": "string"]]
                        ],
                        "required": ["words"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "required": ["sets"],
            "additionalProperties": false
        ]

        if backend == .anthropic {
            let systemBlock = SwiftOpenAI.AnthropicSystemBlock(
                text: "You are a professional identity consultant helping craft compelling resume title lines."
            )
            return try await llmFacade.executeStructuredWithAnthropicCaching(
                systemContent: [systemBlock],
                userPrompt: prompt,
                modelId: modelId,
                responseType: BulkTitleResponse.self,
                schema: schema
            )
        } else {
            return try await llmFacade.executeStructuredWithDictionarySchema(
                prompt: prompt,
                modelId: modelId,
                as: BulkTitleResponse.self,
                schema: schema,
                schemaName: "bulk_titles",
                backend: backend
            )
        }
    }

    // MARK: - Private Context Builders

    private func buildHistoryContext(history: [GenerationTurn]) -> String {
        guard !history.isEmpty else { return "" }

        var context = "Previous generation history:\n"
        for (index, turn) in history.suffix(5).enumerated() {
            context += "\nTurn \(index + 1):\n"
            if !turn.lockedWordTexts.isEmpty {
                context += "- Locked: \(turn.lockedWordTexts.joined(separator: ", "))\n"
            }
            if let instructions = turn.userInstructions {
                context += "- Instructions: \(instructions)\n"
            }
            context += "- Generated: \(turn.generatedWords.joined(separator: ", "))\n"
            if let comment = turn.aiComment {
                context += "- AI comment: \(comment)\n"
            }
        }
        return context
    }

    private func buildApprovedContext(approvedSets: [TitleSetRecord]) -> String {
        guard !approvedSets.isEmpty else { return "" }

        var context = "Already approved title sets (DO NOT duplicate these):\n"
        for titleSet in approvedSets {
            let wordsDisplay = titleSet.words.map { $0.text }.joined(separator: " · ")
            context += "- \(wordsDisplay)\n"
        }
        return context
    }

    private func buildExperienceContext(skills: [Skill]) -> String {
        guard !skills.isEmpty else { return "" }

        var context = "## Candidate's Professional Background\n\n"
        context += "### Skills\n"
        let skillNames = skills.map { $0.canonical }
        context += skillNames.joined(separator: ", ")
        context += "\n\n"

        context += """
            Based on this skill set, generate professional identity words that accurately
            represent this candidate's actual expertise and specializations.
            Do NOT invent credentials or expertise areas not supported by the skills above.
            """

        return context
    }

    private func getModelConfig() -> (modelId: String, backend: LLMFacade.Backend) {
        let backendString = UserDefaults.standard.string(forKey: "seedGenerationBackend") ?? "anthropic"
        let modelKey = backendString == "anthropic" ? "seedGenerationAnthropicModelId" : "seedGenerationOpenRouterModelId"
        let modelId = UserDefaults.standard.string(forKey: modelKey) ?? ""

        let backend: LLMFacade.Backend
        switch backendString {
        case "anthropic":
            backend = .anthropic
        case "openrouter":
            backend = .openRouter
        default:
            backend = .anthropic
        }

        return (modelId, backend)
    }
}

// MARK: - Errors

enum TitleSetGenerationError: LocalizedError {
    case modelNotConfigured

    var errorDescription: String? {
        switch self {
        case .modelNotConfigured:
            return "No model configured. Please set the Seed Generation model in Settings."
        }
    }
}
