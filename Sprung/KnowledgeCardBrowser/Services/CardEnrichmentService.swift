//
//  CardEnrichmentService.swift
//  Sprung
//
//  Enriches KnowledgeCards with structured fact extraction.
//  Fact extraction uses Anthropic structured output against a cached source
//  block — either the actual PDF (Files API document block) or text.
//

import Foundation
import SwiftOpenAI

/// Service that enriches knowledge cards with structured facts.
actor CardEnrichmentService {
    private let llmFacade: LLMFacade

    init(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }

    // MARK: - Public API

    /// Enrich a single card with structured fact extraction from source text.
    /// - Parameters:
    ///   - card: The card to enrich (must have narrative content)
    ///   - sourceText: Source document text for evidence extraction
    func enrichCard(
        _ card: KnowledgeCard,
        sourceText: String
    ) async throws {
        try await enrichCard(
            card,
            source: .text(AnthropicDocumentAnalysisService.sourceTextBlock(
                filename: card.title,
                text: String(sourceText.prefix(150_000))
            ))
        )
    }

    /// Enrich a single card with structured fact extraction from an analysis source
    /// (uploaded PDF or text block).
    /// - Parameter voiceAnchor: Optional voice-anchoring text (Phase 1 voice
    ///   profile + writing-sample excerpts), injected into the user content
    ///   AFTER the cached source block. Must be byte-stable across the
    ///   narrative passes of an analysis run so the anchored prefix caches.
    func enrichCard(
        _ card: KnowledgeCard,
        source: DocumentAnalysisSource,
        voiceAnchor: String? = nil
    ) async throws {
        try await extractFacts(for: card, source: source, voiceAnchor: voiceAnchor)
    }

    // MARK: - Fact Extraction

    private func extractFacts(for card: KnowledgeCard, source: DocumentAnalysisSource, voiceAnchor: String?) async throws {
        let modelId = try AnthropicDocumentAnalysisService.configuredModelId(operationName: "Fact Extraction")

        let instructions = buildFactExtractionPrompt(card: card, isPagedSource: source.isPaged)

        let result: FactExtractionResult = try await llmFacade.executeStructuredWithAnthropicBlocks(
            systemContent: DocumentAnalysisPrompts.systemBlocks,
            userBlocks: DocumentAnalysisPrompts.userBlocks(
                source: source, voiceAnchor: voiceAnchor, instructions: instructions
            ),
            modelId: modelId,
            responseType: FactExtractionResult.self,
            schema: Self.factExtractionSchema,
            maxTokens: 32768
        )

        // Write results to card fields
        await MainActor.run {
            if !result.facts.isEmpty {
                card.facts = result.facts
            }
            if !result.suggestedBullets.isEmpty {
                card.suggestedBullets = result.suggestedBullets
            }
            if !result.outcomes.isEmpty {
                if let data = try? JSONEncoder().encode(result.outcomes),
                   let json = String(data: data, encoding: .utf8) {
                    card.outcomesJSON = json
                }
            }
            if !result.technologies.isEmpty {
                card.technologies = result.technologies
            }
            if !result.verbatimExcerpts.isEmpty {
                card.verbatimExcerpts = result.verbatimExcerpts
            }
            // Baseline grade only — never overwrite an existing value. The
            // document-analysis fabrication guard downgrades a card to "weak"
            // (during verification, which runs BEFORE enrichment) when its anchors
            // couldn't be verified, and the user can grade manually; both are
            // authoritative over this LLM baseline.
            if (card.evidenceQuality ?? "").isEmpty, !result.evidenceQuality.isEmpty {
                card.evidenceQuality = result.evidenceQuality
            }
        }

        Logger.info("CardEnrichmentService: Extracted \(result.facts.count) facts, \(result.suggestedBullets.count) bullets for \(card.title)", category: .ai)
    }

    // MARK: - Prompt Building

    private func buildFactExtractionPrompt(card: KnowledgeCard, isPagedSource: Bool) -> String {
        let locationGuidance = isPagedSource
            ? "`location` MUST be page-anchored — cite the page for every fact (\"p. 14\", \"p. 3, Fig. 2\")"
            : "`location` (section/paragraph)"
        let excerptLocationGuidance = isPagedSource
            ? "Where in the source — MUST cite the page the passage appears on (\"p. 14\")"
            : "Where in the source"

        return """
        You are a FACT EXTRACTION agent. Extract STRUCTURED FACTS from the source text for the \
        knowledge card described below.

        ## Card Information

        **Title**: \(card.title)
        **Type**: \(card.cardType?.displayName ?? "General")
        **Organization**: \(card.organization ?? "Not specified")
        **Time Period**: \(card.dateRange ?? "Not specified")

        **Card Narrative** (for context on what to extract):
        \(card.narrative)

        ## Fact Categories

        Extract facts into these categories:

        | Category | Description |
        |----------|-------------|
        | `technical_decision` | Design choice WITH rationale |
        | `problem_solved` | TECHNICAL/DOMAIN root cause + resolution |
        | `capability_built` | System, tool, or process created |
        | `artifact_produced` | Tangible deliverable |
        | `responsibility` | Role, scope, authority |
        | `scope_indicator` | Scale/complexity evidence |
        | `collaboration` | Team/stakeholder interaction |
        | `recognition` | External validation |
        | `context` | Situation, constraints, environment |
        | `research_process` | How an investigation was structured, iterated, and validated |
        | `experimental_design` | Design of experiments, controls, and validity reasoning |
        | `ambiguity_navigated` | Progress made under unclear requirements or unknowns |
        | `instrument_built` | Apparatus or measurement capability constructed for the work |
        | `analysis_method` | Analytical or computational technique applied or developed |
        | `cross_disciplinary_synthesis` | Methods or insight connected across fields |

        When the source material is research/R&D-flavored, the intellectual contribution, \
        the process maturity, and the judgment shown ARE the extractable value — prefer the \
        research-oriented categories above and match the register of the source rather than \
        distilling to quantitative business metrics.

        ## Resume Fitness Filter

        Every extracted fact should pass this test: "Would including this on a resume help the \
        applicant get an interview?"

        **Extract:** Technical decisions, research findings, measurable outcomes, scope/scale \
        evidence, skills demonstrated, recognition received, capabilities built, qualitative \
        significance of results.

        **Do NOT extract:** Performance criticisms, negative feedback, interpersonal conflicts, \
        self-assessments of weakness, failure admissions, anything a hiring manager would \
        perceive as a red flag.

        ## Output Fields

        ### facts[]
        Raw evidence with source attribution. One fact per entry. Include:
        - `category`: One of the categories above
        - `statement`: The factual observation
        - `confidence`: "high", "medium", or "low"
        - `source`: Object with `artifact_id` (use "source_doc"), \(locationGuidance), \
        `verbatim_quote` (30-100 chars from source)

        ### suggested_bullets[]
        3-5 draft resume bullets combining related facts. Each should read like a sentence \
        the author would actually say about their work — concrete and specific. Include a \
        metric only when the number itself carries information an outsider needs. Never \
        force an "[verbed] [task] resulting in [number]% improvement" mold; vary sentence \
        structure across bullets. Use [BRACKETED_PLACEHOLDERS] only for genuinely unknown \
        specifics, never as a sentence skeleton. Match the register of the source \
        (research vs corporate vs academic).

        ### outcomes[]
        What CHANGED because of this work. Qualitative is fine. Focus on the delta, not the activity.

        ### technologies[]
        All technologies, tools, frameworks, and methodologies demonstrated.

        ### evidence_quality
        Grade how well THIS card's narrative is grounded in the source document, as one of:
        - `strong`: claims are directly and specifically supported — named artifacts, \
        quoted passages, concrete numbers, or unambiguous descriptions in the source.
        - `moderate`: claims are reasonably grounded but partly inferred, generalized, \
        or supported only in passing.
        - `weak`: claims rest mostly on narrative assertion with little corroborating \
        detail in the source. Grade honestly — do not inflate.

        ### verbatim_excerpts[]
        1-3 passages (100-500 words each) worth preserving verbatim. Each with:
        - `context`: What this excerpt demonstrates
        - `location`: \(excerptLocationGuidance)
        - `text`: The verbatim passage
        - `preservation_reason`: Why this matters

        ## Source Document

        The source document is provided at the start of this message.

        Extract facts now.
        """
    }

    // MARK: - Source Resolution

    /// Resolve the source text a card should be enriched against.
    ///
    /// Resolution order:
    /// 1. Evidence-anchor document ID → artifact UUID lookup
    /// 2. Evidence-anchor document ID → the artifact's ORIGINAL pipeline ID
    ///    (persistence assigns a fresh UUID; the extraction-time ID the
    ///    anchors reference survives at metadataJSON.id)
    /// 3. Evidence-anchor document ID → artifact filename match (git cards
    ///    anchor with the repo name, chat cards with a non-UUID string id)
    /// 4. The card's own narrative — self-grounded, never another document.
    ///
    /// There is deliberately NO "any artifact" fallback: enriching a card
    /// against an unrelated document cross-contaminates its facts and
    /// technologies with another card's content.
    @MainActor
    static func resolveSourceText(for card: KnowledgeCard, artifactStore: ArtifactRecordStore?) -> String {
        guard let store = artifactStore else { return card.narrative }

        for anchor in card.evidenceAnchors {
            if let artifact = store.artifact(byIdString: anchor.documentId),
               !artifact.extractedContent.isEmpty {
                return artifact.extractedContent
            }
        }

        let allArtifacts = store.allArtifacts
        for anchor in card.evidenceAnchors {
            if let artifact = allArtifacts.first(where: {
                !$0.extractedContent.isEmpty
                    && ($0.metadataString("id") == anchor.documentId || $0.filename == anchor.documentId)
            }) {
                return artifact.extractedContent
            }
        }

        Logger.info(
            "✨ No source artifact resolved for \"\(card.title)\" — enriching from the card's own narrative",
            category: .ai
        )
        return card.narrative
    }

    // MARK: - JSON Schema for Structured Output

    static let factExtractionSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "facts": [
                "type": "array",
                "description": "Extracted facts with source attribution",
                "items": [
                    "type": "object",
                    "properties": [
                        "category": [
                            "type": "string",
                            "enum": ["technical_decision", "problem_solved", "capability_built",
                                     "artifact_produced", "responsibility", "scope_indicator",
                                     "collaboration", "recognition", "context",
                                     "research_process", "experimental_design", "ambiguity_navigated",
                                     "instrument_built", "analysis_method", "cross_disciplinary_synthesis"],
                            "description": "Fact category"
                        ],
                        "statement": [
                            "type": "string",
                            "description": "The factual observation"
                        ],
                        "confidence": [
                            "type": "string",
                            "enum": ["high", "medium", "low"],
                            "description": "Evidence quality"
                        ],
                        "source": [
                            "type": "object",
                            "properties": [
                                "artifact_id": ["type": "string"],
                                "location": ["type": "string"],
                                "verbatim_quote": ["type": "string"]
                            ],
                            "required": ["artifact_id", "location"],
                            "additionalProperties": false
                        ]
                    ],
                    "required": ["category", "statement", "confidence"],
                    "additionalProperties": false
                ]
            ],
            "suggested_bullets": [
                "type": "array",
                "description": "Draft resume bullets in the author's natural register; placeholders only for genuinely unknown specifics",
                "items": ["type": "string"]
            ],
            "outcomes": [
                "type": "array",
                "description": "What changed because of this work",
                "items": ["type": "string"]
            ],
            "technologies": [
                "type": "array",
                "description": "Technologies, tools, and frameworks",
                "items": ["type": "string"]
            ],
            "verbatim_excerpts": [
                "type": "array",
                "description": "Passages worth preserving verbatim",
                "items": [
                    "type": "object",
                    "properties": [
                        "context": ["type": "string"],
                        "location": ["type": "string"],
                        "text": ["type": "string"],
                        "preservation_reason": ["type": "string"]
                    ],
                    "required": ["context", "location", "text", "preservation_reason"],
                    "additionalProperties": false
                ]
            ],
            "evidence_quality": [
                "type": "string",
                "enum": ["strong", "moderate", "weak"],
                "description": "How well the card's claims are grounded in the source document"
            ]
        ],
        "required": ["facts", "suggested_bullets", "outcomes", "technologies", "verbatim_excerpts", "evidence_quality"],
        "additionalProperties": false
    ]
}

// MARK: - Result Types

private struct FactExtractionResult: Codable, Sendable {
    let facts: [KnowledgeCardFact]
    let suggestedBullets: [String]
    let outcomes: [String]
    let technologies: [String]
    let verbatimExcerpts: [VerbatimExcerpt]
    let evidenceQuality: String

    enum CodingKeys: String, CodingKey {
        case facts
        case suggestedBullets = "suggested_bullets"
        case outcomes
        case technologies
        case verbatimExcerpts = "verbatim_excerpts"
        case evidenceQuality = "evidence_quality"
    }
}
