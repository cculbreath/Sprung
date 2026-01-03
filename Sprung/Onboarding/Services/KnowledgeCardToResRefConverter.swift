//
//  KnowledgeCardToResRefConverter.swift
//  Sprung
//
//  Converts KnowledgeCard (narrative cards) to ResRef knowledge cards.
//  Direct mapping without LLM calls - the narrative is already the content.
//

import Foundation

/// Converts KnowledgeCard narrative cards to ResRef knowledge cards.
@MainActor
final class KnowledgeCardToResRefConverter {

    // MARK: - Public API

    /// Convert a KnowledgeCard to a ResRef.
    /// - Parameters:
    ///   - card: The knowledge card with narrative content
    ///   - artifactLookup: Mapping of artifact IDs to filenames for source attribution
    /// - Returns: A ResRef ready for persistence
    func convert(
        card: KnowledgeCard,
        artifactLookup: [String: String] = [:]
    ) -> ResRef {
        // Build sources JSON from evidence anchors
        let sourcesJSON = buildSourcesJSON(evidenceAnchors: card.evidenceAnchors, artifactLookup: artifactLookup)

        // Build technologies from domains
        let technologiesJSON = encodeArray(card.extractable.domains)

        // Build suggested bullets from extractable metadata
        let suggestedBullets = buildSuggestedBullets(from: card.extractable)
        let suggestedBulletsJSON = encodeArray(suggestedBullets)

        // Build outcomes from scale
        let outcomesJSON = encodeArray(card.extractable.scale)

        // Build verbatim excerpts from evidence anchors
        let verbatimExcerpts = card.evidenceAnchors.compactMap { anchor -> VerbatimExcerpt? in
            guard let excerpt = anchor.verbatimExcerpt, !excerpt.isEmpty else { return nil }
            return VerbatimExcerpt(
                context: card.title,
                location: "\(artifactLookup[anchor.documentId] ?? anchor.documentId): \(anchor.location)",
                text: excerpt,
                preservationReason: "Verbatim excerpt preserving voice from source document"
            )
        }
        let verbatimExcerptsJSON = encodeVerbatimExcerpts(verbatimExcerpts)

        // Create ResRef with all structured data
        let resRef = ResRef(
            name: card.title,
            content: card.narrative,
            enabledByDefault: true,
            cardType: card.cardType.rawValue,
            timePeriod: card.dateRange,
            organization: card.organization,
            location: nil,
            sourcesJSON: sourcesJSON,
            isFromOnboarding: true,
            tokenCount: card.narrative.count / 4,  // Rough estimate
            factsJSON: nil,  // Narrative cards use prose, not structured facts
            suggestedBulletsJSON: suggestedBulletsJSON,
            technologiesJSON: technologiesJSON
        )

        // Set additional fields
        resRef.outcomesJSON = outcomesJSON
        resRef.verbatimExcerptsJSON = verbatimExcerptsJSON
        resRef.evidenceQuality = card.evidenceAnchors.isEmpty ? "weak" : "strong"

        return resRef
    }

    /// Convert multiple KnowledgeCards sequentially.
    /// - Parameters:
    ///   - cards: Array of knowledge cards
    ///   - artifactLookup: Mapping of artifact IDs to filenames
    ///   - onProgress: Optional callback with (completed, total)
    /// - Returns: Array of ResRefs
    func convertAll(
        cards: [KnowledgeCard],
        artifactLookup: [String: String] = [:],
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> [ResRef] {
        let total = cards.count
        var results: [ResRef] = []

        for (index, card) in cards.enumerated() {
            let resRef = convert(card: card, artifactLookup: artifactLookup)
            results.append(resRef)
            onProgress?(index + 1, total)
        }

        Logger.info("✅ Converted \(results.count)/\(total) knowledge cards to ResRefs", category: .ai)
        return results
    }

    // MARK: - Private Helpers

    private func buildSourcesJSON(
        evidenceAnchors: [EvidenceAnchor],
        artifactLookup: [String: String]
    ) -> String? {
        guard !evidenceAnchors.isEmpty else { return nil }

        var sources: [[String: String]] = []
        for anchor in evidenceAnchors {
            sources.append([
                "artifact_id": anchor.documentId,
                "filename": artifactLookup[anchor.documentId] ?? anchor.documentId,
                "location": anchor.location,
                "type": "evidence"
            ])
        }

        guard let data = try? JSONSerialization.data(withJSONObject: sources),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func buildSuggestedBullets(from extractable: ExtractableMetadata) -> [String] {
        var bullets: [String] = []

        // Add scale items (quantified outcomes) as bullets
        for scale in extractable.scale.prefix(3) {
            bullets.append(scale)
        }

        // Add keywords as potential bullet starters
        for keyword in extractable.keywords.prefix(2) {
            if bullets.count < 5 {
                bullets.append("Demonstrated expertise in \(keyword)")
            }
        }

        return bullets
    }

    private func encodeArray(_ array: [String]) -> String? {
        guard !array.isEmpty,
              let data = try? JSONEncoder().encode(array),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func encodeVerbatimExcerpts(_ excerpts: [VerbatimExcerpt]) -> String? {
        guard !excerpts.isEmpty,
              let data = try? JSONEncoder().encode(excerpts),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
