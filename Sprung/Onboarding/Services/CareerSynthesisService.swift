//
//  CareerSynthesisService.swift
//  Sprung
//
//  Generates the candidate's career through-lines synthesis — the cross-cutting
//  prose portrait that no single knowledge card captures alone. Reads across all
//  knowledge cards, the skill bank, and existing strategic notes; writes a rich,
//  evidence-grounded narrative that feeds resume customization and seed
//  generation as positioning fuel.
//
//  This is a read-over-existing-artifacts pass: it consumes already-extracted
//  cards/skills (no document re-ingest, no re-transcription), so it is cheap to
//  (re)run from the onboarding debug panel.
//

import Foundation
import SwiftOpenAI

enum CareerSynthesisError: LocalizedError {
    case noEvidence

    var errorDescription: String? {
        switch self {
        case .noEvidence:
            return "Cannot synthesize career through-lines: no knowledge cards are available."
        }
    }
}

@MainActor
final class CareerSynthesisService {
    private let llmFacade: LLMFacade

    init(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }

    /// Single rich-prose field. Deliberately NOT a section-by-section schema —
    /// forcing fixed sections would pigeonhole the portrait into a standard form.
    /// The model organizes the narrative around whatever through-lines the
    /// evidence actually supports.
    private struct SynthesisResult: Codable {
        let throughLines: String
    }

    private var responseSchema: [String: Any] {
        [
            "type": "object",
            "properties": ["throughLines": ["type": "string"]],
            "required": ["throughLines"],
            "additionalProperties": false
        ]
    }

    /// Generate the career through-lines synthesis from the candidate's evidence
    /// base. Returns the narrative text; the caller persists it (e.g.
    /// `CandidateDossierStore.setCareerThroughLines`).
    ///
    /// - Parameters:
    ///   - cards: every knowledge card (the primary evidence).
    ///   - skills: the skill bank (breadth signal).
    ///   - strategicNotes: orientation only — the dossier's job-search context,
    ///     strengths, and pitfalls. Excludes private circumstances and the prior
    ///     synthesis (so a regeneration never feeds on its own output).
    func generate(
        cards: [KnowledgeCard],
        skills: [Skill],
        strategicNotes: String?
    ) async throws -> String {
        guard !cards.isEmpty else { throw CareerSynthesisError.noEvidence }

        let modelId = try AnthropicDocumentAnalysisService.configuredModelId(
            operationName: "Career Synthesis"
        )

        let systemBlocks = [AnthropicSystemBlock(text: Self.systemPrompt)]
        let userBlocks: [AnthropicContentBlock] = [
            .text(AnthropicTextBlock(text: buildSourceContext(
                cards: cards, skills: skills, strategicNotes: strategicNotes
            )))
        ]

        let result: SynthesisResult = try await llmFacade.executeStructuredWithAnthropicBlocks(
            systemContent: systemBlocks,
            userBlocks: userBlocks,
            modelId: modelId,
            responseType: SynthesisResult.self,
            schema: responseSchema,
            maxTokens: 32768
        )

        let text = result.throughLines.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.info("CareerSynthesisService: synthesized through-lines (\(text.count) chars) from \(cards.count) cards", category: .ai)
        return text
    }

    // MARK: - The Brief (quality centerpiece)

