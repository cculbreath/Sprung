//
//  AnthropicDocumentAnalysisService.swift
//  Sprung
//
//  Orchestrates the Anthropic-native document-analysis passes (summary,
//  skill bank, narrative cards, enrichment) around prompt caching.
//
//  PDFs are uploaded once per chunk via the Files API and every pass sees the
//  ACTUAL PDF (figures, tables, layout) through a document block. Text-based
//  sources use the same pass structure with a cached text block instead —
//  one code path through content blocks.
//

import Foundation
import SwiftOpenAI

// MARK: - DocumentAnalysisSource

/// Source content for an Anthropic document-analysis pass.
enum DocumentAnalysisSource {
    /// Uploaded PDF referenced by its Files API id; passes see the actual PDF.
    case pdfFile(id: String)
    /// Plain text (txt/docx/rtf/html native extraction, or stored artifact text).
    case text(String)

    /// True when locations in the source are page-addressable (evidence anchors
    /// must then be page-anchored, e.g. "p. 14" or "p. 3, Fig. 2").
    var isPaged: Bool {
        if case .pdfFile = self { return true }
        return false
    }

    /// The cached source block. Placed FIRST in every pass's user content so all
    /// passes share one prompt prefix (system + source) and reuse the prompt cache
    /// warmed by the first pass.
    var cachedContentBlock: AnthropicContentBlock {
        switch self {
        case .pdfFile(let id):
            return .document(AnthropicDocumentBlock(
                source: .file(id: id),
                cacheControl: .ephemeral
            ))
        case .text(let text):
            return .text(AnthropicTextBlock(text: text, cacheControl: .ephemeral))
        }
    }
}

// MARK: - DocumentAnalysisPrompts

enum DocumentAnalysisPrompts {
    /// System prompt shared by ALL analysis passes (summary, skills, cards,
    /// verification, enrichment). It must stay byte-identical across passes:
    /// prompt caching is a strict prefix match over tools → system → messages,
    /// so a per-pass system prompt would fork the prefix and the expensive
    /// per-document source-block cache entry would be paid twice. The voice
    /// anchor for the narrative passes therefore lives in the user content
    /// AFTER the cached source block (see `userBlocks`), never in system.
    static let sharedSystemPrompt = """
    You are a meticulous document-analysis assistant for a resume-building application. \
    Ground every claim in the source document provided at the start of the user message, \
    and respond with well-structured JSON that conforms exactly to the requested schema.
    """

    static var systemBlocks: [AnthropicSystemBlock] {
        [AnthropicSystemBlock(text: sharedSystemPrompt)]
    }

    /// Build the user content for one pass: the cached source block first, then
    /// the optional voice anchor (narrative passes only), then the pass-specific
    /// instructions.
    ///
    /// The anchor sits AFTER the source block so every pass — anchored or not —
    /// shares the single (system + source) cache entry warmed by the first pass;
    /// the document is ingested exactly once per chunk. The anchor carries its
    /// own cache breakpoint (2 total ≤ 4) so the narrative passes additionally
    /// share a (system + source + anchor) entry written by the cards pass; the
    /// incremental write is just the anchor's few hundred tokens.
    static func userBlocks(
        source: DocumentAnalysisSource,
        voiceAnchor: String? = nil,
        instructions: String
    ) -> [AnthropicContentBlock] {
        var blocks: [AnthropicContentBlock] = [source.cachedContentBlock]
        if let voiceAnchor, !voiceAnchor.isEmpty {
            blocks.append(.text(AnthropicTextBlock(text: voiceAnchor, cacheControl: .ephemeral)))
        }
        blocks.append(.text(AnthropicTextBlock(text: instructions)))
        return blocks
    }

    // MARK: - Voice Anchoring

    /// Total character budget for representative writing-sample excerpts.
    static let voiceExcerptBudget = 1200

