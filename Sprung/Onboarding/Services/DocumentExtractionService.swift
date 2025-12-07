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
        let extractionMethod: LargePDFExtractionMethod?

        init(
            fileURL: URL,
            purpose: String,
            returnTypes: [String] = [],
            autoPersist: Bool = false,
            timeout: TimeInterval? = nil,
            extractionMethod: LargePDFExtractionMethod? = nil
        ) {
            self.fileURL = fileURL
            self.purpose = purpose
            self.returnTypes = returnTypes
            self.autoPersist = autoPersist
            self.timeout = timeout
            self.extractionMethod = extractionMethod
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
        case llmFailed(String)
        case llmNotConfigured
        case corruptedOutput(String)

        var userFacingMessage: String {
            switch self {
            case .unsupportedType:
                return "Unsupported document format. Please upload a PDF, DOCX, or plain text file."
            case .unreadableData:
                return "The document could not be read. Please try another file."
            case .noTextExtracted:
                return "The document did not contain extractable text."
            case .llmFailed(let description):
                return "Extraction failed: \(description)"
            case .llmNotConfigured:
                return "PDF extraction model is not configured. Add an OpenRouter API key in Settings."
            case .corruptedOutput(let description):
                return "PDF extraction produced corrupted output: \(description). Try using a different extraction method or model."
            }
        }
    }

    /// Check if extracted content contains corruption indicators (e.g., repeated dots from OCR failures)
    /// Returns a description of the issue if corrupted, nil if content looks okay
    private func detectCorruptedOutput(_ content: String) -> String? {
        // Pattern: 20 or more dots in a row (possibly with spaces)
        // This catches ". . . . . . . . . ." patterns from corrupted PDFs
        let dotPattern = try? NSRegularExpression(pattern: "(?:\\s*\\.\\s*){20,}", options: [])
        if let match = dotPattern?.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) {
            let matchLength = match.range.length
            return "Detected \(matchLength) repeated dots - likely OCR or encoding failure"
        }

        // Also check for very long runs of the same character (500+)
        let repeatedCharPattern = try? NSRegularExpression(pattern: "(.)\\1{500,}", options: [])
        if repeatedCharPattern?.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) != nil {
            return "Detected extremely long character repetition - likely encoding failure"
        }

        return nil
    }

    // MARK: - Private Properties
    private var llmFacade: LLMFacade?
    private let maxCharactersForPrompt = 18_000
    private let defaultModelId = "google/gemini-2.0-flash-001"
    private var availableModelIds: [String] = []

    /// Maximum PDF size for direct upload to Gemini (18MB)
    /// Gemini rejects PDFs around 19-20MB, so we use 18MB as a safe threshold
    private let maxPDFSizeBytes = 18 * 1024 * 1024

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

        // For PDFs: Check extraction method preference
        // - textExtract: Extract text locally with PDFKit, then send to LLM (bypasses size limits)
        // - chunkedNative (default): Send PDF directly to Gemini (chunks if >20MB)
        if fileURL.pathExtension.lowercased() == "pdf" {
            // Use text extraction if explicitly requested, or if large PDF with no preference
            let useTextExtraction = request.extractionMethod == .textExtract

            if useTextExtraction {
                Logger.info("📄 Using text extraction method (PDFKit) for PDF", category: .ai)
                // Use the same text-based flow as other documents
                // extractPlainText handles PDFs via PDFKit
            } else {
                Logger.info("📄 Sending PDF directly to Gemini via OpenRouter", category: .ai)
                return try await extractPDFDirect(
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
        }

        // For non-PDF documents (DOCX, text): Extract text first, then send to LLM
        let (rawText, initialIssues, _) = extractPlainText(from: fileURL)

        guard let rawText, !rawText.isEmpty else {
            await notifyProgress(.fileAnalysis, .failed, detail: "No extractable text")
            throw ExtractionError.noTextExtracted
        }

        await notifyProgress(.fileAnalysis, .completed)

        let llmStart = Date()
        let aiStageDetail = request.purpose == "resume_timeline"
            ? "Extracting resume details with Gemini AI..."
            : "Processing document with Gemini AI..."
        await notifyProgress(.aiExtraction, .active, detail: aiStageDetail)

        let enrichmentResult = try await enrichText(rawText, purpose: request.purpose, timeout: request.timeout)

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

    // MARK: - PDF Extraction

    /// Extract content from a PDF by sending it directly to OpenRouter
    /// OpenRouter automatically parses PDFs using pdf-text engine (free) for any model
    /// For PDFs > 20MB: compress first, then split if still too large
    private func extractPDFDirect(
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

        await notifyProgress(.fileAnalysis, .active, detail: "Preparing PDF for extraction...")

        guard let facade = llmFacade else {
            await notifyProgress(.fileAnalysis, .failed, detail: "LLM not configured")
            throw ExtractionError.llmFailed("LLM facade not configured")
        }

        let modelId = currentModelId()

        if sizeInBytes > maxPDFSizeBytes {
            let sizeMB = Double(sizeInBytes) / 1_048_576.0
            Logger.info(
                "📄 PDF exceeds 20MB limit (\(String(format: "%.1f", sizeMB))MB), splitting into chunks...",
                category: .ai
            )
            await notifyProgress(.fileAnalysis, .active, detail: "Splitting large PDF into chunks...")

            guard let chunks = splitPDF(data: fileData, filename: filename) else {
                await notifyProgress(.fileAnalysis, .failed, detail: "Failed to split PDF")
                throw ExtractionError.llmFailed("Failed to split large PDF into chunks")
            }

            await notifyProgress(.fileAnalysis, .completed, detail: "Split into \(chunks.count) chunks")

            // Process chunks serially
            let (extractedTitle, combinedContent) = try await processChunkedPDF(
                chunks: chunks,
                filename: filename,
                modelId: modelId,
                facade: facade,
                progress: progress
            )

            await notifyProgress(.aiExtraction, .completed)

            var metadata: [String: Any] = [
                "character_count": combinedContent.count,
                "source_format": contentType,
                "purpose": purpose,
                "source_file_url": fileURL.absoluteString,
                "source_filename": filename,
                "extraction_method": "chunked_pdf",
                "chunks_processed": chunks.count
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
                extractedContent: combinedContent,
                metadata: metadata
            )

            let quality = Quality(confidence: estimateConfidence(for: combinedContent, issues: []), issues: [])

            // Check for corrupted output before returning
            if let corruptionIssue = detectCorruptedOutput(combinedContent) {
                Logger.error("📄 Chunked PDF extraction produced corrupted output: \(corruptionIssue)", category: .ai)
                await notifyProgress(.aiExtraction, .failed, detail: corruptionIssue)
                throw ExtractionError.corruptedOutput(corruptionIssue)
            }

            return ExtractionResult(
                status: .ok,
                artifact: artifact,
                quality: quality,
                derivedApplicantProfile: nil,
                derivedSkeletonTimeline: nil,
                persisted: false
            )
        }

        await notifyProgress(.fileAnalysis, .completed, detail: "Using \(modelId)")

        let prompt = """
Extract and summarize the content of this PDF to support resume and cover letter drafting for the applicant (me).

Output format: Provide a structured, page-by-page transcription in markdown.

Content handling rules:
- Text passages: Transcribe verbatim when feasible. For lengthy sections, provide a comprehensive summary that preserves key details, achievements, and distinctive phrasing.
- Original writing by the applicant (essays, statements, project descriptions): Quote in full or summarize exhaustively—do not omit substantive content.
- Diagrams, figures, and visual content: Provide a brief description of key elements and their purpose/significance.

Framing: This document is being prepared as source material for my own application materials. Highlight strengths, accomplishments, and distinguishing qualifications. This is not intended as a neutral third-party assessment—advocate for the candidate where the evidence supports it.

When summarizing, include brief qualitative notes on what makes particular achievements or experiences notable (e.g., scope, difficulty, originality, impact).

Respond with a JSON object containing:
- "title": A concise, descriptive title for this document (e.g., "John Smith Resume", "Q3 2024 Project Report")
- "content": The structured, page-by-page transcription in markdown format

Example response format:
{"title": "Document Title Here", "content": "# Page 1\\n\\nContent here..."}
"""

        await notifyProgress(.aiExtraction, .active, detail: "Extracting text from PDF...")

        let llmStart = Date()
        do {
            let text = try await callFacadeTextWithPDF(
                facade: facade,
                prompt: prompt,
                pdfData: fileData,
                modelId: modelId
            )

            let llmDurationMs = Int(Date().timeIntervalSince(llmStart) * 1000)
            Logger.info(
                "📄 Direct PDF extraction completed",
                category: .diagnostics,
                metadata: [
                    "filename": filename,
                    "duration_ms": "\(llmDurationMs)"
                ]
            )

            if text.isEmpty {
                await notifyProgress(.aiExtraction, .failed, detail: "No text extracted")
                throw ExtractionError.noTextExtracted
            }

            let parsed = parseEnrichmentResponse(text)
            let extractedText = parsed.content
            let extractedTitle = parsed.title

            await notifyProgress(.aiExtraction, .completed)

            var metadata: [String: Any] = [
                "character_count": extractedText.count,
                "source_format": contentType,
                "purpose": purpose,
                "source_file_url": fileURL.absoluteString,
                "source_filename": filename,
                "extraction_method": "native_pdf"
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

            let quality = Quality(confidence: estimateConfidence(for: extractedText, issues: []), issues: [])

            // Check for corrupted output before returning
            if let corruptionIssue = detectCorruptedOutput(extractedText) {
                Logger.error("📄 Direct PDF extraction produced corrupted output: \(corruptionIssue)", category: .ai)
                await notifyProgress(.aiExtraction, .failed, detail: corruptionIssue)
                throw ExtractionError.corruptedOutput(corruptionIssue)
            }

            return ExtractionResult(
                status: .ok,
                artifact: artifact,
                quality: quality,
                derivedApplicantProfile: nil,
                derivedSkeletonTimeline: nil,
                persisted: false
            )
        } catch {
            await notifyProgress(.aiExtraction, .failed, detail: error.localizedDescription)
            throw ExtractionError.llmFailed(error.localizedDescription)
        }
    }

    // MARK: - PDF Size Management

    /// Split a PDF into chunks that each stay under maxPDFSizeBytes
    /// Strategy: Split into fixed 25-page chunks, then merge adjacent chunks where possible
    private func splitPDF(data: Data, filename: String) -> [(data: Data, pageRange: String)]? {
        guard let document = PDFDocument(data: data) else {
            Logger.warning("📄 Failed to load PDF for splitting", category: .ai)
            return nil
        }

        let totalPages = document.pageCount
        guard totalPages > 0 else { return nil }

        // Step 1: Create fixed 25-page chunks
        let chunkSize = 25
        var rawChunks: [(doc: PDFDocument, startPage: Int, endPage: Int)] = []

        for startPage in stride(from: 0, to: totalPages, by: chunkSize) {
            let endPage = min(startPage + chunkSize - 1, totalPages - 1)
            let chunkDoc = PDFDocument()

            for pageIndex in startPage...endPage {
                guard let page = document.page(at: pageIndex) else { continue }
                chunkDoc.insert(page, at: chunkDoc.pageCount)
            }

            rawChunks.append((doc: chunkDoc, startPage: startPage, endPage: endPage))
        }

        // Step 2: Merge adjacent chunks where combined size stays under limit
        var mergedChunks: [(data: Data, pageRange: String)] = []
        var pendingChunk: (doc: PDFDocument, startPage: Int, endPage: Int)?

        for chunk in rawChunks {
            if let pending = pendingChunk {
                // Try merging pending with current
                let combined = PDFDocument()
                for i in 0..<pending.doc.pageCount {
                    if let page = pending.doc.page(at: i) {
                        combined.insert(page, at: combined.pageCount)
                    }
                }
                for i in 0..<chunk.doc.pageCount {
                    if let page = chunk.doc.page(at: i) {
                        combined.insert(page, at: combined.pageCount)
                    }
                }

                if let combinedData = combined.dataRepresentation(), combinedData.count <= maxPDFSizeBytes {
                    // Merge succeeded - keep combined as pending
                    pendingChunk = (doc: combined, startPage: pending.startPage, endPage: chunk.endPage)
                } else {
                    // Can't merge - finalize pending, start new pending with current
                    if let pendingData = pending.doc.dataRepresentation() {
                        let pageRange = "\(pending.startPage + 1)-\(pending.endPage + 1)"
                        mergedChunks.append((data: pendingData, pageRange: pageRange))
                    }
                    pendingChunk = chunk
                }
            } else {
                pendingChunk = chunk
            }
        }

        // Finalize last pending chunk
        if let pending = pendingChunk, let pendingData = pending.doc.dataRepresentation() {
            let pageRange = "\(pending.startPage + 1)-\(pending.endPage + 1)"
            mergedChunks.append((data: pendingData, pageRange: pageRange))
        }

        // Log results
        for chunk in mergedChunks {
            Logger.debug(
                "📄 Created PDF chunk",
                category: .ai,
                metadata: [
                    "filename": filename,
                    "pages": chunk.pageRange,
                    "size_mb": String(format: "%.2f", Double(chunk.data.count) / 1_048_576.0)
                ]
            )
        }

        Logger.info(
            "📄 PDF split complete",
            category: .ai,
            metadata: [
                "filename": filename,
                "total_pages": "\(totalPages)",
                "chunks": "\(mergedChunks.count)"
            ]
        )

        return mergedChunks.isEmpty ? nil : mergedChunks
    }

    /// Process PDF chunks serially, building a continuous summary
    /// Each chunk receives the previous summary and appends to it for coherent output
    private func processChunkedPDF(
        chunks: [(data: Data, pageRange: String)],
        filename: String,
        modelId: String,
        facade: LLMFacade,
        progress: ExtractionProgressHandler?
    ) async throws -> (title: String?, content: String) {
        func notifyProgress(_ stage: ExtractionProgressStage, _ state: ExtractionProgressStageState, detail: String? = nil) async {
            guard let progress else { return }
            await progress(ExtractionProgressUpdate(stage: stage, state: state, detail: detail))
        }

        var accumulatedContent = ""
        var extractedTitle: String?
        let totalChunks = chunks.count

        for (index, chunk) in chunks.enumerated() {
            let chunkNumber = index + 1
            let isFirstChunk = index == 0

            await notifyProgress(
                .aiExtraction,
                .active,
                detail: "Processing chunk \(chunkNumber)/\(totalChunks) (pages \(chunk.pageRange))..."
            )

            let chunkPrompt: String
            if isFirstChunk {
                // First chunk: extract content
                chunkPrompt = """
Extract and summarize the content of this PDF section (pages \(chunk.pageRange) of a \(totalChunks)-part document) to support resume and cover letter drafting for the applicant (me).

Output format: Provide a structured, page-by-page transcription in markdown.

Content handling rules:
- Text passages: Transcribe verbatim when feasible. For lengthy sections, provide a comprehensive summary that preserves key details, achievements, and distinctive phrasing.
- Original writing by the applicant (essays, statements, project descriptions): Quote in full or summarize exhaustively—do not omit substantive content.
- Diagrams, figures, and visual content: Provide a brief description of key elements and their purpose/significance.

Framing: This document is being prepared as source material for my own application materials. Highlight strengths, accomplishments, and distinguishing qualifications. This is not intended as a neutral third-party assessment—advocate for the candidate where the evidence supports it.

When summarizing, include brief qualitative notes on what makes particular achievements or experiences notable (e.g., scope, difficulty, originality, impact).

Respond with a JSON object containing:
- "title": A concise, descriptive title for this document (e.g., "John Smith Resume", "Q3 2024 Project Report")
- "content": The structured, page-by-page transcription in markdown format

Example: {"title": "Document Title Here", "content": "# Page 1\\n\\nContent here..."}
"""
            } else {
                // Subsequent chunks: append to existing extracted content
                chunkPrompt = """
You are continuing to extract content from a multi-part PDF document. This is part \(chunkNumber) of \(totalChunks) (pages \(chunk.pageRange)).

Here is the extracted content from the previous sections:
---
\(accumulatedContent)
---

Now extract the content from this new section and APPEND it to the existing extracted content. The final result should read as a continuous, coherent document—not separate chunks.

Content handling rules:
- Integrate new content seamlessly with the existing extraction
- Maintain consistent formatting and structure
- Text passages: Transcribe verbatim when feasible, or provide comprehensive summaries preserving key details
- Original writing by the applicant: Quote in full or summarize exhaustively—do not omit substantive content
- Diagrams, figures, and visual content: Provide brief descriptions of key elements

Framing: This document is being prepared as source material for the applicant's job materials. Highlight strengths, accomplishments, and distinguishing qualifications. Advocate for the candidate where the evidence supports it.

Respond with a JSON object containing:
- "title": null (title already captured)
- "content": The COMPLETE updated extraction (previous content + new content integrated together)

Important: Return the full accumulated extracted content, not just the new section.
"""
            }

            do {
                let text = try await callFacadeTextWithPDF(
                    facade: facade,
                    prompt: chunkPrompt,
                    pdfData: chunk.data,
                    modelId: modelId
                )

                if !text.isEmpty {
                    let parsed = parseEnrichmentResponse(text)

                    // Capture title from first chunk
                    if isFirstChunk, let title = parsed.title {
                        extractedTitle = title
                    }

                    // Update accumulated content
                    accumulatedContent = parsed.content
                }

                Logger.info(
                    "📄 Chunk \(chunkNumber)/\(totalChunks) processed",
                    category: .ai,
                    metadata: [
                        "pages": chunk.pageRange,
                        "accumulated_chars": "\(accumulatedContent.count)"
                    ]
                )
            } catch {
                Logger.error(
                    "📄 Chunk \(chunkNumber) failed: \(error.localizedDescription)",
                    category: .ai
                )
                // Fail fast on chunk errors - don't create partial artifacts
                throw ExtractionError.llmFailed("PDF extraction failed on pages \(chunk.pageRange): \(error.localizedDescription)")
            }
        }

        return (extractedTitle, accumulatedContent)
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

    /// Call LLMFacade for PDF extraction
    /// Note: NOT marked @MainActor - Swift automatically hops to MainActor when calling
    /// facade.executeTextWithPDF. Keeping this function off MainActor reduces contention
    /// with event processing that runs on MainActor via CoordinatorEventRouter.
    private func callFacadeTextWithPDF(
        facade: LLMFacade,
        prompt: String,
        pdfData: Data,
        modelId: String,
        maxTokens: Int? = 16000
    ) async throws -> String {
        try await facade.executeTextWithPDF(
            prompt: prompt,
            modelId: modelId,
            pdfData: pdfData,
            temperature: 0.1,
            maxTokens: maxTokens
        )
    }
}
