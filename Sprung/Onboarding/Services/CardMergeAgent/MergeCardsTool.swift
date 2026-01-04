//
//  MergeCardsTool.swift
//  Sprung
//
//  Tool for spawning background merge sub-agents.
//

import Foundation

// MARK: - Merge Cards Tool

struct MergeCardsTool: AgentTool {
    static let name = "merge_cards"
    static let description = """
        Spawn a background agent to merge 2 or more cards into one.
        The background agent will read the cards, synthesize a merged narrative,
        write the new card, and delete the source cards.
        Returns immediately so you can continue analyzing other cards.
        Use this when you've identified duplicates and want to merge them efficiently.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "card_files": [
                "type": "array",
                "items": ["type": "string"],
                "minItems": 2,
                "description": "Paths to card files to merge (e.g., ['cards/uuid1.json', 'cards/uuid2.json'])"
            ],
            "merge_reason": [
                "type": "string",
                "description": "Brief explanation of why these cards should be merged (e.g., 'Same project with different names')"
            ]
        ],
        "required": ["card_files", "merge_reason"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let cardFiles: [String]
        let mergeReason: String

        enum CodingKeys: String, CodingKey {
            case cardFiles = "card_files"
            case mergeReason = "merge_reason"
        }
    }
}

// MARK: - Background Merge Agent

/// A lightweight background agent that merges cards
@MainActor
class BackgroundMergeAgent {
    private let workspacePath: URL
    private let cardFiles: [String]
    private let mergeReason: String
    private let modelId: String
    private weak var facade: LLMFacade?
    private let mergeId: String

    init(
        workspacePath: URL,
        cardFiles: [String],
        mergeReason: String,
        modelId: String,
        facade: LLMFacade?
    ) {
        self.workspacePath = workspacePath
        self.cardFiles = cardFiles
        self.mergeReason = mergeReason
        self.modelId = modelId
        self.facade = facade
        self.mergeId = UUID().uuidString.prefix(8).lowercased()
    }

    /// Execute the merge operation
    func run() async throws -> BackgroundMergeResult {
        guard let facade = facade else {
            throw MergeError.noLLMFacade
        }

        Logger.info("🔀 Background merge [\(mergeId)] starting: \(cardFiles.count) cards", category: .ai)

        // Step 1: Read all source cards
        var cardContents: [String: String] = [:]
        for cardFile in cardFiles {
            let filePath = workspacePath.appendingPathComponent(cardFile)
            guard FileManager.default.fileExists(atPath: filePath.path) else {
                throw MergeError.cardNotFound(cardFile)
            }
            let content = try String(contentsOf: filePath, encoding: .utf8)
            cardContents[cardFile] = content
        }

        // Step 2: Build merge prompt
        let prompt = buildMergePrompt(cards: cardContents)

        // Step 3: Call LLM to synthesize merged card
        let mergedCardJSON = try await callLLMForMerge(facade: facade, prompt: prompt)

        // Step 4: Generate new UUID and write merged card
        let newCardId = UUID().uuidString
        let mergedCard = try updateCardId(json: mergedCardJSON, newId: newCardId)
        let newCardPath = workspacePath.appendingPathComponent("cards/\(newCardId).json")
        try mergedCard.write(to: newCardPath, atomically: true, encoding: .utf8)

        Logger.info("🔀 Background merge [\(mergeId)] wrote merged card: \(newCardId)", category: .ai)

        // Step 5: Delete source cards
        for cardFile in cardFiles {
            let filePath = workspacePath.appendingPathComponent(cardFile)
            try? FileManager.default.removeItem(at: filePath)
        }

        Logger.info("🔀 Background merge [\(mergeId)] deleted \(cardFiles.count) source cards", category: .ai)

        // Step 6: Update index
        try updateIndex(deletedFiles: cardFiles, newCardId: newCardId, mergedCardJSON: mergedCard)

        Logger.info("🔀 Background merge [\(mergeId)] complete", category: .ai)

        return BackgroundMergeResult(
            mergeId: mergeId,
            sourceCardIds: cardFiles.map { extractCardId(from: $0) },
            newCardId: newCardId,
            success: true
        )
    }

    private func buildMergePrompt(cards: [String: String]) -> String {
        var prompt = """
        You are merging \(cards.count) knowledge cards that describe the SAME underlying experience.

        Merge reason: \(mergeReason)

        ## THE CARDINAL RULE: NEVER OVER-COMPRESS

        The merged result MUST be RICHER than any single input. Preserve:
        - WHY (motivation, context, the problem being solved)
        - HOW (methodology, decisions, pivots, collaboration)
        - WHAT (outcomes, lessons, insights)
        - VOICE (authentic phrasing, personality)