    /// Render the voice-anchoring text from the Phase 1 voice profile and
    /// writing samples (injected into the user content of the narrative passes
    /// after the cached source block). Deterministic by construction (stable
    /// sort, bounded excerpts, no timestamps) so the rendered text is
    /// byte-identical across passes and documents within a session. Returns nil
    /// when there is nothing to inject — no placeholder text.
    static func voiceAnchorText(profile: VoiceProfile?, writingSamples: [String]) -> String? {
        var sections: [String] = []

        if let profile {
            var lines: [String] = []
            lines.append("- Enthusiasm: \(profile.enthusiasm.displayName)")
            lines.append("- Person: \(profile.useFirstPerson ? "first person (I built, I discovered)" : "third person")")
            lines.append("- Connective style: \(profile.connectiveStyle)")
            if !profile.aspirationalPhrases.isEmpty {
                lines.append("- Aspirational phrases: \(profile.aspirationalPhrases.joined(separator: ", "))")
            }
            if !profile.avoidPhrases.isEmpty {
                lines.append("- Never use: \(profile.avoidPhrases.joined(separator: ", "))")
            }
            if let register = profile.vocabularyRegister, !register.isEmpty {
                lines.append("- Vocabulary register: \(register)")
            }
            if let modulation = profile.registerModulation, !modulation.isEmpty {
                lines.append("- Register modulation: \(modulation)")
            }
            // Curated excerpts are LLM-selected for voice-distinctiveness —
            // higher signal per token than the raw-sample excerpt below, which
            // stays for paragraph-scale sentence rhythm.
            if !profile.sampleExcerpts.isEmpty {
                let curated = profile.sampleExcerpts
                    .map { "  - \"\($0)\"" }
                    .joined(separator: "\n")
                lines.append("- Curated voice excerpts:\n\(curated)")
            }
            sections.append("## Author Voice Profile\n\n" + lines.joined(separator: "\n"))
        }

        let excerpts = representativeExcerpts(from: writingSamples)
        if !excerpts.isEmpty {
            let rendered = excerpts.enumerated()
                .map { "Excerpt \($0.offset + 1):\n\"\($0.element)\"" }
                .joined(separator: "\n\n")
            sections.append("## Representative Writing Samples\n\n" + rendered)
        }

        guard !sections.isEmpty else { return nil }

        return """
        This is how the author describes their own work — match this register when writing \
        narratives, bullets, and excerpts. Preserve the author's natural sentence rhythm and \
        vocabulary; never compress their voice into formulaic resume bullet patterns.

        \(sections.joined(separator: "\n\n"))
        """
    }

    /// Pick 1–2 representative writing-sample excerpts, bounded to
    /// `voiceExcerptBudget` characters total. Samples are sorted before
    /// selection so the result is deterministic regardless of store ordering.
    private static func representativeExcerpts(from samples: [String]) -> [String] {
        let cleaned = samples
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        guard !cleaned.isEmpty else { return [] }

        let selected = cleaned.prefix(2)
        let perExcerpt = voiceExcerptBudget / selected.count
        return selected.map { truncatedAtWordBoundary($0, limit: perExcerpt) }
    }

    private static func truncatedAtWordBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let prefix = String(text.prefix(limit))
        if let lastSpace = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(prefix[..<lastSpace]) + "…"
        }
        return prefix + "…"
    }
}

// MARK: - AnthropicDocumentAnalysisService

