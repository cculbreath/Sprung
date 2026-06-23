import Foundation
import SwiftOpenAI

/// Refines a single knowledge card using structured output from an LLM.
@MainActor
final class KCRefinementService {
    enum KCRefinementError: LocalizedError {
        case incompleteResponse

        var errorDescription: String? {
            switch self {
            case .incompleteResponse:
                return "The refinement response was incomplete (missing title or narrative). Your card was left unchanged — please try again."
            }
        }
    }

    private let llmFacade: LLMFacade
    private let reasoningStreamManager: ReasoningStreamState
    private var activeStreamingHandle: LLMStreamingHandle?

    init(llmFacade: LLMFacade, reasoningStreamManager: ReasoningStreamState) {
        self.llmFacade = llmFacade
        self.reasoningStreamManager = reasoningStreamManager
    }

    /// Refine a knowledge card with streaming reasoning display.
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

        return try await refineStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId
        )
    }

    /// Re-refine a single field using the user's feedback, returning just that
    /// field's new value. Backs the review screen's per-field Retry.
    func refineField(
        card: KnowledgeCard,
        field: KCField,
        feedback: String,
        modelId: String
    ) async throws -> KCFieldValue {
        let cardJSON = try encodeCard(card)

        let systemPrompt = """
        You are refining a SINGLE field of a knowledge card based on the user's feedback.

        A knowledge card is a structured narrative about a professional experience, project, \
        achievement, or education credential.

        ## Guidelines

        - Refine ONLY the "\(field.jsonKey)" field (\(field.label)). Do not return any other field.
        - Apply the user's feedback precisely.
        - Preserve factual accuracy — do not fabricate experiences or credentials.
        - Maintain the card's narrative voice and style.
        - Return a JSON object containing only the "\(field.jsonKey)" field.
        """

        let userMessage = """
        ## Current Card

        ```json
        \(cardJSON)
        ```

        ## Field to Refine

        \(field.label) (`\(field.jsonKey)`)

        ## Feedback

        \(feedback)
        """

        let jsonSchema = try JSONSchema.from(dictionary: KCRefinementSchema.singleFieldSchema(key: field.jsonKey))
        let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
        let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)
        let maxOutputTokens = llmFacade.maxOutputTokens(forModel: modelId) ?? 128_000

        cancelActiveStreaming()

        let handle = try await llmFacade.startConversationStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            reasoning: reasoning,
            jsonSchema: jsonSchema,
            maxTokens: maxOutputTokens
        )
        activeStreamingHandle = handle

        var fullResponse = ""
        for try await chunk in handle.stream {
            if let content = chunk.content {
                fullResponse += content
            }
        }
        cancelActiveStreaming()

        let jsonText = JSONResponseParser.extractJSON(from: fullResponse)
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object[field.jsonKey] != nil else {
            Logger.error(
                "KC Refine field '\(field.jsonKey)' produced no value (\(fullResponse.count) chars): \(fullResponse.prefix(2000))",
                category: .ai
            )
            throw KCRefinementError.incompleteResponse
        }

        let value = field.value(fromJSON: object[field.jsonKey])

        // Never let an empty title/narrative retry wipe the field on accept.
        if field == .title || field == .narrative,
           case .text(let text) = value,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Logger.error("KC Refine field '\(field.jsonKey)' returned empty text — rejecting", category: .ai)
            throw KCRefinementError.incompleteResponse
        }

        return value
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
    ) async throws -> RefinedKnowledgeCard {
        let jsonSchema = try JSONSchema.from(dictionary: KCRefinementSchema.schema)
        let userEffort = UserDefaults.standard.string(forKey: "reasoningEffort") ?? "medium"
        let reasoning = OpenRouterReasoning(effort: userEffort, includeReasoning: true)

        // Give the response the model's full output budget. With extended thinking
        // enabled, max_tokens bounds thinking + output together, so a small provider
        // default clips the (500-2000 word) narrative mid-JSON. A truncated card then
        // parses into empty/partial fields and wipes the user's content on apply.
        let maxOutputTokens = llmFacade.maxOutputTokens(forModel: modelId) ?? 128_000
        Logger.info("KC Refine max output tokens: \(maxOutputTokens)", category: .ai)

        cancelActiveStreaming()

        let handle = try await llmFacade.startConversationStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: modelId,
            reasoning: reasoning,
            jsonSchema: jsonSchema,
            maxTokens: maxOutputTokens
        )
        activeStreamingHandle = handle

        let responseText = try await processStreamWithReasoning(handle: handle, modelName: modelId)
        let refined = try JSONResponseParser.parseText(responseText, as: RefinedKnowledgeCard.self)

        // Defensively reject a refinement that dropped the card's core content. A
        // truncated or malformed response can still decode with empty title/narrative;
        // applying it would destroy the user's card, so fail loud and leave it intact.
        guard !refined.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !refined.narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.error(
                "KC Refine produced empty title/narrative (\(responseText.count) chars) — rejecting to preserve card: \(responseText.prefix(2000))",
                category: .ai
            )
            throw KCRefinementError.incompleteResponse
        }

        return refined
    }

    // MARK: - Stream Processing

    private func processStreamWithReasoning(
        handle: LLMStreamingHandle,
        modelName: String
    ) async throws -> String {
        reasoningStreamManager.clear()
        reasoningStreamManager.startReasoning(modelName: modelName)

        var fullResponse = ""
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
            }

            if chunk.isFinished {
                Logger.debug("KC Refine stream finished: \(chunkCount) chunks, \(reasoningChunks) reasoning, \(contentChunks) content, response=\(fullResponse.count) chars", category: .ai)
                reasoningStreamManager.isStreaming = false
                reasoningStreamManager.isVisible = false
            }
        }

        cancelActiveStreaming()
        // Feed the parser the full response; it handles fenced/embedded JSON, so a
        // chunk-boundary-dependent slice only risks dropping the leading brace.
        return fullResponse
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
