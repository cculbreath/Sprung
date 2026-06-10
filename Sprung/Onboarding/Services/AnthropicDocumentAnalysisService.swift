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
    /// enrichment). It must stay byte-identical across passes: prompt caching is
    /// a prefix match over system + messages, so a per-pass system prompt would
    /// invalidate the cached document prefix.
    static let sharedSystemPrompt = """
    You are a meticulous document-analysis assistant for a resume-building application. \
    Ground every claim in the source document provided at the start of the user message, \
    and respond with well-structured JSON that conforms exactly to the requested schema.
    """

    static var systemBlocks: [AnthropicSystemBlock] {
        [AnthropicSystemBlock(text: sharedSystemPrompt)]
    }

    /// Build the user content for one pass: the cached source block first,
    /// then the pass-specific instructions.
    static func userBlocks(source: DocumentAnalysisSource, instructions: String) -> [AnthropicContentBlock] {
        [
            source.cachedContentBlock,
            .text(AnthropicTextBlock(text: instructions))
        ]
    }
}

// MARK: - AnthropicDocumentAnalysisService

/// Runs the document-analysis pass set against a single source with a shared,
/// cached prompt prefix:
///
/// 1. Summary FIRST (awaited — warms the prompt cache for the document prefix)
/// 2. Skill bank + narrative-card extraction concurrently
/// 3. Enrichment after cards complete (sees the document + the extracted cards)
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
    }

    private let llmFacade: LLMFacade
    private let preflightService: PDFPreflightService
    private let skillBankService: SkillBankService
    private let kcExtractionService: KnowledgeCardExtractionService
    private let enrichmentService: CardEnrichmentService

    init(
        llmFacade: LLMFacade,
        skillBankService: SkillBankService,
        kcExtractionService: KnowledgeCardExtractionService
    ) {
        self.llmFacade = llmFacade
        self.preflightService = PDFPreflightService(llmFacade: llmFacade)
        self.skillBankService = skillBankService
        self.kcExtractionService = kcExtractionService
        self.enrichmentService = CardEnrichmentService(llmFacade: llmFacade)
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

        // Pass 1: summary FIRST — awaiting it warms the prompt cache for the
        // shared (system + source) prefix used by every subsequent pass.
        if passes.summary {
            statusCallback?("Summarizing \(filename)...")
            do {
                result.summary = try await generateSummary(filename: filename, source: source, modelId: modelId)
                Logger.info("✅ Summary generated for \(filename) (\(result.summary?.summary.count ?? 0) chars)", category: .ai)
            } catch {
                Logger.warning("⚠️ Summary pass failed for \(filename): \(error.localizedDescription)", category: .ai)
            }
        }

        // Pass 2: skill bank + narrative cards against the warmed prefix.
        // A cache entry only becomes readable once the first response begins
        // streaming, so if no earlier pass warmed the cache (e.g. knowledgeOnly
        // skips the summary) two concurrent passes would EACH pay full document
        // input cost — run sequentially in that case (warm-then-continue).
        if passes.skills || passes.narrativeCards {
            statusCallback?("Extracting skills and narrative cards from \(filename)...")

            if passes.skills && passes.narrativeCards && !passes.summary {
                result.skills = await extractSkills(documentId: documentId, filename: filename, source: source)
                result.narrativeCards = await extractCards(documentId: documentId, filename: filename, source: source)
            } else {
                async let skillsTask: [Skill]? = passes.skills
                    ? extractSkills(documentId: documentId, filename: filename, source: source)
                    : nil
                async let cardsTask: [KnowledgeCard]? = passes.narrativeCards
                    ? extractCards(documentId: documentId, filename: filename, source: source)
                    : nil

                (result.skills, result.narrativeCards) = await (skillsTask, cardsTask)
            }
        }

        // Pass 3: enrichment after cards complete — each enrichment request sees
        // the same cached document plus the extracted card it is enriching.
        if passes.enrichment, let cards = result.narrativeCards, !cards.isEmpty {
            statusCallback?("Enriching \(cards.count) cards from \(filename)...")
            await enrichCards(cards, source: source)
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
    ) async -> [Skill]? {
        do {
            return try await skillBankService.extractSkills(
                documentId: documentId,
                filename: filename,
                source: source
            )
        } catch {
            Logger.warning("🔧 Skill pass failed for \(filename): \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    private func extractCards(
        documentId: String,
        filename: String,
        source: DocumentAnalysisSource
    ) async -> [KnowledgeCard]? {
        do {
            return try await kcExtractionService.extractCards(
                documentId: documentId,
                filename: filename,
                source: source
            )
        } catch {
            Logger.warning("📖 Narrative-card pass failed for \(filename): \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Enrich freshly extracted cards in small concurrent batches.
    private func enrichCards(_ cards: [KnowledgeCard], source: DocumentAnalysisSource) async {
        let batchSize = 4
        var enriched = 0

        for batchStart in stride(from: 0, to: cards.count, by: batchSize) {
            let batch = Array(cards[batchStart..<min(batchStart + batchSize, cards.count)])
            let service = enrichmentService

            enriched += await withTaskGroup(of: Bool.self) { group in
                for card in batch where !card.narrative.isEmpty {
                    group.addTask {
                        do {
                            try await service.enrichCard(card, source: source)
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
