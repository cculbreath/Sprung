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
    /// Used ONLY by the one-time transcription pass — downstream extraction
    /// reads the transcription via `.transcript`, never the PDF again.
    case pdfFile(id: String)
    /// Plain text (txt/docx/rtf/html native extraction, or stored artifact text).
    case text(String)
    /// Pre-rendered intermediate representation (PDF transcription or git
    /// digest) consumed by extraction passes. Carries its own paged-ness: a PDF
    /// transcription preserves page anchors, a git digest uses path/line/commit.
    case transcript(text: String, isPaged: Bool)

    /// True when locations in the source are page-addressable (evidence anchors
    /// must then be page-anchored, e.g. "p. 14" or "p. 3, Fig. 2").
    var isPaged: Bool {
        switch self {
        case .pdfFile: return true
        case .text: return false
        case .transcript(_, let isPaged): return isPaged
        }
    }

    /// The source block, placed FIRST in every pass's user content.
    ///
    /// Caching is per-case, by reuse profile:
    /// - `.transcript` / `.text` are read by EVERY extraction pass (summary, skills,
    ///   cards, verification, enrichment), so they carry a cache breakpoint — the
    ///   first pass writes the prefix (1.25x) and the rest read it (0.1x). This is
    ///   the warm-then-fan-out win.
    /// - `.pdfFile` is the SINGLE-SHOT transcription input: each chunk is uploaded,
    ///   transcribed once, then deleted and never re-read (downstream extraction
    ///   uses `.transcript`). Caching it would pay the 1.25x write premium on the
    ///   document's largest token component with zero subsequent reads to amortize
    ///   it, so it is sent as a standard (uncached) block at the 1.0x input rate.
    var sourceContentBlock: AnthropicContentBlock {
        switch self {
        case .pdfFile(let id):
            return .document(AnthropicDocumentBlock(source: .file(id: id)))
        case .text(let text):
            return .text(AnthropicTextBlock(text: text, cacheControl: .ephemeral))
        case .transcript(let text, _):
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
        var blocks: [AnthropicContentBlock] = [source.sourceContentBlock]
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
        /// The high-fidelity intermediate representation the extraction passes ran
        /// against, when one was produced (PDF transcription). Persisted on the
        /// artifact so extraction can be re-run later without re-reading the source.
        /// Nil for plain-text sources (they are already text — no transcription).
        var intermediateRepresentation: IntermediateRepresentation?
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

    /// Checkpoints each transcribed chunk by its absolute page range so a
    /// later-chunk failure does not discard the chunks already done. Nil disables
    /// checkpointing (the transcription still works, it just cannot resume).
    private let checkpointStore: TranscriptionCheckpointStore?

    init(
        llmFacade: LLMFacade,
        skillBankService: SkillBankService,
        kcExtractionService: KnowledgeCardExtractionService,
        voiceAnchorProvider: (@Sendable () async -> String?)? = nil,
        checkpointStore: TranscriptionCheckpointStore? = nil
    ) {
        self.llmFacade = llmFacade
        self.preflightService = PDFPreflightService(llmFacade: llmFacade)
        self.skillBankService = skillBankService
        self.kcExtractionService = kcExtractionService
        self.enrichmentService = CardEnrichmentService(llmFacade: llmFacade)
        self.voiceAnchorProvider = voiceAnchorProvider
        self.checkpointStore = checkpointStore
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
        try ModelConfigResolver.resolve(key: modelSettingKey, operation: operationName)
    }

    // MARK: - Public API

    /// Analyze a PDF. The PDF is read EXACTLY ONCE — transcribed into a
    /// high-fidelity `DocumentTranscription` (handles its own chunking / Files-API
    /// upload) — and then every extraction pass runs against that transcription via
    /// a single cached `.transcript` source block. The PDF is never re-uploaded for
    /// extraction; the returned `AnalysisResult` carries the IR for persistence so
    /// extraction can be re-run later for $0.
    /// - Parameter resumeFrom: a prior transcription of the SAME content (matched
    ///   by the caller via sha256). Its `.completed` chunks are reused so only the
    ///   still-missing pages are transcribed — even across sessions.
    func analyzePDF(
        documentId: String,
        filename: String,
        pdfData: Data,
        resumeFrom: DocumentTranscription? = nil,
        passes: PassSelection = .all,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> AnalysisResult {
        let modelId = try Self.configuredModelId()

        // Tag every LLM pass in this document's pipeline (transcription + the
        // summary/skills/cards/verify/enrich passes) for token-usage attribution.
        // `runPasses` overrides the tag for the summary and enrichment sub-passes.
        return try await OnboardingUsageReporting.$source.withValue(.documentExtraction) {
            // Stage 1: transcribe the actual PDF, reusing any prior completed chunks.
            let transcription = try await transcribePDF(
                documentId: documentId,
                filename: filename,
                pdfData: pdfData,
                resumeFrom: resumeFrom,
                statusCallback: statusCallback
            )
            let ir = IntermediateRepresentation.pdf(transcription)

            // An incomplete transcription is PERSISTED (carrying its log + the
            // chunks that did succeed) so a later run resumes only the gaps — but
            // extraction is skipped: running it on a partial document would mint
            // cards/skills from a document missing pages. Surface it as a
            // resumable failure, never a silent partial.
            guard transcription.isComplete else {
                var result = AnalysisResult()
                result.intermediateRepresentation = ir
                let missing = transcription.missingPagesDescription
                Logger.warning(
                    "⚠️ Transcription incomplete for \(filename) — missing pages \(missing). Persisting partial IR for resume; skipping extraction.",
                    category: .ai
                )
                result.passFailures.append(
                    "document analysis — \(filename): transcription incomplete (missing pages \(missing)); re-run to resume the missing chunks"
                )
                return result
            }

            // Stage 2: run the extraction pass set ONCE over the rendered transcription.
            // Page anchors survive (isPaged: true) so evidence still resolves to pages.
            var result = await runPasses(
                documentId: documentId,
                filename: filename,
                source: .transcript(text: ir.renderedForExtraction(), isPaged: true),
                passes: passes,
                modelId: modelId,
                sourceKind: ir.sourceKind,
                statusCallback: statusCallback
            )
            result.intermediateRepresentation = ir
            return result
        }
    }

    /// Analyze a text-based source (txt/docx/rtf/html native extraction, or stored
    /// artifact text). Same pass structure as PDFs, with a cached text block.
    func analyzeText(
        documentId: String,
        filename: String,
        text: String,
        passes: PassSelection = .all,
        sourceKind: ExtractionSourceKind = .document,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> AnalysisResult {
        let modelId = try Self.configuredModelId()
        let source = DocumentAnalysisSource.text(Self.sourceTextBlock(filename: filename, text: text))
        return await OnboardingUsageReporting.$source.withValue(.documentExtraction) {
            await runPasses(
                documentId: documentId,
                filename: filename,
                source: source,
                passes: passes,
                modelId: modelId,
                sourceKind: sourceKind,
                statusCallback: statusCallback
            )
        }
    }

    /// Re-run the extraction pass set against a STORED intermediate representation
    /// (PDF transcription or git digest) — no source re-read, no Files-API upload,
    /// no live git agent. The IR's own paged-ness is preserved so evidence anchors
    /// resolve the same way they did at ingestion. This is the cheap-iteration entry
    /// point: tweak an extraction prompt and re-run for $0 in source parsing.
    func analyzeIntermediateRepresentation(
        documentId: String,
        filename: String,
        ir: IntermediateRepresentation,
        passes: PassSelection = .all,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> AnalysisResult {
        let modelId = try Self.configuredModelId()
        var result = await OnboardingUsageReporting.$source.withValue(.documentExtraction) {
            await runPasses(
                documentId: documentId,
                filename: filename,
                source: .transcript(text: ir.renderedForExtraction(), isPaged: ir.isPaged),
                passes: passes,
                modelId: modelId,
                sourceKind: ir.sourceKind,
                statusCallback: statusCallback
            )
        }
        result.intermediateRepresentation = ir
        return result
    }

    /// Transcribe a PDF ONCE into a high-fidelity `DocumentTranscription` (the
    /// PDF intermediate representation). Each chunk is uploaded via the Files API,
    /// transcribed in a single multimodal pass against the ACTUAL PDF, then deleted
    /// best-effort. Per-chunk payloads are merged into one transcription with
    /// ABSOLUTE page numbers preserved.
    ///
    /// This is the ONLY pass that re-reads the PDF; downstream extraction reads the
    /// returned transcription (via `.transcript`) instead of re-uploading the file.
    func transcribePDF(
        documentId: String,
        filename: String,
        pdfData: Data,
        resumeFrom: DocumentTranscription? = nil,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> DocumentTranscription {
        let modelId = try Self.configuredModelId(operationName: "PDF Transcription")

        statusCallback?("Preparing \(filename) for transcription...")
        let chunks = try await preflightService.makeChunks(pdfData: pdfData, filename: filename, modelId: modelId)

        // The document's true total page count: each chunk's page range is
        // absolute, so the last chunk's upper bound is the total. Used in the
        // per-chunk instructions and as the merged transcription's page count.
        let totalPages = chunks.map { $0.pageRange.upperBound }.max() ?? 0
        let maxTokens = 32_768

        // Seed already-transcribed chunks so resume re-does ONLY what's missing.
        // Two sources, keyed by absolute page range:
        //   • a prior IR for the SAME content (cross-session reuse) — its log's
        //     `.completed` chunks carry their payloads;
        //   • this run's checkpoint store (within-attempt crash recovery).
        // Checkpoint wins on overlap (same content, freshest).
        var completedByRange: [ClosedRange<Int>: TranscriptionPayload] = [:]
        for chunk in resumeFrom?.transcriptionLog ?? [] where chunk.status == .completed {
            if let payload = chunk.payload { completedByRange[chunk.pageRange] = payload }
        }
        if let checkpointStore {
            for saved in await checkpointStore.savedChunks(documentId: documentId) {
                completedByRange[saved.pageRange] = saved.payload
            }
        }

        for chunk in chunks where completedByRange[chunk.pageRange] != nil {
            statusCallback?(
                "Reusing \(filename) pages \(chunk.pageRange.lowerBound)–\(chunk.pageRange.upperBound)..."
            )
            Logger.info(
                "⏭️ Reusing transcribed \(chunkLabel(filename: filename, chunk: chunk, totalChunks: chunks.count)) — skipping re-transcription",
                category: .ai
            )
        }
        let pending = chunks.filter { completedByRange[$0.pageRange] == nil }

        // Fan out the missing chunks, capped so a large document (or several in
        // flight) doesn't storm the rate limiter. A per-chunk content/transient
        // failure is RECORDED (the chunk stays `.failed` for a later resume)
        // rather than aborting the whole document; a `ModelConfigurationError` is
        // fatal and propagates so the UI surfaces the model picker. Each task
        // checkpoints its own success for within-attempt recovery.
        let limit = max(1, maxConcurrentChunkTranscriptions)
        let totalChunks = chunks.count
        var failureReasons: [ClosedRange<Int>: String] = [:]
        try await withThrowingTaskGroup(
            of: (pageRange: ClosedRange<Int>, payload: TranscriptionPayload?, failureReason: String?).self
        ) { group in
            var remaining = pending.makeIterator()
            func schedule(_ chunk: PDFChunk) {
                group.addTask {
                    do {
                        let transcribed = try await self.transcribeChunk(
                            chunk, documentId: documentId, filename: filename,
                            totalChunks: totalChunks, totalPages: totalPages,
                            modelId: modelId, maxTokens: maxTokens, statusCallback: statusCallback
                        )
                        return (chunk.pageRange, transcribed.payload, nil)
                    } catch let error as ModelConfigurationError {
                        throw error
                    } catch {
                        Logger.warning(
                            "⚠️ Transcription failed for \(self.chunkLabel(filename: filename, chunk: chunk, totalChunks: totalChunks)): \(error.localizedDescription) — marking chunk for resume",
                            category: .ai
                        )
                        return (chunk.pageRange, nil, error.localizedDescription)
                    }
                }
            }
            var scheduled = 0
            while scheduled < limit, let chunk = remaining.next() { schedule(chunk); scheduled += 1 }
            while let outcome = try await group.next() {
                if let payload = outcome.payload {
                    completedByRange[outcome.pageRange] = payload
                } else {
                    failureReasons[outcome.pageRange] = outcome.failureReason
                }
                if let chunk = remaining.next() { schedule(chunk) }
            }
        }

        // Authoritative per-chunk log over the full plan, in absolute page order.
        let log: [TranscribedChunk] = chunks.map { chunk in
            if let payload = completedByRange[chunk.pageRange] {
                return TranscribedChunk(pageRange: chunk.pageRange, status: .completed, payload: payload)
            }
            return TranscribedChunk(
                pageRange: chunk.pageRange, status: .failed,
                payload: nil, failureReason: failureReasons[chunk.pageRange]
            )
        }

        let provenance = IRProvenance(
            sourceArtifactId: documentId,
            sha256: nil,
            modelId: modelId,
            promptVersion: DocumentTranscriptionPrompts.promptVersion,
            createdAt: Date()
        )

        // Merge only completed chunks (page-ordered) into the extraction view; the
        // log records every chunk's status (incl. the failed ones excluded here).
        let completedParts = chunks.compactMap { chunk -> (pageRange: ClosedRange<Int>, payload: TranscriptionPayload)? in
            completedByRange[chunk.pageRange].map { (chunk.pageRange, $0) }
        }
        var merged = mergeTranscriptions(completedParts, totalPages: totalPages, provenance: provenance)
        merged.transcriptionLog = log

        // The IR now carries every completed payload, so the within-attempt
        // scratchpad is only useful while chunks are still missing. Clear it once
        // the document is whole.
        if log.allSatisfy({ $0.status == .completed }) {
            await checkpointStore?.clear(documentId: documentId)
        }

        return merged
    }

    /// Max chunks of a single document transcribed concurrently. Fan-out replaces one
    /// slow, truncation-prone transcription call with many small parallel ones; this
    /// caps peak request concurrency (multiplied by the document-level extraction cap)
    /// so large uploads don't storm the rate limiter — 429s back off and retry anyway.
    /// Override via the `onboardingMaxConcurrentChunkTranscriptions` default; else 4.
    private var maxConcurrentChunkTranscriptions: Int {
        let configured = UserDefaults.standard.integer(forKey: "onboardingMaxConcurrentChunkTranscriptions")
        return configured > 0 ? configured : 4
    }

    /// Human-readable label for a chunk: the bare filename for single-chunk documents,
    /// filename + absolute page range otherwise. `nonisolated` (pure formatting, no
    /// actor state) so the concurrent transcription tasks can label without hopping.
    private nonisolated func chunkLabel(filename: String, chunk: PDFChunk, totalChunks: Int) -> String {
        totalChunks > 1
            ? "\(filename) (pages \(chunk.pageRange.lowerBound)–\(chunk.pageRange.upperBound))"
            : filename
    }

    /// Transcribe a single PDF chunk: upload it, run the multimodal transcription pass,
    /// delete the uploaded file, checkpoint the result, and return it. Safe to run
    /// concurrently — it touches no shared `transcribePDF` state, and the checkpoint
    /// store serializes its own writes on the main actor.
    private func transcribeChunk(
        _ chunk: PDFChunk,
        documentId: String,
        filename: String,
        totalChunks: Int,
        totalPages: Int,
        modelId: String,
        maxTokens: Int,
        statusCallback: (@Sendable (String) -> Void)?
    ) async throws -> (pageRange: ClosedRange<Int>, payload: TranscriptionPayload) {
        let label = chunkLabel(filename: filename, chunk: chunk, totalChunks: totalChunks)

        statusCallback?("Uploading \(label) for transcription...")
        let file = try await llmFacade.anthropicUploadFile(
            data: chunk.data,
            filename: chunkFilename(filename, chunk: chunk, totalChunks: totalChunks),
            mimeType: "application/pdf"
        )
        Logger.info("📄 Uploaded \(label) to Anthropic Files API for transcription: \(file.id)", category: .ai)

        statusCallback?("Transcribing \(label)...")
        let payload: TranscriptionPayload
        do {
            payload = try await llmFacade.executeStructuredWithAnthropicBlocks(
                systemContent: DocumentAnalysisPrompts.systemBlocks,
                userBlocks: DocumentAnalysisPrompts.userBlocks(
                    source: .pdfFile(id: file.id),
                    instructions: DocumentTranscriptionPrompts.transcriptionInstructions(
                        filename: filename,
                        pageRange: chunk.pageRange,
                        totalPages: totalPages
                    )
                ),
                modelId: modelId,
                responseType: TranscriptionPayload.self,
                schema: DocumentTranscriptionPrompts.transcriptionJsonSchema,
                maxTokens: maxTokens
            )
        } catch {
            deleteFileBestEffort(file.id)
            throw error
        }

        deleteFileBestEffort(file.id)

        // No silent caps: a transcription crowding the output ceiling was likely cut
        // mid-document. Warn rather than pretend it is complete.
        warnIfTruncated(payload: payload, chunkLabel: label, maxTokens: maxTokens)

        Logger.info(
            "📝 Transcribed \(label): \(payload.fullText.count) chars, \(payload.visualElements.count) visuals, \(payload.tables.count) tables",
            category: .ai
        )

        // Checkpoint immediately so a sibling chunk's failure keeps this one.
        await checkpointStore?.saveChunk(documentId: documentId, pageRange: chunk.pageRange, payload: payload)
        return (chunk.pageRange, payload)
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
        sourceKind: ExtractionSourceKind,
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
                result.summary = try await OnboardingUsageReporting.$source.withValue(.documentSummarization) {
                    try await generateSummary(filename: filename, source: source, modelId: modelId)
                }
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
                skillsOutcome = await extractSkills(documentId: documentId, filename: filename, source: source, sourceKind: sourceKind)
                cardsOutcome = await extractCards(
                    documentId: documentId, filename: filename, source: source, voiceAnchor: voiceAnchor, sourceKind: sourceKind
                )
            } else {
                async let skillsTask: Result<[Skill], Error>? = passes.skills
                    ? extractSkills(documentId: documentId, filename: filename, source: source, sourceKind: sourceKind)
                    : nil
                async let cardsTask: Result<[KnowledgeCard], Error>? = passes.narrativeCards
                    ? extractCards(documentId: documentId, filename: filename, source: source, voiceAnchor: voiceAnchor, sourceKind: sourceKind)
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
            await OnboardingUsageReporting.$source.withValue(.cardGeneration) {
                await enrichCards(cards, source: source, voiceAnchor: voiceAnchor)
            }
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
        source: DocumentAnalysisSource,
        sourceKind: ExtractionSourceKind
    ) async -> Result<[Skill], Error> {
        do {
            return .success(try await skillBankService.extractSkills(
                documentId: documentId,
                filename: filename,
                source: source,
                sourceKind: sourceKind
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
        voiceAnchor: String?,
        sourceKind: ExtractionSourceKind
    ) async -> Result<[KnowledgeCard], Error> {
        do {
            return .success(try await kcExtractionService.extractCards(
                documentId: documentId,
                filename: filename,
                source: source,
                voiceAnchor: voiceAnchor,
                sourceKind: sourceKind
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

    // MARK: - Transcription Merge

    /// Merge per-chunk transcription payloads into one `DocumentTranscription`,
    /// PRESERVING ABSOLUTE PAGE NUMBERS. `fullText` is concatenated in chunk order
    /// with an explicit page-break marker between chunks (only when multi-chunk);
    /// `visualElements` and `tables` are concatenated in chunk order (their `.page`
    /// is already absolute via the prompt). `productionQuality`, `structure`,
    /// `docMeta.language`, and `docMeta.docClassGuess` take the first chunk's
    /// values; `docMeta.pageCount` is the document's true total page count. A
    /// single-chunk document passes through unchanged (no marker, first == only).
    private func mergeTranscriptions(
        _ unsortedParts: [(pageRange: ClosedRange<Int>, payload: TranscriptionPayload)],
        totalPages: Int,
        provenance: IRProvenance
    ) -> DocumentTranscription {
        // Defensive sort: callers seed checkpoints + freshly-transcribed chunks
        // that can interleave, and the merge concatenates `fullText` in chunk
        // order with absolute page-break markers — order must be ascending.
        let parts = unsortedParts.sorted { $0.pageRange.lowerBound < $1.pageRange.lowerBound }

        // makeChunks always yields ≥ 1 chunk; fall back to an empty transcription
        // rather than crash if that invariant ever changes.
        guard let first = parts.first else {
            return DocumentTranscription(
                fullText: "",
                productionQuality: TranscriptionProductionQuality(typesettingSystemGuess: ""),
                docMeta: DocMeta(pageCount: totalPages),
                provenance: provenance
            )
        }

        let multiChunk = parts.count > 1

        var fullTextParts: [String] = []
        var visualElements: [VisualElement] = []
        var tables: [TranscribedTable] = []

        for part in parts {
            if multiChunk {
                fullTextParts.append(
                    "\n\n---\n\n## Pages \(part.pageRange.lowerBound)–\(part.pageRange.upperBound)\n\n"
                    + part.payload.fullText
                )
            } else {
                fullTextParts.append(part.payload.fullText)
            }
            visualElements.append(contentsOf: part.payload.visualElements)
            tables.append(contentsOf: part.payload.tables)
        }

        let firstMeta = first.payload.docMeta
        let docMeta = DocMeta(
            pageCount: totalPages,
            language: firstMeta.language,
            docClassGuess: firstMeta.docClassGuess
        )

        return DocumentTranscription(
            fullText: fullTextParts.joined(),
            visualElements: visualElements,
            tables: tables,
            productionQuality: first.payload.productionQuality,
            structure: first.payload.structure,
            docMeta: docMeta,
            provenance: provenance
        )
    }

    /// Heuristic "no silent caps" guard. The structured call returns only the
    /// decoded payload (no token usage), so we approximate the output token count
    /// from the serialized payload size (~4 chars/token) and warn when it crowds
    /// the `maxTokens` ceiling — a strong sign the transcription was cut
    /// mid-document and is incomplete.
    private func warnIfTruncated(payload: TranscriptionPayload, chunkLabel: String, maxTokens: Int) {
        let approxChars = payload.fullText.count
            + payload.visualElements.reduce(0) { $0 + $1.faithfulDescription.count }
            + payload.tables.reduce(0) { $0 + $1.markdown.count }
        let approxTokens = approxChars / 4
        // 95% of the ceiling: close enough that a longer document would not have fit.
        if approxTokens >= maxTokens * 95 / 100 {
            Logger.warning(
                "✂️ Transcription of \(chunkLabel) is near the \(maxTokens)-token output cap (~\(approxTokens) tokens) — it may be truncated; the transcription could be incomplete.",
                category: .ai
            )
        }
    }
}
