import Foundation
import PDFKit
import UniformTypeIdentifiers
import CryptoKit
import SwiftyJSON

/// Lightweight service that orchestrates vendor-agnostic document extraction.
/// It converts local PDF/DOCX files into enriched markdown using the configured
/// PDF extraction model (default: Gemini 2.0 Flash via OpenRouter).
actor DocumentExtractionService {
    var onInvalidModelId: ((String) -> Void)?

    struct ExtractionRequest {
        let fileURL: URL
        let purpose: String
        let returnTypes: [String]
        let autoPersist: Bool
        let timeout: TimeInterval?
        /// When true, extracts verbatim text without summarization (for writing samples)
        let verbatimTranscription: Bool

        init(
            fileURL: URL,
            purpose: String,
            returnTypes: [String] = [],
            autoPersist: Bool = false,
            timeout: TimeInterval? = nil,
            verbatimTranscription: Bool = false
        ) {
            self.fileURL = fileURL
            self.purpose = purpose
            self.returnTypes = returnTypes
            self.autoPersist = autoPersist
            self.timeout = timeout
            self.verbatimTranscription = verbatimTranscription
        }
    }

    struct ExtractedArtifact {
        let id: String
        let filename: String
        let title: String?
        let contentType: String
        let sizeInBytes: Int
        let sha256: String
        let extractedContent: String
        let metadata: [String: Any]
    }

    struct Quality {
        let confidence: Double
        let issues: [String]
    }

    struct ExtractionResult {
        enum Status: String {
            case ok
            case partial
            case failed
        }
        let status: Status
        let artifact: ExtractedArtifact?
        let quality: Quality
        let derivedApplicantProfile: JSON?
        let derivedSkeletonTimeline: JSON?
        let persisted: Bool
    }

    enum ExtractionError: Error {
        case unsupportedType(String)
        case unreadableData
        case noTextExtracted
        case pdfTooLarge(pageCount: Int)
        case llmFailed(String)
        case llmNotConfigured

        var userFacingMessage: String {
            switch self {
            case .unsupportedType:
                return "Unsupported document format. Please upload a PDF, DOCX, or plain text file."
            case .unreadableData:
                return "The document could not be read. Please try another file."
            case .noTextExtracted:
                return "The document did not contain extractable text."
            case .pdfTooLarge(let pageCount):
                return "This PDF has \(pageCount) pages. Image-based extraction is limited to 10 pages or fewer. Please split the document or provide a text-based PDF."
            case .llmFailed(let description):
                return "Extraction failed: \(description)"
            case .llmNotConfigured:
                return "PDF extraction model is not configured. Add an OpenRouter API key in Settings."
            }
        }
    }

    /// Maximum pages for image-based PDF extraction
    private let maxPagesForImageExtraction = 10

    /// Threshold above which PDFs get LLM summarization instead of full text enrichment
    private let largePDFPageThreshold = 20

    // MARK: - Private Properties
    private var llmFacade: LLMFacade?
    private let maxCharactersForPrompt = 18_000
    private let defaultModelId = "google/gemini-2.0-flash-001"
    private var availableModelIds: [String] = []

    init(llmFacade: LLMFacade?) {
        self.llmFacade = llmFacade
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
    }

    func updateAvailableModels(_ ids: [String]) {
        availableModelIds = ids
    }

    func setInvalidModelHandler(_ handler: @escaping (String) -> Void) {
        onInvalidModelId = handler
    }

    // MARK: - Public API

    func extract(using request: ExtractionRequest, progress: ExtractionProgressHandler? = nil) async throws -> ExtractionResult {
        guard llmFacade != nil else {
            throw ExtractionError.llmNotConfigured
        }

        let fileURL = request.fileURL
        let filename = fileURL.lastPathComponent
        let sizeInBytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        let contentType = contentTypeForFile(at: fileURL) ?? "application/octet-stream"
        let extractionStart = Date()

        Logger.info(
            "📄 Extraction started",
            category: .diagnostics,
            metadata: [
                "filename": filename,
                "size_bytes": "\(sizeInBytes)",
                "purpose": request.purpose
            ]
        )

        func notifyProgress(_ stage: ExtractionProgressStage, _ state: ExtractionProgressStageState, detail: String? = nil) async {
            guard let progress else { return }
            await progress(ExtractionProgressUpdate(stage: stage, state: state, detail: detail))
        }

        let fileAnalysisDetail = filename.isEmpty ? "Analyzing document" : "Analyzing \(filename)"
        await notifyProgress(.fileAnalysis, .active, detail: fileAnalysisDetail)

        guard let fileData = try? Data(contentsOf: fileURL) else {
            await notifyProgress(.fileAnalysis, .failed, detail: "Unreadable file data")
            throw ExtractionError.unreadableData
        }

        let sha256 = sha256Hex(for: fileData)
        let (rawText, initialIssues, pdfPageCount) = extractPlainText(from: fileURL)

        // If text extraction failed and this is a PDF, try image-based extraction
        if (rawText == nil || rawText?.isEmpty == true) && fileURL.pathExtension.lowercased() == "pdf" {
            Logger.info("📄 Text extraction failed for PDF, attempting image-based extraction", category: .ai)
            await notifyProgress(.fileAnalysis, .active, detail: "No extractable text, processing pages as images...")
            return try await extractPDFViaImages(
                fileURL: fileURL,
                fileData: fileData,
                filename: filename,
                sizeInBytes: sizeInBytes,
                contentType: contentType,
                sha256: sha256,
                purpose: request.purpose,
                timeout: request.timeout,
                autoPersist: request.autoPersist,
                progress: progress
            )
        }

        guard let rawText, !rawText.isEmpty else {
            await notifyProgress(.fileAnalysis, .failed, detail: "No extractable text")
            throw ExtractionError.noTextExtracted
        }

        await notifyProgress(.fileAnalysis, .completed)

        // For verbatim transcription mode (writing samples), skip summarization
        // For large PDFs (> 20 pages), use LLM summarization unless verbatim mode
        let isLargePDF = (pdfPageCount ?? 0) > largePDFPageThreshold && !request.verbatimTranscription
        if isLargePDF {
            Logger.info("📄 Large PDF detected (\(pdfPageCount ?? 0) pages), using LLM summarization", category: .ai)
        }

        let llmStart = Date()
        let aiStageDetail: String
        if request.verbatimTranscription {
            aiStageDetail = "Transcribing document verbatim..."
        } else if isLargePDF {
            aiStageDetail = "Summarizing \(pdfPageCount ?? 0)-page document with AI..."
        } else if request.purpose == "resume_timeline" {
            aiStageDetail = "Extracting resume details with Gemini AI..."
        } else {
            aiStageDetail = "Processing document with Gemini AI..."
        }
        await notifyProgress(.aiExtraction, .active, detail: aiStageDetail)

        let enrichmentResult: EnrichmentResult
        if request.verbatimTranscription {
            // For writing samples: verbatim transcription with chunking for large documents
            let (markdown, markdownIssues) = try await transcribeVerbatim(
                rawText,
                pageCount: pdfPageCount,
                timeout: request.timeout,
                progress: progress
            )
            enrichmentResult = EnrichmentResult(title: nil, content: markdown, issues: markdownIssues)
        } else if isLargePDF {
            enrichmentResult = try await summarizeLargePDF(rawText, timeout: request.timeout)
        } else {
            enrichmentResult = try await enrichText(rawText, purpose: request.purpose, timeout: request.timeout)
        }

        let llmDurationMs = Int(Date().timeIntervalSince(llmStart) * 1000)
        Logger.info(
            "📄 Extraction LLM phase completed",
            category: .diagnostics,
            metadata: [
                "filename": filename,
                "duration_ms": "\(llmDurationMs)"
            ]
        )

        let enrichedContent = enrichmentResult.content ?? rawText
        let extractedTitle = enrichmentResult.title
        let aiDetail: String? = {
            if let failure = enrichmentResult.issues.first(where: { $0.hasPrefix("llm_failure") }) {
                return failure.replacingOccurrences(of: "llm_failure_", with: "")
            }
            if enrichmentResult.content == nil {
                return "Using original text"
            }
            return nil
        }()

        let aiState: ExtractionProgressStageState = enrichmentResult.issues.contains(where: { $0.hasPrefix("llm_failure") }) ? .failed : .completed
        await notifyProgress(.aiExtraction, aiState, detail: aiDetail)

        var issues = initialIssues
        issues.append(contentsOf: enrichmentResult.issues)

        let confidence = estimateConfidence(for: enrichedContent, issues: issues)

        var metadata: [String: Any] = [
            "character_count": enrichedContent.count,
            "source_format": contentType,
            "purpose": request.purpose,
            "source_file_url": fileURL.absoluteString,
            "source_filename": filename
        ]
        if let pageCount = pdfPageCount {
            metadata["page_count"] = pageCount
        }
        if isLargePDF {
            metadata["extraction_method"] = "llm_summarization"
            metadata["summarized"] = true
        }
        if initialIssues.contains("truncated_input") {
            metadata["truncated_input"] = true
        }
        if let title = extractedTitle {
            metadata["title"] = title
        }

        let artifact = ExtractedArtifact(
            id: UUID().uuidString,
            filename: filename,
            title: extractedTitle,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            sha256: sha256,
            extractedContent: enrichedContent,
            metadata: metadata
        )

        let status: ExtractionResult.Status
        if issues.contains(where: { $0.hasPrefix("llm_failure") }) {
            status = .partial
        } else if issues.contains(where: { $0 == "text_extraction_warning" }) {
            status = .partial
        } else {
            status = .ok
        }

        if request.autoPersist {
            issues.append("auto_persist_not_supported")
        }

        let quality = Quality(confidence: confidence, issues: issues)

        let result = ExtractionResult(
            status: status,
            artifact: artifact,
            quality: quality,
            derivedApplicantProfile: nil,
            derivedSkeletonTimeline: nil,
            persisted: false
        )

        let totalMs = Int(Date().timeIntervalSince(extractionStart) * 1000)
        Logger.info(
            "📄 Extraction finished",
            category: .diagnostics,
            metadata: [
                "filename": filename,
                "duration_ms": "\(totalMs)",
                "issues": issues.isEmpty ? "none" : issues.joined(separator: ",")
            ]
        )

        return result
    }

    // MARK: - Helpers

    private func currentModelId() -> String {
        let stored = UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId") ?? defaultModelId
        let (sanitized, adjusted) = ModelPreferenceValidator.sanitize(
            requested: stored,
            available: availableModelIds,
            fallback: defaultModelId
        )
        if adjusted {
            UserDefaults.standard.set(sanitized, forKey: "onboardingPDFExtractionModelId")
        }
        return sanitized
    }

    private func contentTypeForFile(at url: URL) -> String? {
        if #available(macOS 12.0, *) {
            return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        } else {
            return nil
        }
    }

    /// Returns (text, issues, pageCount) - pageCount is nil for non-PDF documents
    private func extractPlainText(from url: URL) -> (String?, [String], Int?) {
        var issues: [String] = []
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else {
                return (nil, ["text_extraction_warning"], nil)
            }
            let pageCount = document.pageCount
            var text = ""
            for index in 0..<pageCount {
                guard let page = document.page(at: index) else { continue }
                if let pageText = page.string {
                    text.append(pageText)
                    text.append("\n\n")
                }
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (nil, ["text_extraction_warning"], pageCount)
            }
            return (text, issues, pageCount)
        }

        if ext == "docx" {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.officeOpenXML
            ]
            if let attributed = try? NSAttributedString(url: url, options: options, documentAttributes: nil) {
                let text = attributed.string
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (nil, ["text_extraction_warning"], nil)
                }
                return (text, issues, nil)
            } else {
                issues.append("text_extraction_warning")
                if let plain = try? String(contentsOf: url, encoding: .utf8) {
                    return (plain, issues, nil)
                }
                return (nil, issues, nil)
            }
        }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return (text, issues, nil)
        }

        return (nil, ["text_extraction_warning"], nil)
    }

    /// Result of text enrichment including optional title
    struct EnrichmentResult {
        let title: String?
        let content: String?
        let issues: [String]
    }

    private func enrichText(_ rawText: String, purpose: String, timeout: TimeInterval?) async throws -> EnrichmentResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return EnrichmentResult(title: nil, content: nil, issues: ["llm_failure_empty_input"])
        }

        guard let facade = llmFacade else {
            return EnrichmentResult(title: nil, content: nil, issues: ["llm_failure_not_configured"])
        }

        let modelId = currentModelId()
        var input = trimmed
        var issues: [String] = []

        if trimmed.count > maxCharactersForPrompt {
            input = String(trimmed.prefix(maxCharactersForPrompt))
            issues.append("truncated_input")
        }

        var prompt = """
You are a document extraction assistant. Convert the provided plain text into high-quality Markdown that preserves the document's logical structure.

Requirements:
- Reconstruct headings, bullet lists, numbered lists, and tables when possible.
- Process every page of the source document; include the full content in order with no omissions.
- Keep original ordering of sections.
- Summarize images/figures if referenced.
- Do not invent content; rewrite only what you can infer from the input.
- Use Markdown tables for tabular data.
- For contact details, list them as bullet points.
"""
        if purpose == "resume_timeline" {
            prompt += "- Highlight employment sections clearly. Use headings per job.\n"
        }
        prompt += """

Plain text input begins:
```
\(input)
```

Respond with a JSON object containing:
- "title": A concise, descriptive title for this document (e.g., "John Smith Resume", "Q3 2024 Project Report", "Senior Developer Cover Letter")
- "content": The formatted Markdown content

Example response format:
{"title": "Document Title Here", "content": "# Heading\\n\\nContent here..."}
"""

        do {
            let text = try await callFacadeText(facade: facade, prompt: prompt, modelId: modelId)
            if text.isEmpty {
                issues.append("llm_failure_empty_response")
                return EnrichmentResult(title: nil, content: nil, issues: issues)
            }
            let parsed = parseEnrichmentResponse(text)
            return EnrichmentResult(title: parsed.title, content: parsed.content, issues: issues)
        } catch let error as LLMError {
            if case .clientError(let message) = error, message.contains("not found") || message.contains("not valid") {
                onInvalidModelId?(modelId)
                throw ExtractionError.llmFailed("\(modelId) is not a valid model ID.")
            }
            issues.append("llm_failure_\(error.localizedDescription)")
            return EnrichmentResult(title: nil, content: nil, issues: issues)
        } catch {
            issues.append("llm_failure_\(error.localizedDescription)")
            return EnrichmentResult(title: nil, content: nil, issues: issues)
        }
    }

    /// Parse enrichment response - tries JSON first, falls back to plain text
    private func parseEnrichmentResponse(_ response: String) -> (title: String?, content: String) {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to parse as JSON
        if let data = trimmed.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let title = json["title"] as? String
                    let content = json["content"] as? String ?? trimmed
                    return (title, content)
                }
            } catch {
                // Not valid JSON, continue to fallback
            }
        }

        // Try to extract JSON from markdown code block
        if trimmed.contains("```json") || trimmed.contains("```") {
            let jsonPattern = #"```(?:json)?\s*(\{[\s\S]*?\})\s*```"#
            if let regex = try? NSRegularExpression(pattern: jsonPattern, options: []),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
               let jsonRange = Range(match.range(at: 1), in: trimmed) {
                let jsonString = String(trimmed[jsonRange])
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let title = json["title"] as? String
                    let content = json["content"] as? String ?? trimmed
                    return (title, content)
                }
            }
        }

        // Fallback: use full response as content, no title
        return (nil, trimmed)
    }

    /// Transcribe document verbatim for writing samples
    /// For documents > 10 pages, chunks into 10-page segments and processes serially
    private func transcribeVerbatim(
        _ rawText: String,
        pageCount: Int?,
        timeout: TimeInterval?,
        progress: ExtractionProgressHandler?
    ) async throws -> (String?, [String]) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (nil, ["llm_failure_empty_input"])
        }

        guard let facade = llmFacade else {
            return (nil, ["llm_failure_not_configured"])
        }

        let modelId = currentModelId()
        var issues: [String] = []

        // Estimate characters per page (rough approximation)
        let estimatedCharsPerPage = 3000
        let effectivePageCount = pageCount ?? max(1, trimmed.count / estimatedCharsPerPage)

        // If document is 10 pages or less, process in one go
        if effectivePageCount <= maxPagesForImageExtraction {
            return try await transcribeChunk(trimmed, chunkNumber: nil, totalChunks: nil, facade: facade, modelId: modelId)
        }

        // For larger documents, chunk into ~10-page segments and process serially
        Logger.info("📄 Large document (\(effectivePageCount) pages), chunking for verbatim transcription", category: .ai)

        let chunkSize = maxPagesForImageExtraction * estimatedCharsPerPage
        var chunks: [String] = []
        var startIndex = trimmed.startIndex

        while startIndex < trimmed.endIndex {
            let endIndex = trimmed.index(startIndex, offsetBy: chunkSize, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            chunks.append(String(trimmed[startIndex..<endIndex]))
            startIndex = endIndex
        }

        var allTranscriptions: [String] = []
        let totalChunks = chunks.count

        for (index, chunk) in chunks.enumerated() {
            let chunkNumber = index + 1
            Logger.info("📄 Processing chunk \(chunkNumber)/\(totalChunks) for verbatim transcription", category: .ai)

            // Update progress if available
            if let progress {
                await progress(ExtractionProgressUpdate(
                    stage: .aiExtraction,
                    state: .active,
                    detail: "Transcribing section \(chunkNumber) of \(totalChunks)..."
                ))
            }

            let (transcription, chunkIssues) = try await transcribeChunk(
                chunk,
                chunkNumber: chunkNumber,
                totalChunks: totalChunks,
                facade: facade,
                modelId: modelId
            )

            issues.append(contentsOf: chunkIssues)

            if let transcription {
                allTranscriptions.append(transcription)
            }
        }

        if allTranscriptions.isEmpty {
            return (nil, issues)
        }

        // Combine all chunks with section markers
        let combined = allTranscriptions.joined(separator: "\n\n---\n\n")
        issues.append("verbatim_transcription")
        if totalChunks > 1 {
            issues.append("chunked_\(totalChunks)_sections")
        }

        return (combined, issues)
    }

    /// Transcribe a single chunk of text verbatim
    private func transcribeChunk(
        _ text: String,
        chunkNumber: Int?,
        totalChunks: Int?,
        facade: LLMFacade,
        modelId: String
    ) async throws -> (String?, [String]) {
        var issues: [String] = []

        let chunkContext: String
        if let num = chunkNumber, let total = totalChunks, total > 1 {
            chunkContext = " (Section \(num) of \(total))"
        } else {
            chunkContext = ""
        }

        let prompt = """
You are a document transcription assistant. Your task is to provide a VERBATIM transcription of the provided text\(chunkContext).

Requirements:
- Transcribe ALL text exactly as written - do not summarize, paraphrase, or condense
- Preserve the original formatting, structure, and paragraph breaks
- Maintain headings, bullet points, and lists as they appear
- Keep the original voice, tone, and word choices intact
- If there are any unclear or illegible portions, mark them with [unclear]
- Do not add commentary, analysis, or interpretation
- Do not omit any content

This is a writing sample that will be used to analyze the author's writing style, so accuracy and completeness are critical.

Text to transcribe:
```
\(text)
```

Return the complete verbatim transcription:
"""

        do {
            let transcription = try await callFacadeText(facade: facade, prompt: prompt, modelId: modelId)
            if transcription.isEmpty {
                issues.append("llm_failure_empty_response")
                return (nil, issues)
            }
            return (transcription, issues)
        } catch let error as LLMError {
            if case .clientError(let message) = error, message.contains("not found") || message.contains("not valid") {
                onInvalidModelId?(modelId)
                throw ExtractionError.llmFailed("\(modelId) is not a valid model ID.")
            }
            issues.append("llm_failure_\(error.localizedDescription)")
            return (nil, issues)
        } catch {
            issues.append("llm_failure_\(error.localizedDescription)")
            return (nil, issues)
        }
    }

    /// Summarize a large PDF (> 20 pages) using LLM for resume/cover letter preparation
    private func summarizeLargePDF(_ rawText: String, timeout: TimeInterval?) async throws -> EnrichmentResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return EnrichmentResult(title: nil, content: nil, issues: ["llm_failure_empty_input"])
        }

        guard let facade = llmFacade else {
            return EnrichmentResult(title: nil, content: nil, issues: ["llm_failure_not_configured"])
        }

        let modelId = currentModelId()
        var issues: [String] = []

        // For large documents, we send the full text without truncation
        // The LLM will summarize appropriately
        let prompt = """
Extract and summarize the content of this PDF to support resume and cover letter drafting for the applicant (me).

Content handling rules:
- Text passages: Transcribe verbatim when feasible. For lengthy sections, provide a comprehensive summary that preserves key details, achievements, and distinctive phrasing.
- Original writing by the applicant (essays, statements, project descriptions): Quote in full or summarize exhaustively—do not omit substantive content.
- Diagrams, figures, and visual content: Provide a brief description of key elements and their purpose/significance.

Framing: This document is being prepared as source material for my own application materials. Highlight strengths, accomplishments, and distinguishing qualifications. This is not intended as a neutral third-party assessment—advocate for the candidate where the evidence supports it.

When summarizing, include brief qualitative notes on what makes particular achievements or experiences notable (e.g., scope, difficulty, originality, impact).

Document text begins:
```
\(trimmed)
```

Respond with a JSON object containing:
- "title": A concise, descriptive title for this document (e.g., "John Smith Resume", "Q3 2024 Project Report", "PhD Thesis - Machine Learning")
- "content": The structured, page-by-page summary in markdown format

Example response format:
{"title": "Document Title Here", "content": "# Summary\\n\\nContent here..."}
"""

        do {
            let text = try await callFacadeText(facade: facade, prompt: prompt, modelId: modelId)
            if text.isEmpty {
                issues.append("llm_failure_empty_response")
                return EnrichmentResult(title: nil, content: nil, issues: issues)
            }
            issues.append("large_pdf_summarized")
            let parsed = parseEnrichmentResponse(text)
            return EnrichmentResult(title: parsed.title, content: parsed.content, issues: issues)
        } catch let error as LLMError {
            if case .clientError(let message) = error, message.contains("not found") || message.contains("not valid") {
                onInvalidModelId?(modelId)
                throw ExtractionError.llmFailed("\(modelId) is not a valid model ID.")
            }
            issues.append("llm_failure_\(error.localizedDescription)")
            return EnrichmentResult(title: nil, content: nil, issues: issues)
        } catch {
            issues.append("llm_failure_\(error.localizedDescription)")
            return EnrichmentResult(title: nil, content: nil, issues: issues)
        }
    }

    private func estimateConfidence(for text: String, issues: [String]) -> Double {
        var confidence = min(0.95, Double(text.count) / 10_000.0 + 0.4)
        if issues.contains(where: { $0.hasPrefix("llm_failure") }) {
            confidence = min(confidence, 0.4)
        }
        if issues.contains("text_extraction_warning") {
            confidence = min(confidence, 0.5)
        }
        return max(0.1, min(confidence, 0.95))
    }

    private func sha256Hex(for data: Data) -> String {
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Image-Based PDF Extraction

    /// Extract content from a PDF by converting pages to images and using vision-capable LLM
    private func extractPDFViaImages(
        fileURL: URL,
        fileData: Data,
        filename: String,
        sizeInBytes: Int,
        contentType: String,
        sha256: String,
        purpose: String,
        timeout: TimeInterval?,
        autoPersist: Bool,
        progress: ExtractionProgressHandler?
    ) async throws -> ExtractionResult {
        func notifyProgress(_ stage: ExtractionProgressStage, _ state: ExtractionProgressStageState, detail: String? = nil) async {
            guard let progress else { return }
            await progress(ExtractionProgressUpdate(stage: stage, state: state, detail: detail))
        }

        // Check page count
        guard let pageCount = ImageConversionService.shared.getPDFPageCount(pdfData: fileData) else {
            await notifyProgress(.fileAnalysis, .failed, detail: "Unable to read PDF")
            throw ExtractionError.unreadableData
        }

        Logger.info("📄 PDF has \(pageCount) pages, max for image extraction is \(maxPagesForImageExtraction)", category: .ai)

        // If too many pages, throw user-facing error
        if pageCount > maxPagesForImageExtraction {
            await notifyProgress(.fileAnalysis, .failed, detail: "PDF has too many pages (\(pageCount))")
            throw ExtractionError.pdfTooLarge(pageCount: pageCount)
        }

        await notifyProgress(.fileAnalysis, .active, detail: "Converting \(pageCount) PDF page(s) to images...")

        // Convert pages to images - get raw Data instead of base64
        guard let imageDataArray = ImageConversionService.shared.convertPDFPagesToImageData(pdfData: fileData, maxPages: maxPagesForImageExtraction),
              !imageDataArray.isEmpty else {
            await notifyProgress(.fileAnalysis, .failed, detail: "Failed to convert PDF pages to images")
            throw ExtractionError.noTextExtracted
        }

        await notifyProgress(.fileAnalysis, .completed, detail: "Converted \(imageDataArray.count) page(s)")

        // Use vision-capable model to extract content
        let aiStageDetail = "Analyzing \(imageDataArray.count) page image(s) with AI..."
        await notifyProgress(.aiExtraction, .active, detail: aiStageDetail)

        let llmStart = Date()
        let enrichmentResult = try await extractTextFromImages(imageDataArray, purpose: purpose)

        let llmDurationMs = Int(Date().timeIntervalSince(llmStart) * 1000)
        Logger.info(
            "📄 Image-based extraction LLM phase completed",
            category: .diagnostics,
            metadata: [
                "filename": filename,
                "page_count": "\(imageDataArray.count)",
                "duration_ms": "\(llmDurationMs)"
            ]
        )

        let aiState: ExtractionProgressStageState = enrichmentResult.issues.contains(where: { $0.hasPrefix("llm_failure") }) ? .failed : .completed
        await notifyProgress(.aiExtraction, aiState)

        var allIssues = ["image_based_extraction"]
        allIssues.append(contentsOf: enrichmentResult.issues)

        let extractedText = enrichmentResult.content ?? ""
        let extractedTitle = enrichmentResult.title
        let confidence = estimateConfidence(for: extractedText, issues: allIssues)
        var metadata: [String: Any] = [
            "character_count": extractedText.count,
            "source_format": contentType,
            "purpose": purpose,
            "source_file_url": fileURL.absoluteString,
            "source_filename": filename,
            "extraction_method": "image_vision",
            "page_count": pageCount
        ]
        if let title = extractedTitle {
            metadata["title"] = title
        }

        let artifact = ExtractedArtifact(
            id: UUID().uuidString,
            filename: filename,
            title: extractedTitle,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            sha256: sha256,
            extractedContent: extractedText,
            metadata: metadata
        )

        let status: ExtractionResult.Status
        if enrichmentResult.issues.contains(where: { $0.hasPrefix("llm_failure") }) {
            status = .partial
        } else {
            status = .ok
        }

        if autoPersist {
            allIssues.append("auto_persist_not_supported")
        }

        let quality = Quality(confidence: confidence, issues: allIssues)

        return ExtractionResult(
            status: status,
            artifact: artifact,
            quality: quality,
            derivedApplicantProfile: nil,
            derivedSkeletonTimeline: nil,
            persisted: false
        )
    }

    /// Extract text from image data using a vision-capable LLM via LLMFacade
    private func extractTextFromImages(_ imageDataArray: [Data], purpose: String) async throws -> EnrichmentResult {
        var issues: [String] = []

        guard let facade = llmFacade else {
            return EnrichmentResult(title: nil, content: "", issues: ["llm_failure_not_configured"])
        }

        let modelId = currentModelId()

        var prompt = """
You are a document extraction assistant. Analyze the provided page images and extract ALL text content into high-quality Markdown.

Requirements:
- Extract all visible text from each page image
- Reconstruct headings, bullet lists, numbered lists, and tables when possible
- Process every page in order with no omissions
- Keep original ordering of sections
- Describe any diagrams, charts, or figures you see
- Do not invent content; only extract what you can see
- Use Markdown tables for tabular data
- For contact details, list them as bullet points
"""
        if purpose == "resume_timeline" {
            prompt += "\n- Highlight employment sections clearly. Use headings per job."
        }
        prompt += """

Respond with a JSON object containing:
- "title": A concise, descriptive title for this document (e.g., "John Smith Resume", "Q3 2024 Project Report")
- "content": The formatted Markdown content extracted from all pages

Example response format:
{"title": "Document Title Here", "content": "# Heading\\n\\nContent here..."}
"""

        do {
            let text = try await callFacadeTextWithImages(
                facade: facade,
                prompt: prompt,
                modelId: modelId,
                images: imageDataArray
            )

            if text.isEmpty {
                issues.append("llm_failure_empty_response")
                return EnrichmentResult(title: nil, content: "", issues: issues)
            }

            let parsed = parseEnrichmentResponse(text)
            return EnrichmentResult(title: parsed.title, content: parsed.content, issues: issues)
        } catch let error as LLMError {
            if case .clientError(let message) = error, message.contains("not found") || message.contains("not valid") {
                onInvalidModelId?(modelId)
                throw ExtractionError.llmFailed("\(modelId) is not a valid model ID.")
            }
            issues.append("llm_failure_\(error.localizedDescription)")
            return EnrichmentResult(title: nil, content: "", issues: issues)
        } catch {
            issues.append("llm_failure_\(error.localizedDescription)")
            return EnrichmentResult(title: nil, content: "", issues: issues)
        }
    }

    // MARK: - MainActor Bridge Methods

    @MainActor
    private func callFacadeText(
        facade: LLMFacade,
        prompt: String,
        modelId: String
    ) async throws -> String {
        try await facade.executeText(
            prompt: prompt,
            modelId: modelId,
            temperature: 0.1
        )
    }

    @MainActor
    private func callFacadeTextWithImages(
        facade: LLMFacade,
        prompt: String,
        modelId: String,
        images: [Data]
    ) async throws -> String {
        try await facade.executeTextWithImages(
            prompt: prompt,
            modelId: modelId,
            images: images,
            temperature: 0.1
        )
    }
}