        ## MERGE SYNTHESIS PROCESS

        1. Use the richest narrative as your base
        2. Weave in unique content from other cards (don't just append)
        3. Preserve ALL specific numbers, dates, technologies
        4. Union all metadata (domains, scale, keywords, evidence_anchors)
        5. Use the widest date_range that covers all cards
        6. Keep the most descriptive title

        ## SOURCE CARDS

        """

        for (file, content) in cards {
            prompt += "\n### \(file)\n```json\n\(content)\n```\n"
        }

        prompt += """

        ## OUTPUT

        Return ONLY the merged card as valid JSON. Use the same schema as the input cards.
        The "id" field will be replaced with a new UUID after you return it.
        """

        return prompt
    }

    private func callLLMForMerge(facade: LLMFacade, prompt: String) async throws -> String {
        let messages: [ChatCompletionParameters.Message] = [
            ChatCompletionParameters.Message(role: .user, content: .text(prompt))
        ]

        let response = try await facade.executeWithTools(
            messages: messages,
            tools: [],
            toolChoice: nil,
            modelId: modelId,
            temperature: 0.3
        )

        guard let choice = response.choices?.first,
              let message = choice.message,
              let content = message.content else {
            throw MergeError.noResponse
        }

        // Extract JSON from response (may be wrapped in markdown code blocks)
        return extractJSON(from: content)
    }

    private func extractJSON(from content: String) -> String {
        // Try to extract JSON from markdown code block
        if let jsonMatch = content.range(of: "```json\n", options: .caseInsensitive),
           let endMatch = content.range(of: "\n```", range: jsonMatch.upperBound..<content.endIndex) {
            return String(content[jsonMatch.upperBound..<endMatch.lowerBound])
        }
        // Try generic code block
        if let jsonMatch = content.range(of: "```\n"),
           let endMatch = content.range(of: "\n```", range: jsonMatch.upperBound..<content.endIndex) {
            return String(content[jsonMatch.upperBound..<endMatch.lowerBound])
        }
        // Assume raw JSON
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateCardId(json: String, newId: String) throws -> String {
        guard let data = json.data(using: .utf8),
              var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MergeError.invalidJSON
        }
        dict["id"] = newId
        let updatedData = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        guard let updatedJSON = String(data: updatedData, encoding: .utf8) else {
            throw MergeError.invalidJSON
        }
        return updatedJSON
    }

    private func updateIndex(deletedFiles: [String], newCardId: String, mergedCardJSON: String) throws {
        let indexPath = workspacePath.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: indexPath.path) else { return }

        let indexData = try Data(contentsOf: indexPath)
        guard var index = try JSONSerialization.jsonObject(with: indexData) as? [[String: Any]] else { return }

        // Remove deleted cards from index
        let deletedIds = Set(deletedFiles.map { extractCardId(from: $0) })
        index.removeAll { entry in
            guard let id = entry["id"] as? String else { return false }
            return deletedIds.contains(id)
        }

        // Add new merged card summary to index
        if let cardData = mergedCardJSON.data(using: .utf8),
           let cardDict = try? JSONSerialization.jsonObject(with: cardData) as? [String: Any] {
            let summary: [String: Any] = [
                "id": newCardId,
                "card_type": cardDict["card_type"] as? String ?? "",
                "title": cardDict["title"] as? String ?? "",
                "organization": cardDict["organization"] as? String ?? "",
                "date_range": cardDict["date_range"] as? String ?? "",
                "narrative_preview": String((cardDict["narrative"] as? String ?? "").prefix(200))
            ]
            index.append(summary)
        }

        // Write updated index
        let updatedIndexData = try JSONSerialization.data(withJSONObject: index, options: [.prettyPrinted, .sortedKeys])
        try updatedIndexData.write(to: indexPath)
    }

    private func extractCardId(from path: String) -> String {
        // Extract UUID from path like "cards/uuid.json"
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return filename
    }

    enum MergeError: LocalizedError {
        case noLLMFacade
        case cardNotFound(String)
        case noResponse
        case invalidJSON

        var errorDescription: String? {
            switch self {
            case .noLLMFacade: return "LLM service not available"
            case .cardNotFound(let path): return "Card not found: \(path)"
            case .noResponse: return "No response from LLM"
            case .invalidJSON: return "Invalid JSON in response"
            }
        }
    }
}

struct BackgroundMergeResult {
    let mergeId: String
    let sourceCardIds: [String]
    let newCardId: String
    let success: Bool
}
