//
//  ReadKnowledgeCardsTool.swift
//  Sprung
//
//  Tool that retrieves full knowledge card details by ID during resume customization.
//  Returns verbatim excerpts, evidence anchors, outcomes, and full fact attribution
//  that are omitted from the preamble for token efficiency.
//

import Foundation
import SwiftyJSON

/// Tool that retrieves full knowledge card details including verbatim excerpts
/// and evidence anchors. The LLM uses this to get deeper evidence when the
/// abbreviated preamble context isn't sufficient for a particular claim.
struct ReadKnowledgeCardsTool: ResumeTool {
    static let name = "read_knowledge_cards"

    static let description = """
        Retrieve full details for one or more knowledge cards by ID. Returns \
        verbatim source excerpts, evidence anchors, outcomes, and all facts with \
        full source attribution. Use this when you need the candidate's authentic \
        phrasing, want to verify a specific metric, or need deeper evidence to \
        support a resume claim. Card IDs are listed in the Knowledge Cards section \
        of the context (bracketed UUIDs in each card header).
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "card_ids": [
                "type": "array",
                "description": "Array of knowledge card UUIDs to retrieve full details for.",
                "items": [
                    "type": "string",
                    "description": "UUID of a knowledge card from the context"
                ]
            ]
        ],
        "required": ["card_ids"],
        "additionalProperties": false
    ]

    private let knowledgeCardStore: KnowledgeCardStore

    init(knowledgeCardStore: KnowledgeCardStore) {
        self.knowledgeCardStore = knowledgeCardStore
    }

    func execute(_ params: JSON, context: ResumeToolContext) async throws -> ResumeToolResult {
        guard let idsArray = params["card_ids"].array else {
            return .error("Missing or invalid 'card_ids' parameter")
        }

        let requestedIds = idsArray.compactMap { $0.string }
        if requestedIds.isEmpty {
            return .error("No valid card IDs provided")
        }

        Logger.info("[ReadKnowledgeCardsTool] Retrieving \(requestedIds.count) cards", category: .ai)

        // Read card data on MainActor (KnowledgeCardStore is @MainActor)
        let (cards, notFound) = await MainActor.run {
            var found: [JSON] = []
            var missing: [String] = []

            for idString in requestedIds {
                guard let uuid = UUID(uuidString: idString),
                      let card = knowledgeCardStore.card(withId: uuid) else {
                    missing.append(idString)
                    continue
                }
                found.append(buildCardJSON(card))
            }

            return (found, missing)
        }

        var result = JSON(["cards": cards.map { $0.object as Any }])
        if !notFound.isEmpty {
            result["not_found"] = JSON(notFound)
        }

        return .immediate(result)
    }

    // MARK: - Private

    private func buildCardJSON(_ card: KnowledgeCard) -> JSON {
        var json = JSON([:])

        json["id"].string = card.id.uuidString
        json["title"].string = card.title
        json["narrative"].string = card.narrative
        json["card_type"].string = card.cardType?.displayName ?? "General"

        if let org = card.organization { json["organization"].string = org }
        if let dateRange = card.dateRange { json["date_range"].string = dateRange }
        if let quality = card.evidenceQuality { json["evidence_quality"].string = quality }

        // Full facts with source attribution
        let facts = card.facts
        if !facts.isEmpty {
            json["facts"] = JSON(facts.map { fact -> [String: Any] in
                var f: [String: Any] = [
                    "category": fact.category,
                    "statement": fact.statement
                ]
                if let confidence = fact.confidence { f["confidence"] = confidence }
                if let source = fact.source {
                    var s: [String: String] = [:]
                    if let artifactId = source.artifactId { s["artifact_id"] = artifactId }
                    if let location = source.location { s["location"] = location }
                    if let quote = source.verbatimQuote { s["verbatim_quote"] = quote }
                    f["source"] = s
                }
                return f
            })
        }

        // Verbatim excerpts (the primary value of this tool — not in preamble)
        let excerpts = card.verbatimExcerpts
        if !excerpts.isEmpty {
            json["verbatim_excerpts"] = JSON(excerpts.map { excerpt -> [String: String] in
                [
                    "context": excerpt.context,
                    "location": excerpt.location,
                    "text": excerpt.text,
                    "preservation_reason": excerpt.preservationReason
                ]
            })
        }

        // Evidence anchors linking to source documents
        let anchors = card.evidenceAnchors
        if !anchors.isEmpty {
            json["evidence_anchors"] = JSON(anchors.map { anchor -> [String: String] in
                var a: [String: String] = [
                    "document_id": anchor.documentId,
                    "location": anchor.location
                ]
                if let excerpt = anchor.verbatimExcerpt { a["verbatim_excerpt"] = excerpt }
                return a
            })
        }

        // Outcomes
        if let outcomesJSON = card.outcomesJSON,
           let data = outcomesJSON.data(using: .utf8),
           let outcomes = try? JSONDecoder().decode([String].self, from: data) {
            json["outcomes"] = JSON(outcomes)
        }

        // Technologies
        let techs = card.technologies
        if !techs.isEmpty {
            json["technologies"] = JSON(techs)
        }

        // Suggested bullets
        let bullets = card.suggestedBullets
        if !bullets.isEmpty {
            json["suggested_bullets"] = JSON(bullets)
        }

        return json
    }
}