    private static let systemPrompt = """
    You are a career analyst writing a private synthesis about one person. Your reader is \
    NOT that person and NOT a recruiter — it is another AI agent that will later customize \
    resumes and cover letters for specific jobs. Your job is to hand that agent the rich, \
    true, cross-cutting understanding of this candidate that no single document holds.

    You are given the candidate's full evidence base: knowledge cards (each a narrative \
    about one project, role, or achievement, with grounded facts, outcomes, technologies, \
    and verbatim excerpts in the candidate's own words), the skill bank, and any existing \
    strategic notes for orientation.

    Write the candidate's CAREER THROUGH-LINES: the recurring instincts, methods, and \
    values that connect otherwise-disparate work; the genuine arc of how they got from \
    where they started to where they are now; the tensions and contradictions that make \
    them a specific person rather than a generic candidate; and the distinctive strengths \
    that only become visible when you read everything at once.

    WHAT MAKES THIS GOOD:
    - Through-lines, not a summary. Do NOT restate the cards one by one. Find what REPEATS \
      across them — the instinct behind the projects, the method that shows up in every \
      domain — and name the connective tissue explicitly.
    - Specific, not abstract. Every claim earns its place by pointing to a concrete artifact \
      in the evidence: name the actual project, system, paper, or decision. An abstraction \
      with no artifact behind it is worthless and must be cut.
    - Subtle, not flat. Capture nuance, register, and contradiction — the person who is one \
      way in this context and another way in that one. A rich portrait holds tension; slop \
      sands it off. Surface the non-obvious read, not the obvious one.
    - Honest above all. Ground EVERYTHING in the evidence provided. Invent nothing: no \
      metrics, dates, titles, employers, technologies, or accomplishments that are not in \
      the cards. If a pattern is real but thinly supported, say so plainly rather than \
      inflating it. A hallucination here silently poisons every downstream resume.

    HOW TO WRITE IT:
    - Flowing analytical prose in clear, plain, specific English. This is analysis for a \
      colleague — not marketing copy, and not a ventriloquized version of the candidate's \
      own voice.
    - Absolutely no resume / LinkedIn slop. FORBIDDEN: the formula "[Verb] [thing] resulting \
      in [X]% improvement"; buzzwords ("leveraged", "spearheaded", "drove results", \
      "cross-functional", "results-driven", "passionate about", "proven track record"); \
      vague intensifiers ("significantly", "extensive", "robust"); and any fabricated number.
    - Do not force a fixed template or section headers. Organize around the through-lines you \
      actually find, in whatever shape fits THIS person — some have one dominant thread, \
      some have several. Let the evidence decide the structure.
    - Length: as long as the material genuinely supports, and no longer. Depth over coverage. \
      Cut anything you cannot ground in a specific piece of evidence.

    Return JSON exactly as: {"throughLines": "<your synthesis>"}
    """

    // MARK: - Source Context

    private func buildSourceContext(
        cards: [KnowledgeCard],
        skills: [Skill],
        strategicNotes: String?
    ) -> String {
        var lines: [String] = []

        if let notes = strategicNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append("# Existing Strategic Notes (orientation only — do not merely restate)")
            lines.append("")
            lines.append(notes)
            lines.append("")
        }

        lines.append("# Knowledge Cards (\(cards.count)) — the primary evidence")
        lines.append("")
        // Stable order so re-runs read the evidence the same way.
        let orderedCards = cards.sorted { ($0.dateRange ?? "") < ($1.dateRange ?? "") }
        for card in orderedCards {
            lines.append(renderCard(card))
            lines.append("")
        }

        if !skills.isEmpty {
            lines.append("# Skill Bank (breadth signal)")
            lines.append("")
            let categories = SkillCategoryUtils.sortedCategories(from: skills)
            for category in categories {
                let names = skills
                    .filter { SkillCategoryUtils.normalizeCategory($0.categoryRaw) == category }
                    .map { $0.canonical }
                    .sorted()
                guard !names.isEmpty else { continue }
                lines.append("- \(category): \(names.joined(separator: ", "))")
            }
            lines.append("")
        }

        lines.append("---")
        lines.append("Now write the candidate's career through-lines per your brief. Ground every claim in the evidence above.")

        return lines.joined(separator: "\n")
    }

    /// Render a card's full evidence: header, narrative, and the grounded
    /// enrichment fields. The synthesis needs the substance, not a preview.
    private func renderCard(_ card: KnowledgeCard) -> String {
        var parts: [String] = ["## \(card.title)"]

        var meta: [String] = []
        if let type = card.cardType?.displayName { meta.append(type) }
        if let org = card.organization, !org.isEmpty { meta.append(org) }
        if let dates = card.dateRange, !dates.isEmpty { meta.append(dates) }
        if !meta.isEmpty { parts.append("_\(meta.joined(separator: " · "))_") }

        if !card.narrative.isEmpty {
            parts.append(card.narrative)
        }

        let facts = card.facts
        if !facts.isEmpty {
            parts.append("Facts: " + facts.map { $0.statement }.joined(separator: " "))
        }

        let outcomes = card.outcomes
        if !outcomes.isEmpty {
            parts.append("Outcomes: " + outcomes.joined(separator: "; "))
        }

        let technologies = card.technologies
        if !technologies.isEmpty {
            parts.append("Technologies: " + technologies.joined(separator: ", "))
        }

        let excerpts = card.verbatimExcerpts
        if !excerpts.isEmpty {
            parts.append("In the candidate's own words: " + excerpts.map { "\"\($0.text)\"" }.joined(separator: " "))
        }

        return parts.joined(separator: "\n")
    }
}