/// Runs the document-analysis pass set against a single source with a shared,
/// cached prompt prefix:
///
/// 1. Summary FIRST (awaited — warms the prompt cache for the document prefix)
/// 2. Skill bank + narrative-card extraction concurrently
/// 3. Verification after cards (awaited) — one batched adversarial grounding
///    check per document/chunk against the same cached source; unsupported
///    claims are stripped, broken anchors repaired or downgraded, fabricated
///    cards dropped BEFORE enrichment can elaborate on them
/// 4. Enrichment after verification (sees the document + the verified cards)
///
/// All five passes share ONE system prefix and ONE cached source block per
/// document/chunk. When a Phase 1 voice profile / writing samples exist, the
/// narrative passes (cards, verification, enrichment) additionally inject a
/// voice-anchor text block AFTER the cached source block in the user content;
/// the summary and skill passes omit it.
///
/// Multi-chunk PDFs run the pass set per chunk; results are concatenated and
/// summaries are joined with "Part N (pages X–Y):" labels.
actor AnthropicDocumentAnalysisService {

    /// UserDefaults key for the single model used by all document-analysis passes.
    static let modelSettingKey = "onboardingDocAnalysisModelId"

    /// Maximum characters for text-based sources. Text documents are capped here
    /// (single choke point for all text paths) and go in one pass — no chunking.
    static let textInputLimit = 200_000

    struct PassSelection {
        var summary = true
        var skills = true
        var narrativeCards = true
        var enrichment = true

        static let all = PassSelection()
        static let summaryOnly = PassSelection(summary: true, skills: false, narrativeCards: false, enrichment: false)
        static let knowledgeOnly = PassSelection(summary: false, skills: true, narrativeCards: true, enrichment: true)
    }

    struct AnalysisResult {
        var summary: DocumentSummary?
        var skills: [Skill]?
        var narrativeCards: [KnowledgeCard]?
        /// Human-readable descriptions of analysis passes that failed after
        /// exhausting retries (e.g. "skills (pages 1–50): Status 400 …").
        /// Empty when every requested pass succeeded. Callers surface these to
        /// the event log and the user — a failed pass must never silently
        /// masquerade as "0 results".
        var passFailures: [String] = []
    }

    private let llmFacade: LLMFacade
    private let preflightService: PDFPreflightService
    private let skillBankService: SkillBankService
    private let kcExtractionService: KnowledgeCardExtractionService
    private let enrichmentService: CardEnrichmentService

    /// Supplies the rendered voice-anchor text (nil when no voice profile /
    /// writing samples exist). Resolved once per service instance so the
    /// anchor is byte-stable across passes and documents in a session; the
    /// container re-installs the provider (dropping this instance) when
    /// voice-primer extraction completes.
    private let voiceAnchorProvider: (@Sendable () async -> String?)?
    private var voiceAnchorResolved = false
    private var voiceAnchorCache: String?

    init(
        llmFacade: LLMFacade,
        skillBankService: SkillBankService,
        kcExtractionService: KnowledgeCardExtractionService,
        voiceAnchorProvider: (@Sendable () async -> String?)? = nil
    ) {
        self.llmFacade = llmFacade
        self.preflightService = PDFPreflightService(llmFacade: llmFacade)
        self.skillBankService = skillBankService
        self.kcExtractionService = kcExtractionService
        self.enrichmentService = CardEnrichmentService(llmFacade: llmFacade)
        self.voiceAnchorProvider = voiceAnchorProvider
    }

    /// Resolve (and memoize) the voice anchor for this service instance.
    /// A concurrent double-resolution is harmless: the provider is
    /// deterministic, so both resolutions yield identical bytes.
    private func resolveVoiceAnchor() async -> String? {
        if voiceAnchorResolved { return voiceAnchorCache }
        let anchor = await voiceAnchorProvider?()
        voiceAnchorCache = anchor
        voiceAnchorResolved = true
        if let anchor {
            Logger.info("🎤 Voice anchoring active for narrative passes (\(anchor.count) chars)", category: .ai)
        }
        return anchor
    }

    /// Resolve the configured document-analysis model or throw so the UI layer
    /// can surface the model settings picker.
    static func configuredModelId(operationName: String = "Document Analysis") throws -> String {
        guard let modelId = UserDefaults.standard.string(forKey: modelSettingKey), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: modelSettingKey,
                operationName: operationName
            )
        }
        return modelId
    }

    // MARK: - Public API

    /// Analyze a PDF. Each chunk is uploaded once via the Files API, all passes run
    /// against the same cached document prefix, and the file is deleted best-effort
    /// when the chunk's passes finish.
    func analyzePDF(
        documentId: String,
        filename: String,
        pdfData: Data,
        passes: PassSelection = .all,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> AnalysisResult {
        let modelId = try Self.configuredModelId()

        statusCallback?("Preparing \(filename) for analysis...")
        let chunks = try await preflightService.makeChunks(pdfData: pdfData, filename: filename, modelId: modelId)

        var merged = AnalysisResult()
        var summaryParts: [(pageRange: ClosedRange<Int>, summary: DocumentSummary)] = []

        for chunk in chunks {
            let chunkLabel = chunks.count > 1
                ? "\(filename) (pages \(chunk.pageRange.lowerBound)–\(chunk.pageRange.upperBound))"
                : filename

            statusCallback?("Uploading \(chunkLabel)...")
            let file = try await llmFacade.anthropicUploadFile(
                data: chunk.data,
                filename: chunkFilename(filename, chunk: chunk, totalChunks: chunks.count),
                mimeType: "application/pdf"
            )
            Logger.info("📄 Uploaded \(chunkLabel) to Anthropic Files API: \(file.id)", category: .ai)

            let result = await runPasses(
                documentId: documentId,
                filename: chunkLabel,
                source: .pdfFile(id: file.id),
                passes: passes,
                modelId: modelId,
                statusCallback: statusCallback
            )

            deleteFileBestEffort(file.id)

            if let summary = result.summary {
                summaryParts.append((chunk.pageRange, summary))
            }
            if let skills = result.skills {
                merged.skills = (merged.skills ?? []) + skills
            }
            if let cards = result.narrativeCards {
                merged.narrativeCards = (merged.narrativeCards ?? []) + cards
            }
            merged.passFailures += result.passFailures
        }

        merged.summary = mergeSummaries(summaryParts, totalChunks: chunks.count)
        return merged
    }

    /// Analyze a text-based source (txt/docx/rtf/html native extraction, or stored
    /// artifact text). Same pass structure as PDFs, with a cached text block.
    func analyzeText(
        documentId: String,
        filename: String,
        text: String,
        passes: PassSelection = .all,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> AnalysisResult {
        let modelId = try Self.configuredModelId()
        let source = DocumentAnalysisSource.text(Self.sourceTextBlock(filename: filename, text: text))
        return await runPasses(
            documentId: documentId,
            filename: filename,
            source: source,
            passes: passes,
            modelId: modelId,
            statusCallback: statusCallback
        )
    }

    /// Wrap raw document text in a stable header so the cached source block is
    /// self-describing and byte-identical across passes. Text is capped at
    /// `textInputLimit` characters.
    static func sourceTextBlock(filename: String, text: String) -> String {
        """
        # Source Document: \(filename)

        \(text.prefix(Self.textInputLimit))
        """
    }

    // MARK: - Pass Orchestration

    private func runPasses(
        documentId: String,
        filename: String,
        source: DocumentAnalysisSource,
        passes: PassSelection,
        modelId: String,
        statusCallback: (@Sendable (String) -> Void)?
    ) async -> AnalysisResult {
        var result = AnalysisResult()

        // Resolved once per service instance; nil when no voice profile or
        // writing samples exist. Used only by the narrative passes.
        let voiceAnchor = await resolveVoiceAnchor()

        // Pass 1: summary FIRST — awaiting it warms the prompt cache for the
        // shared (system + source) prefix used by every subsequent pass.
        if passes.summary {
            statusCallback?("Summarizing \(filename)...")
            do {
                result.summary = try await generateSummary(filename: filename, source: source, modelId: modelId)
                Logger.info("✅ Summary generated for \(filename) (\(result.summary?.summary.count ?? 0) chars)", category: .ai)
            } catch {
                Logger.warning("⚠️ Summary pass failed for \(filename): \(error.localizedDescription)", category: .ai)
                result.passFailures.append("summary — \(filename): \(error.localizedDescription)")
            }
        }

        // Pass 2: skill bank + narrative cards against the warmed prefix.
        // A cache entry only becomes readable once the first response begins
        // streaming, so if no earlier pass warmed the cache (e.g. knowledgeOnly
        // skips the summary) two concurrent passes would EACH pay full document
        // input cost — run sequentially in that case (warm-then-continue).
        if passes.skills || passes.narrativeCards {
            statusCallback?("Extracting skills and narrative cards from \(filename)...")

            let skillsOutcome: Result<[Skill], Error>?
            let cardsOutcome: Result<[KnowledgeCard], Error>?
            if passes.skills && passes.narrativeCards && !passes.summary {
                skillsOutcome = await extractSkills(documentId: documentId, filename: filename, source: source)
                cardsOutcome = await extractCards(
                    documentId: documentId, filename: filename, source: source, voiceAnchor: voiceAnchor
                )
            } else {
                async let skillsTask: Result<[Skill], Error>? = passes.skills
                    ? extractSkills(documentId: documentId, filename: filename, source: source)
                    : nil
                async let cardsTask: Result<[KnowledgeCard], Error>? = passes.narrativeCards
                    ? extractCards(documentId: documentId, filename: filename, source: source, voiceAnchor: voiceAnchor)
                    : nil

                (skillsOutcome, cardsOutcome) = await (skillsTask, cardsTask)
            }

            switch skillsOutcome {
            case .success(let skills): result.skills = skills
            case .failure(let error):
                result.passFailures.append("skill extraction — \(filename): \(error.localizedDescription)")
            case nil: break
            }
            switch cardsOutcome {
            case .success(let cards): result.narrativeCards = cards
            case .failure(let error):
                result.passFailures.append("narrative cards — \(filename): \(error.localizedDescription)")
            case nil: break
            }
        }

        // Pass 3: verification (awaited) — one batched adversarial grounding
        // check against the same cached source block. Runs BEFORE enrichment so
        // enrichment never elaborates on hallucinated claims. A verification
        // failure keeps the cards: it is a quality gate, not a point of failure.
        if let cards = result.narrativeCards, !cards.isEmpty {
            statusCallback?("Verifying \(cards.count) cards against \(filename)...")
            result.narrativeCards = await verifyCards(
                cards,
                documentId: documentId,
                filename: filename,
                source: source,
                modelId: modelId,
                voiceAnchor: voiceAnchor
            )
        }

        // Pass 4: enrichment after verification — each enrichment request sees
        // the same cached document plus the verified card it is enriching.
        if passes.enrichment, let cards = result.narrativeCards, !cards.isEmpty {
            statusCallback?("Enriching \(cards.count) cards from \(filename)...")
            await enrichCards(cards, source: source, voiceAnchor: voiceAnchor)
        }

        return result
    }

    private func generateSummary(
        filename: String,
        source: DocumentAnalysisSource,
        modelId: String
    ) async throws -> DocumentSummary {
        try await llmFacade.executeStructuredWithAnthropicBlocks(
            systemContent: DocumentAnalysisPrompts.systemBlocks,
            userBlocks: DocumentAnalysisPrompts.userBlocks(
                source: source,
                instructions: DocumentExtractionPrompts.summaryInstructions(filename: filename)
            ),
            modelId: modelId,
            responseType: DocumentSummary.self,
            schema: DocumentExtractionPrompts.summaryJsonSchema,
            maxTokens: 8192
        )
    }

    private func extractSkills(
        documentId: String,
        filename: String,
        source: DocumentAnalysisSource
    ) async -> Result<[Skill], Error> {
        do {
            return .success(try await skillBankService.extractSkills(
                documentId: documentId,
                filename: filename,
                source: source
            ))
        } catch {
            Logger.warning("🔧 Skill pass failed for \(filename): \(error.localizedDescription)", category: .ai)
            return .failure(error)
        }
    }

    private func extractCards(
        documentId: String,
        filename: String,
        source: DocumentAnalysisSource,
        voiceAnchor: String?
    ) async -> Result<[KnowledgeCard], Error> {
        do {
            return .success(try await kcExtractionService.extractCards(
                documentId: documentId,
                filename: filename,
                source: source,
                voiceAnchor: voiceAnchor
            ))
        } catch {
            Logger.warning("📖 Narrative-card pass failed for \(filename): \(error.localizedDescription)", category: .ai)
            return .failure(error)
        }
    }

    // MARK: - Verification Pass

    /// Run one batched adversarial verification call for the chunk's cards and
    /// apply the verdicts: drop fabricated cards, swap in revised narratives,
    /// repair broken anchors, and downgrade evidence quality when anchors are
    /// broken and unrepairable. On any call failure the cards pass through
    /// unchanged (logged) — verification degrades gracefully.
    private func verifyCards(
        _ cards: [KnowledgeCard],
        documentId: String,
        filename: String,
        source: DocumentAnalysisSource,
        modelId: String,
        voiceAnchor: String?
    ) async -> [KnowledgeCard] {
        let response: CardVerificationResponse
        do {
            response = try await llmFacade.executeStructuredWithAnthropicBlocks(
                systemContent: DocumentAnalysisPrompts.systemBlocks,
                userBlocks: DocumentAnalysisPrompts.userBlocks(
                    source: source,
                    voiceAnchor: voiceAnchor,
                    instructions: CardVerificationPrompts.verificationPrompt(
                        documentId: documentId,
                        filename: filename,
                        cards: cards,
                        isPagedSource: source.isPaged
                    )
                ),
                modelId: modelId,
                responseType: CardVerificationResponse.self,
                schema: CardVerificationPrompts.jsonSchema,
                maxTokens: 32768
            )
        } catch {
            Logger.warning(
                "🛡️ Verification pass failed for \(filename) — keeping all \(cards.count) cards unverified: \(error.localizedDescription)",
                category: .ai
            )
            return cards
        }

        var kept = 0
        var revised = 0
        var dropped = 0
        var surviving: [KnowledgeCard] = []

        for (index, card) in cards.enumerated() {
            guard let verdict = verdictFor(card: card, index: index, in: response.verdicts) else {
                // No verdict returned for this card — keep it untouched.
                kept += 1
                surviving.append(card)
                continue
            }

            if verdict.verdict == .drop {
                dropped += 1
                Logger.info(
                    "🛡️ Dropped card \"\(card.title)\" — unsupported: \(verdict.unsupportedClaims.joined(separator: " | "))",
                    category: .ai
                )
                continue
            }

            let revisedNarrative = verdict.verdict == .revise
                ? verdict.revisedNarrative?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            // Contract (CardVerificationPrompts): when anchorsValid is false,
            // repairedAnchors is the card's COMPLETE replacement anchor set —
            // still-valid anchors echoed unchanged, broken ones corrected,
            // unrepairable ones omitted — so wholesale replacement below is
            // lossless. Empty/missing means no anchor material survived: keep
            // the originals and downgrade evidence quality instead.
            let repairedAnchors = verdict.anchorsValid ? nil : verdict.repairedAnchors
            let downgradeEvidence = !verdict.anchorsValid && (repairedAnchors?.isEmpty ?? true)

            await MainActor.run {
                if let revisedNarrative, !revisedNarrative.isEmpty {
                    card.narrative = revisedNarrative
                }
                if let repairedAnchors, !repairedAnchors.isEmpty {
                    // The document identity is known a priori — never trust the
                    // model-echoed documentId (a hallucinated id would corrupt
                    // the anchor's linkage to its source artifact).
                    card.evidenceAnchors = repairedAnchors.map {
                        EvidenceAnchor(
                            documentId: documentId,
                            location: $0.location,
                            verbatimExcerpt: $0.verbatimExcerpt
                        )
                    }
                }
                if downgradeEvidence {
                    card.evidenceQuality = "weak"
                }
            }

            if let revisedNarrative, !revisedNarrative.isEmpty {
                revised += 1
                Logger.info(
                    "🛡️ Revised card \"\(card.title)\" — stripped: \(verdict.unsupportedClaims.joined(separator: " | "))",
                    category: .ai
                )
            } else {
                kept += 1
            }
            surviving.append(card)
        }

        Logger.info(
            "🛡️ Verification for \(filename): \(cards.count) cards in → \(kept) kept, \(revised) revised, \(dropped) dropped",
            category: .ai
        )
        return surviving
    }

    /// Match a verdict to a card by id (preferred) or batch index (fallback).
    private func verdictFor(
        card: KnowledgeCard,
        index: Int,
        in verdicts: [CardVerificationVerdict]
    ) -> CardVerificationVerdict? {
        let cardId = card.id.uuidString.lowercased()
        if let byId = verdicts.first(where: { $0.cardId.lowercased() == cardId }) {
            return byId
        }
        return verdicts.first(where: { $0.cardIndex == index })
    }

    /// Enrich verified cards in small concurrent batches.
    private func enrichCards(_ cards: [KnowledgeCard], source: DocumentAnalysisSource, voiceAnchor: String?) async {
        let batchSize = 4
        var enriched = 0

        for batchStart in stride(from: 0, to: cards.count, by: batchSize) {
            let batch = Array(cards[batchStart..<min(batchStart + batchSize, cards.count)])
            let service = enrichmentService

            enriched += await withTaskGroup(of: Bool.self) { group in
                for card in batch where !card.narrative.isEmpty {
                    group.addTask {
                        do {
                            try await service.enrichCard(card, source: source, voiceAnchor: voiceAnchor)
                            return true
                        } catch {
                            Logger.warning("✨ Enrichment failed for \(card.title): \(error.localizedDescription)", category: .ai)
                            return false
                        }
                    }
                }
                var count = 0
                for await success in group where success { count += 1 }
                return count
            }
        }

        Logger.info("✨ Enriched \(enriched)/\(cards.count) cards during document analysis", category: .ai)
    }

    // MARK: - Helpers

    private func chunkFilename(_ filename: String, chunk: PDFChunk, totalChunks: Int) -> String {
        guard totalChunks > 1 else { return filename }
        let base = (filename as NSString).deletingPathExtension
        return "\(base)-p\(chunk.pageRange.lowerBound)-\(chunk.pageRange.upperBound).pdf"
    }

    private func deleteFileBestEffort(_ fileId: String) {
        // Unstructured Task: cleanup must not inherit the caller's cancellation —
        // cancelling an ingestion mid-run would otherwise abort the delete and
        // leak the uploaded chunk in the Anthropic Files workspace.
        let facade = llmFacade
        Task {
            do {
                _ = try await facade.anthropicDeleteFile(id: fileId)
                Logger.debug("🗑️ Deleted Anthropic file \(fileId)", category: .ai)
            } catch {
                Logger.warning("⚠️ Failed to delete Anthropic file \(fileId): \(error.localizedDescription)", category: .ai)
            }
        }
    }

    /// Merge per-chunk summaries. Single-chunk documents pass through unchanged;
    /// multi-chunk summaries are joined with "Part N (pages X–Y):" labels.
    private func mergeSummaries(
        _ parts: [(pageRange: ClosedRange<Int>, summary: DocumentSummary)],
        totalChunks: Int
    ) -> DocumentSummary? {
        guard !parts.isEmpty else { return nil }
        if parts.count == 1 && totalChunks == 1 {
            return parts[0].summary
        }

        let joinedSummary = parts.enumerated().map { index, part in
            "Part \(index + 1) (pages \(part.pageRange.lowerBound)–\(part.pageRange.upperBound)): \(part.summary.summary)"
        }.joined(separator: "\n\n")

        let first = parts[0].summary
        return DocumentSummary(
            documentType: first.documentType,
            briefDescription: first.briefDescription,
            summary: joinedSummary,
            timePeriod: parts.compactMap { $0.summary.timePeriod }.first,
            companies: uniqued(parts.flatMap { $0.summary.companies }),
            roles: uniqued(parts.flatMap { $0.summary.roles }),
            skills: uniqued(parts.flatMap { $0.summary.skills }),
            achievements: uniqued(parts.flatMap { $0.summary.achievements }),
            relevanceHints: uniqued(parts.map { $0.summary.relevanceHints }).joined(separator: " ")
        )
    }

    private func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
