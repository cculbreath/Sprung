//
//  CardVerificationPrompts.swift
//  Sprung
//
//  Prompt builder, JSON schema, and response types for the anti-hallucination
//  verification pass that runs after narrative-card extraction and before
//  enrichment. One batched structured call per document/chunk audits every
//  extracted card against the SAME cached source block the extraction saw.
//

import Foundation

enum CardVerificationPrompts {

    /// Build the verification instructions for one document/chunk. The source
    /// document itself is provided as a preceding content block (PDF document
    /// block or cached text block), not inlined into the prompt.
    static func verificationPrompt(
        documentId: String,
        filename: String,
        cards: [KnowledgeCard],
        isPagedSource: Bool
    ) -> String {
        let anchorGuidance = isPagedSource
            ? """
            The source is page-addressable: every anchor location MUST cite a page \
            ("p. 14", "p. 3, Fig. 2"). An anchor that cites no page is invalid. Verify the \
            quoted excerpt actually appears on the cited page.
            """
            : """
            Verify the cited location exists in the document and the quoted excerpt \
            actually appears at (or immediately near) that location.
            """

        return """
        You are now acting as an ADVERSARIAL FACT-CHECKER. The source document is provided \
        at the start of this message. Below are \(cards.count) knowledge cards that were \
        extracted from it (document id: \(documentId), filename: \(filename)). Your job is \
        to audit every card against the source — assume the extraction may have hallucinated.

        ## Audit, per card

        1. **Unsupported claims** — list every specific factual assertion in the card \
        (numbers, dates, names, titles, technologies, outcomes, scope/scale claims) that \
        the source document does NOT support. Faithful paraphrase and reasonable \
        summarization of what the document states are fine; invention, inflation, and \
        details imported from outside the document are not.

        2. **Anchor audit** — check every evidence anchor. \(anchorGuidance) \
        Set `anchorsValid` to true ONLY if every anchor passes. When `anchorsValid` is \
        false you MUST supply `repairedAnchors` as the card's COMPLETE replacement anchor \
        set — it replaces ALL of the card's anchors, so include every anchor that should \
        survive:
           - echo each anchor that passed the audit UNCHANGED (same location, same excerpt);
           - for each failed anchor whose underlying material DOES exist elsewhere in the \
        document, include a corrected anchor with the right location and a verbatim \
        excerpt copied EXACTLY from the document;
           - omit anchors whose material does not exist in the document at all — never \
        invent a repair.
        Leave `repairedAnchors` empty ONLY when no anchor material exists anywhere in the \
        document. Omitting a valid anchor from `repairedAnchors` deletes it.

        3. **Verdict** — exactly one of:
           - `keep`: every material claim is supported by the document.
           - `revise`: the core story is supported, but some claims are not. You MUST then \
        provide `revisedNarrative`: the complete narrative with the unsupported claims \
        removed or softened to exactly what the document supports. Change NOTHING else — \
        preserve the author's voice, wording, and structure everywhere else verbatim.
           - `drop`: the card's core claim is not supported by this document.

        Be strict — an unverifiable claim on a resume can cost the applicant the job. But \
        do not punish grounded paraphrase, and do not drop a card for tone or style.

        ## Cards Under Audit

        \(renderCards(cards))

        Return a verdict for ALL \(cards.count) cards, in order, echoing each card's \
        `cardIndex` (as numbered above) and `cardId`.
        """
    }

