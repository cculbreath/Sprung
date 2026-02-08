//
//  BackgroundMergeAgent.swift
//  Sprung
//
//  Background agent for merging knowledge cards.
//  Operates asynchronously during document processing.
//

import Foundation

/// A lightweight background agent that merges cards
@MainActor
class BackgroundMergeAgent {
    private let workspacePath: URL
    private let cardFiles: [String]
    private let mergeReason: String
    private let modelId: String
    private weak var facade: LLMFacade?
    private let agentId: String
    private let parentAgentId: String?
    private weak var tracker: AgentActivityTracker?

    init(
        workspacePath: URL,
        cardFiles: [String],
        mergeReason: String,
        modelId: String,
        facade: LLMFacade?,
        parentAgentId: String? = nil,
        tracker: AgentActivityTracker? = nil
    ) {
        self.workspacePath = workspacePath
        self.cardFiles = cardFiles
        self.mergeReason = mergeReason
        self.modelId = modelId
        self.facade = facade
        self.agentId = UUID().uuidString
        self.parentAgentId = parentAgentId
        self.tracker = tracker
    }

    /// Execute the merge operation
    func run() async throws -> BackgroundMergeResult {
        guard let facade = facade else {
            throw MergeError.noLLMFacade
        }

        // Build a short name from the card files
        let shortName = cardFiles.count <= 2
            ? cardFiles.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.prefix(8) }.joined(separator: "+")
            : "\(cardFiles.count) cards"

        // Register as child agent if we have a parent
        if let parentId = parentAgentId, let tracker = tracker {
            tracker.trackChildAgent(
                id: agentId,
                parentAgentId: parentId,
                type: .backgroundMerge,
                name: "Merge: \(shortName)",
                task: nil as Task<Void, Never>?
            )
            tracker.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Starting merge of \(cardFiles.count) cards",
                details: mergeReason
            )
        }

        Logger.info("🔀 Background merge [\(agentId.prefix(8))] starting: \(cardFiles.count) cards", category: .ai)

        do {
            // Step 1: Read all source cards
            tracker?.updateStatusMessage(agentId: agentId, message: "Reading cards...")
            var cardContents: [String: String] = [:]
            for cardFile in cardFiles {
                let filePath = workspacePath.appendingPathComponent(cardFile)
                guard FileManager.default.fileExists(atPath: filePath.path) else {
                    throw MergeError.cardNotFound(cardFile)
                }
                let content = try String(contentsOf: filePath, encoding: .utf8)
                cardContents[cardFile] = content
            }

            tracker?.appendTranscript(
                agentId: agentId,
                entryType: .toolResult,
                content: "Read \(cardContents.count) cards"
            )

            // Step 2: Build merge prompt
            let prompt = buildMergePrompt(cards: cardContents)

            // Step 3: Call LLM to synthesize merged card
            tracker?.updateStatusMessage(agentId: agentId, message: "Synthesizing merge...")
            tracker?.appendTranscript(
                agentId: agentId,
                entryType: .turn,
                content: "Calling LLM to synthesize merged card"
            )

            let mergedCardJSON = try await callLLMForMerge(facade: facade, prompt: prompt)

            tracker?.appendTranscript(
                agentId: agentId,
                entryType: .assistant,
                content: "Merged card synthesized"
            )

            // Step 4: Generate new UUID and write merged card
            tracker?.updateStatusMessage(agentId: agentId, message: "Writing merged card...")
            let newCardId = UUID().uuidString
            let mergedCard = try updateCardId(json: mergedCardJSON, newId: newCardId)
            let newCardPath = workspacePath.appendingPathComponent("cards/\(newCardId).json")
            try mergedCard.write(to: newCardPath, atomically: true, encoding: .utf8)

            Logger.info("🔀 Background merge [\(agentId.prefix(8))] wrote merged card: \(newCardId)", category: .ai)

            // Step 5: Delete source cards
            tracker?.updateStatusMessage(agentId: agentId, message: "Deleting source cards...")
            for cardFile in cardFiles {
                let filePath = workspacePath.appendingPathComponent(cardFile)
                try? FileManager.default.removeItem(at: filePath)
            }

            Logger.info("🔀 Background merge [\(agentId.prefix(8))] deleted \(cardFiles.count) source cards", category: .ai)

            // Step 6: Update index
            try updateIndex(deletedFiles: cardFiles, newCardId: newCardId, mergedCardJSON: mergedCard)

            Logger.info("🔀 Background merge [\(agentId.prefix(8))] complete", category: .ai)

            // Mark complete
            tracker?.appendTranscript(
                agentId: agentId,
                entryType: .toolResult,
                content: "Merge complete",
                details: "Created \(newCardId.prefix(8))..., deleted \(cardFiles.count) source cards"
            )
            tracker?.markCompleted(agentId: agentId)

            return BackgroundMergeResult(
                mergeId: agentId,
                sourceCardIds: cardFiles.map { extractCardId(from: $0) },
                newCardId: newCardId,
                success: true
            )

        } catch {
            Logger.error("🔀 Background merge [\(agentId.prefix(8))] failed: \(error.localizedDescription)", category: .ai)
            tracker?.markFailed(agentId: agentId, error: error.localizedDescription)
            throw error
        }
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
        5. Use the widest dateRange that covers all cards
        6. Keep the most descriptive title
        7. If any source card contains negative content (performance criticisms,
           failure admissions, negative feedback), drop that content — it has
           no value in resume generation

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
            modelId: modelId
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
                "cardType": cardDict["cardType"] as? String ?? "",
                "title": cardDict["title"] as? String ?? "",
                "organization": cardDict["organization"] as? String ?? "",
                "dateRange": cardDict["dateRange"] as? String ?? "",
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

/// Result of a background merge operation
struct BackgroundMergeResult {
    let mergeId: String
    let sourceCardIds: [String]
    let newCardId: String
    let success: Bool
}
