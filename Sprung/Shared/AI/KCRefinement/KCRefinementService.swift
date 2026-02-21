import Foundation

/// Refines a single knowledge card using structured output from an LLM.
@MainActor
final class KCRefinementService {
    private let llmFacade: LLMFacade

    init(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }

    /// Refine a knowledge card with the given instructions.
    /// Returns the LLM's refined version of the card.
    func refine(
        card: KnowledgeCard,
        instructions: String,
        modelId: String
    ) async throws -> RefinedKnowledgeCard {
        let cardJSON = try encodeCard(card)

        let prompt = """
        You are refining a knowledge card based on the user's instructions.

        A knowledge card is a structured narrative about a professional experience, project, \
        achievement, or education credential. It contains a rich narrative (500-2000 words) along \
        with structured metadata used for resume generation and job matching.

        ## Current Card

        ```json
        \(cardJSON)
        ```

        ## Refinement Instructions

        \(instructions)

        ## Guidelines

        - Apply the refinement instructions to improve the card
        - Preserve the card's factual accuracy — do not fabricate experiences or credentials
        - Maintain the narrative voice and style while making requested improvements
        - Keep all metadata fields (domains, keywords, technologies, etc.) consistent with the narrative
        - If the narrative changes significantly, update suggestedBullets and outcomes to match
        - Preserve any facts and verbatim excerpts unless the instructions specifically ask to change them
        - Return the complete refined card with ALL fields populated
        """

        return try await llmFacade.executeStructuredWithDictionarySchema(
            prompt: prompt,
            modelId: modelId,
            as: RefinedKnowledgeCard.self,
            schema: KCRefinementSchema.schema,
            schemaName: "refined_knowledge_card"
        )
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
        // Build a dictionary representation with all editable fields
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