    /// Render the extracted cards (claims + evidence anchors) for the audit.
    /// Deterministic: derived only from card fields, no timestamps.
    private static func renderCards(_ cards: [KnowledgeCard]) -> String {
        cards.enumerated().map { index, card in
            var lines: [String] = []
            lines.append("### Card \(index)")
            lines.append("cardId: \(card.id.uuidString.lowercased())")
            lines.append("title: \(card.title)")
            if let organization = card.organization, !organization.isEmpty {
                lines.append("organization: \(organization)")
            }
            if let dateRange = card.dateRange, !dateRange.isEmpty {
                lines.append("dateRange: \(dateRange)")
            }
            lines.append("narrative:\n\(card.narrative)")

            let anchors = card.evidenceAnchors
            if anchors.isEmpty {
                lines.append("evidenceAnchors: (none)")
            } else {
                let rendered = anchors.enumerated().map { anchorIndex, anchor -> String in
                    var entry = "- anchor \(anchorIndex): location=\"\(anchor.location)\""
                    if let excerpt = anchor.verbatimExcerpt, !excerpt.isEmpty {
                        entry += " excerpt=\"\(excerpt)\""
                    }
                    return entry
                }.joined(separator: "\n")
                lines.append("evidenceAnchors:\n\(rendered)")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// JSON Schema for the batched verification response — enforced via
    /// Anthropic structured output. Keys are camelCase matching the Swift
    /// response types exactly (we control this wire format).
    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "verdicts": [
                "type": "array",
                "description": "One verdict per audited card, in card order",
                "items": [
                    "type": "object",
                    "properties": [
                        "cardIndex": [
                            "type": "integer",
                            "description": "Zero-based index of the card as numbered in the audit list"
                        ],
                        "cardId": [
                            "type": "string",
                            "description": "The cardId echoed from the audit list"
                        ],
                        "verdict": [
                            "type": "string",
                            "enum": ["keep", "revise", "drop"],
                            "description": "keep = fully supported; revise = strip unsupported claims (revisedNarrative required); drop = core claim unsupported"
                        ],
                        "unsupportedClaims": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Specific claims in the card that the source document does not support (empty when fully supported)"
                        ],
                        "anchorsValid": [
                            "type": "boolean",
                            "description": "True only if every evidence anchor's location exists and its excerpt appears there"
                        ],
                        "repairedAnchors": [
                            "type": "array",
                            "description": "REQUIRED when anchorsValid is false: the card's COMPLETE replacement anchor set (replaces ALL anchors) — valid anchors echoed unchanged, broken-but-repairable anchors corrected, unrepairable anchors omitted; empty only when no anchor material exists in the document",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "documentId": [
                                        "type": "string",
                                        "description": "Document identifier (unchanged from the card)"
                                    ],
                                    "location": [
                                        "type": "string",
                                        "description": "Corrected location; page-anchored for paged sources"
                                    ],
                                    "verbatimExcerpt": [
                                        "type": "string",
                                        "description": "Excerpt copied exactly from the document at the corrected location"
                                    ]
                                ],
                                "required": ["documentId", "location"],
                                "additionalProperties": false
                            ]
                        ],
                        "revisedNarrative": [
                            "type": "string",
                            "description": "REQUIRED when verdict is revise: the full narrative with unsupported claims removed, everything else preserved verbatim"
                        ]
                    ],
                    "required": ["cardIndex", "cardId", "verdict", "unsupportedClaims", "anchorsValid"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["verdicts"],
        "additionalProperties": false
    ]
}

// MARK: - Response Types

/// Batched verification response: one verdict per audited card.
struct CardVerificationResponse: Codable, Sendable {
    let verdicts: [CardVerificationVerdict]
}

enum CardVerdict: String, Codable, Sendable {
    case keep
    case revise
    case drop
}

struct CardVerificationVerdict: Codable, Sendable {
    let cardIndex: Int
    let cardId: String
    let verdict: CardVerdict
    let unsupportedClaims: [String]
    let anchorsValid: Bool
    let repairedAnchors: [RepairedEvidenceAnchor]?
    let revisedNarrative: String?
}

/// One anchor in the card's COMPLETE replacement anchor set supplied by the
/// verification pass when `anchorsValid` is false (valid originals echoed
/// unchanged, broken ones corrected, unrepairable ones omitted). The set
/// wholesale-replaces the card's anchors.
struct RepairedEvidenceAnchor: Codable, Sendable {
    let documentId: String
    let location: String
    let verbatimExcerpt: String?
}
