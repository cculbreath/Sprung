import Foundation
import SwiftOpenAI

/// Refines a single knowledge card using structured output from an LLM.
@MainActor
final class KCRefinementService {
    private let llmFacade: LLMFacade
    private let reasoningStreamManager: ReasoningStreamManager
    private var activeStreamingHandle: LLMStreamingHandle?

    init(llmFacade: LLMFacade, reasoningStreamManager: ReasoningStreamManager) {
        self.llmFacade = llmFacade
        self.reasoningStreamManager = reasoningStreamManager
    }

    /// Refine a knowledge card with streaming reasoning display.
    /// Falls back to non-streaming if the streaming path yields no content.
    func refine(
        card: KnowledgeCard,
        instructions: String,
        modelId: String
    ) async throws -> RefinedKnowledgeCard {
        let cardJSON = try encodeCard(card)

        let systemPrompt = """
        You are refining a knowledge card based on the user's instructions.

        A knowledge card is a structured narrative about a professional experience, project, \
        achievement, or education credential. It contains a rich narrative (500-2000 words) along \
        with structured metadata used for resume generation and job matching.

        ## Guidelines

        - Apply the refinement instructions to improve the card
        - Preserve the card's factual accuracy — do not fabricate experiences or credentials
        - Maintain the narrative voice and style while making requested improvements
        - Keep all metadata fields (domains, keywords, technologies, etc.) consistent with the narrative
        - If the narrative changes significantly, update suggestedBullets and outcomes to match
        - Preserve any facts and verbatim excerpts unless the instructions specifically ask to change them
        - Return the complete refined card with ALL fields populated
        """

        let userMessage = """
        ## Current Card

        ```json
        \(cardJSON)
        ```

        ## Refinement Instructions

        \(instructions)
        """

        let prompt = systemPrompt + "\n\n" + userMessage

        // Try streaming with reasoning first
        do {
            let result = try await refineStreaming(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId
            )
            if let result { return result }
            Logger.info("KC Refine: streaming produced no content, falling back to non-streaming", category: .ai)
        } catch {
            Logger.info("KC Refine: streaming failed (\(error.localizedDescription)), falling back to non-streaming", category: .ai)
        }

        // Fallback: non-streaming structured output (always works)
        reasoningStreamManager.hideAndClear()
        return try await llmFacade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: RefinedKnowledgeCard.self,
            schema: KCRefinementSchema.schema,
            schemaName: "refined_knowledge_card"
        )
    }

    /// Cancel any active streaming operation.
    func cancelActiveStreaming() {
        activeStreamingHandle?.cancel()
        activeStreamingHandle = nil
    }

    // MARK: - Streaming Path

    private func refineStreaming(
        systemPrompt: String,
        userMessage: String,
        modelId: String
    ) async throws -> RefinedKnowledgeCard? {
        let jsonSchema = try JSONSchema.from(dictionary: KCRefinementSchema.schema)
        let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
        let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

        cancelActiveStreaming()

        let handle = try await llmFacade.startConversationStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            reasoning: reasoning,
            jsonSchema: jsonSchema
        )
        activeStreamingHandle = handle

        let responseText = try await processStreamWithReasoning(handle: handle, modelName: modelId)

        guard !responseText.isEmpty else { return nil }
        return try LLMResponseParser.parseJSON(responseText, as: RefinedKnowledgeCard.self)
    }

    // MARK: - Stream Processing

    private func processStreamWithReasoning(
        handle: LLMStreamingHandle,
        modelName: String
    ) async throws -> String {
        reasoningStreamManager.clear()
        reasoningStreamManager.startReasoning(modelName: modelName)

        var fullResponse = ""
        var collectingJSON = false
        var jsonResponse = ""
        var chunkCount = 0
        var reasoningChunks = 0
        var contentChunks = 0

        for try await chunk in handle.stream {
            chunkCount += 1

            if let reasoningContent = chunk.allReasoningText {
                reasoningChunks += 1
                reasoningStreamManager.reasoningText += reasoningContent
            }

            if let content = chunk.content {
                contentChunks += 1
                fullResponse += content
                if content.contains("{") || collectingJSON {
                    collectingJSON = true
                    jsonResponse += content
                }
            }

            if chunk.isFinished {
                Logger.debug("KC Refine stream finished: \(chunkCount) chunks, \(reasoningChunks) reasoning, \(contentChunks) content, response=\(fullResponse.count) chars", category: .ai)
                reasoningStreamManager.isStreaming = false
                reasoningStreamManager.isVisible = false
            }
        }

        cancelActiveStreaming()
        return jsonResponse.isEmpty ? fullResponse : jsonResponse
    }

    /// Apply a refined card's fields onto an existing KnowledgeCard.
    func apply(_ refined: RefinedKnowledgeCard, to card: KnowledgeCard) {
        card.title = refined.title
        card.narrative = refined.narrative
        if let cardTypeStr = refined.cardType {
            card.cardType = CardType(rawValue: cardTypeStr)
        }
        card.dateRange = refined.dateRange
        card.organization = refined.organization
        card.location = refined.location
        card.extractable = ExtractableMetadata(
            domains: refined.domains,
            scale: refined.scale,
            keywords: refined.keywords
        )
        card.technologies = refined.technologies
        card.outcomes = refined.outcomes
        card.suggestedBullets = refined.suggestedBullets
        card.evidenceQuality = refined.evidenceQuality

        if let refinedFacts = refined.facts {
            card.facts = refinedFacts.map { fact in
                KnowledgeCardFact(
                    category: fact.category,
                    statement: fact.statement,
                    confidence: fact.confidence,
                    source: nil
                )
            }
        }

        if let refinedExcerpts = refined.verbatimExcerpts {
            card.verbatimExcerpts = refinedExcerpts.map { excerpt in
                VerbatimExcerpt(
                    context: excerpt.context,
                    location: excerpt.location,
                    text: excerpt.text,
                    preservationReason: excerpt.preservationReason
                )
            }
        }
    }

    // MARK: - Private

    private func encodeCard(_ card: KnowledgeCard) throws -> String {
        var dict: [String: Any] = [
            "title": card.title,
            "narrative": card.narrative
        ]

        if let cardType = card.cardType { dict["cardType"] = cardType.rawValue }
        if let dateRange = card.dateRange { dict["dateRange"] = dateRange }
        if let org = card.organization { dict["organization"] = org }
        if let loc = card.location { dict["location"] = loc }

        let ext = card.extractable
        dict["domains"] = ext.domains
        dict["scale"] = ext.scale
        dict["keywords"] = ext.keywords
        dict["technologies"] = card.technologies
        dict["outcomes"] = card.outcomes
        dict["suggestedBullets"] = card.suggestedBullets

        if let eq = card.evidenceQuality { dict["evidenceQuality"] = eq }

        if !card.facts.isEmpty {
            dict["facts"] = card.facts.map { fact in
                var f: [String: Any] = [
                    "category": fact.category,
                    "statement": fact.statement
                ]
                if let c = fact.confidence { f["confidence"] = c }
                return f
            }
        }

        if !card.verbatimExcerpts.isEmpty {
            dict["verbatimExcerpts"] = card.verbatimExcerpts.map { excerpt in
                [
                    "context": excerpt.context,
                    "location": excerpt.location,
                    "text": excerpt.text,
                    "preservationReason": excerpt.preservationReason
                ]
            }
        }

        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
