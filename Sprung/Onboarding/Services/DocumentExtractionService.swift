import Foundation
import PDFKit
import UniformTypeIdentifiers
import CryptoKit
import SwiftyJSON

/// Lightweight service that orchestrates document extraction.
/// - PDFs: Sent to Google's Files API (Gemini) for extraction with detailed prompting
/// - Text/DOCX: Extracted directly without LLM processing, preserving original content
actor DocumentExtractionService {
    var onInvalidModelId: ((String) -> Void)?

    struct ExtractionRequest {
        let fileURL: URL
        let purpose: String
        let returnTypes: [String]
        let autoPersist: Bool
        let timeout: TimeInterval?
        let extractionMethod: LargePDFExtractionMethod?
        /// Original filename for user-facing messages (storage URL may have UUID prefix)
        let displayFilename: String?

        init(
            fileURL: URL,
            purpose: String,
            returnTypes: [String] = [],
            autoPersist: Bool = false,
            timeout: TimeInterval? = nil,
            extractionMethod: LargePDFExtractionMethod? = nil,
            displayFilename: String? = nil
        ) {
            self.fileURL = fileURL
            self.purpose = purpose
            self.returnTypes = returnTypes
            self.autoPersist = autoPersist
            self.timeout = timeout
            self.extractionMethod = extractionMethod
            self.displayFilename = displayFilename
        }
    }

    struct ExtractedArtifact {
        let id: String
        let filename: String
        let title: String?
        let contentType: String
        let sizeInBytes: Int
        let sha256: String
        let extractedContent: String      // Combined content (text + graphics for backward compat)
        let metadata: [String: Any]

        // Two-pass extraction results (PDFs only)
        let plainTextContent: String?     // Pass 1: PDFKit local extraction
        let graphicsContent: String?      // Pass 2: LLM visual descriptions
        let graphicsExtractionStatus: GraphicsExtractionStatus

        enum GraphicsExtractionStatus: String {
            case success = "success"
            case failed = "failed"
            case skipped = "skipped"   // Non-PDF or extraction not applicable
        }
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
                return "PDF extraction model is not configured. Add a Gemini API key in Settings."
            case .corruptedOutput(let description):
                return "PDF extraction produced corrupted output: \(description). Try using a different extraction method or model."
            }
        }
    }

    // MARK: - Private Properties
    private var llmFacade: LLMFacade?
    private let defaultModelId = "gemini-2.5-flash"
    private var eventBus: EventCoordinator?

    init(llmFacade: LLMFacade?, eventBus: EventCoordinator? = nil) {
        self.llmFacade = llmFacade
        self.eventBus = eventBus
    }

    func updateEventBus(_ bus: EventCoordinator?) {
        self.eventBus = bus
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
        // Use displayFilename if provided, otherwise fall back to URL's lastPathComponent
        let filename = request.displayFilename ?? fileURL.lastPathComponent
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
                Logger.info("📄 Sending PDF directly to Gemini via Google Files API", category: .ai)
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

        // For non-PDF documents (DOCX, text): Extract text directly without LLM processing
        // Text files are passed directly to the interview LLM as artifacts
        let (rawText, initialIssues, _) = extractPlainText(from: fileURL)

        guard let rawText, !rawText.isEmpty else {
            await notifyProgress(.fileAnalysis, .failed, detail: "No extractable text")
            throw ExtractionError.noTextExtracted
        }

        await notifyProgress(.fileAnalysis, .completed)

        // Skip AI extraction stage for text documents - just use raw text
        await notifyProgress(.aiExtraction, .completed, detail: "Text extracted directly")

        // Derive title from filename (remove extension)
        let derivedTitle = filename
            .replacingOccurrences(of: ".\(fileURL.pathExtension)", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        let confidence = estimateConfidence(for: rawText, issues: initialIssues)

        let metadata: [String: Any] = [
            "character_count": rawText.count,
            "source_format": contentType,
            "purpose": request.purpose,
            "source_file_url": fileURL.absoluteString,
            "source_filename": filename,
            "extraction_method": "direct_text"
        ]

        let artifact = ExtractedArtifact(
            id: UUID().uuidString,
            filename: filename,
            title: derivedTitle,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            sha256: sha256,
            extractedContent: rawText,
            metadata: metadata,
            plainTextContent: rawText,
            graphicsContent: nil,
            graphicsExtractionStatus: .skipped  // Non-PDF documents
        )

        let status: ExtractionResult.Status = initialIssues.contains("text_extraction_warning") ? .partial : .ok

        let quality = Quality(confidence: confidence, issues: initialIssues)

        let totalMs = Int(Date().timeIntervalSince(extractionStart) * 1000)
        Logger.info(
            "📄 Text extraction finished",
            category: .diagnostics,
            metadata: [
                "filename": filename,
                "duration_ms": "\(totalMs)",
                "chars": "\(rawText.count)"
            ]
        )

        return ExtractionResult(
            status: status,
            artifact: artifact,
            quality: quality,
            derivedApplicantProfile: nil,
            derivedSkeletonTimeline: nil,
            persisted: false
        )
    }

    // MARK: - Helpers

    private func currentModelId() -> String {
        // Model IDs are now Gemini format (e.g., "gemini-2.0-flash") not OpenRouter format
        // Validation happens in SettingsView when models are loaded from Google API
        UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId") ?? defaultModelId
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

    // MARK: - PDF Extraction (Two-Pass)

    /// Extract content from a PDF using two-pass parallel extraction:
    /// - Pass 1: Local PDFKit text extraction (fast, reliable)
    /// - Pass 2: LLM graphics extraction (describes figures, charts, diagrams)
    /// Both passes run in parallel. Graphics extraction failure doesn't block processing.
    private func extractPDFDirect(
        fileURL: URL,
        fileData: Data,
        filename: String,
        sizeInBytes: Int,
        contentType: String,
        sha256: String,
        purpose: String,
        timeout: TimeInterval?,
        autoPersist _: Bool,
        progress: ExtractionProgressHandler?
    ) async throws -> ExtractionResult {
        func notifyProgress(_ stage: ExtractionProgressStage, _ state: ExtractionProgressStageState, detail: String? = nil) async {
            guard let progress else { return }
            await progress(ExtractionProgressUpdate(stage: stage, state: state, detail: detail))
        }

        let modelId = currentModelId()
        let sizeMB = Double(sizeInBytes) / 1_048_576.0
        let pageCount = PDFDocument(data: fileData)?.pageCount

        await notifyProgress(.fileAnalysis, .active, detail: "Preparing PDF (\(String(format: "%.1f", sizeMB)) MB)...")

        Logger.info(
            "📄 Starting two-pass PDF extraction",
            category: .ai,
            metadata: [
                "filename": filename,
                "size_mb": String(format: "%.1f", sizeMB),
                "model": modelId,
                "page_count": pageCount.map(String.init) ?? "unknown"
            ]
        )

        await notifyProgress(.fileAnalysis, .completed, detail: "Using \(modelId)")
        await notifyProgress(.aiExtraction, .active, detail: "Extracting text and analyzing graphics...")

        let extractionStart = Date()

        // Two-pass parallel extraction
        // Pass 1: Local PDFKit text extraction
        // Pass 2: LLM graphics extraction (gracefully handles failure)

        // Run both passes in parallel
        async let textTask: (String?, [String], Int?) = extractPlainText(from: fileURL)
        async let graphicsTask: (graphics: String?, error: String?) = extractGraphicsWithGracefulFailure(
            pdfData: fileData,
            filename: filename
        )

        // Wait for both to complete
        let (plainText, textIssues, extractedPageCount) = await textTask
        let graphicsResult = await graphicsTask

        // Validate PDFKit extraction quality
        let textQuality = validateTextExtraction(
            text: plainText ?? "",
            pageCount: extractedPageCount ?? pageCount ?? 1
        )
        Logger.info("PDF extraction quality: \(textQuality.diagnosticSummary)", category: .ai)

        // Pass 1 must succeed - we need text content
        guard let plainText, !plainText.isEmpty else {
            await notifyProgress(.aiExtraction, .failed, detail: "No text extracted from PDF")
            throw ExtractionError.noTextExtracted
        }

        // Log quality assessment for future vision fallback integration
        if textQuality.isAcceptable {
            Logger.info("PDFKit text quality acceptable (\(String(format: "%.0f%%", textQuality.score * 100)))", category: .ai)
        } else if textQuality.requiresVisionFallback {
            Logger.warning("PDFKit quality too low (\(String(format: "%.0f%%", textQuality.score * 100))) - vision fallback recommended", category: .ai)
        } else {
            Logger.warning("PDFKit quality marginal (\(String(format: "%.0f%%", textQuality.score * 100)))", category: .ai)
        }

        // Log results
        let durationMs = Int(Date().timeIntervalSince(extractionStart) * 1000)
        Logger.info(
            "📄 Two-pass PDF extraction completed",
            category: .diagnostics,
            metadata: [
                "filename": filename,
                "duration_ms": "\(durationMs)",
                "text_chars": "\(plainText.count)",
                "graphics_status": graphicsResult.graphics != nil ? "success" : "failed",
                "page_count": pageCount.map(String.init) ?? "unknown"
            ]
        )

        // Emit token usage for graphics extraction if available
        // (Text extraction is local, no token usage)

        await notifyProgress(.aiExtraction, .completed)

        // Combine content for downstream processing
        let combinedContent: String
        if let graphics = graphicsResult.graphics {
            combinedContent = """
            --- EXTRACTED TEXT ---
            \(plainText)

            --- VISUAL CONTENT ANALYSIS ---
            \(graphics)
            """
        } else {
            combinedContent = plainText
        }

        // Determine graphics extraction status
        let graphicsStatus: ExtractedArtifact.GraphicsExtractionStatus
        if graphicsResult.graphics != nil {
            graphicsStatus = .success
        } else {
            graphicsStatus = .failed
        }

        // Derive title from filename
        let derivedTitle = filename
            .replacingOccurrences(of: ".pdf", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        var metadata: [String: Any] = [
            "character_count": combinedContent.count,
            "plain_text_chars": plainText.count,
            "source_format": contentType,
            "purpose": purpose,
            "source_file_url": fileURL.absoluteString,
            "source_filename": filename,
            "extraction_method": "two_pass_parallel"
        ]
        if let pageCount {
            metadata["page_count"] = pageCount
        }
        metadata["graphics_extraction_status"] = graphicsStatus.rawValue
        if let graphicsError = graphicsResult.error {
            metadata["graphics_extraction_error"] = graphicsError
        }
        if let graphics = graphicsResult.graphics {
            metadata["graphics_chars"] = graphics.count
        }

        let artifact = ExtractedArtifact(
            id: UUID().uuidString,
            filename: filename,
            title: derivedTitle,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            sha256: sha256,
            extractedContent: combinedContent,
            metadata: metadata,
            plainTextContent: plainText,
            graphicsContent: graphicsResult.graphics,
            graphicsExtractionStatus: graphicsStatus
        )

        let issues = textIssues + (graphicsResult.error != nil ? ["graphics_extraction_failed"] : [])
        let quality = Quality(confidence: estimateConfidence(for: plainText, issues: issues), issues: issues)

        return ExtractionResult(
            status: graphicsResult.error != nil ? .partial : .ok,
            artifact: artifact,
            quality: quality,
            derivedApplicantProfile: nil,
            derivedSkeletonTimeline: nil,
            persisted: false
        )
    }

    /// Extract graphics from PDF with graceful failure handling.
    /// Returns (graphics: String?, error: String?) - graphics is nil if extraction failed.
    private func extractGraphicsWithGracefulFailure(
        pdfData: Data,
        filename: String
    ) async -> (graphics: String?, error: String?) {
        guard let facade = llmFacade else {
            return (nil, "LLM not configured")
        }

        do {
            let (graphics, tokenUsage) = try await facade.extractGraphicsFromPDF(
                pdfData: pdfData,
                filename: filename
            )

            // Emit token usage if available
            if let usage = tokenUsage, let eventBus = eventBus {
                let modelId = currentModelId()
                await eventBus.publish(.llmTokenUsageReceived(
                    modelId: modelId,
                    inputTokens: usage.promptTokenCount,
                    outputTokens: usage.candidatesTokenCount,
                    cachedTokens: 0,
                    reasoningTokens: 0,
                    source: .documentExtraction
                ))
            }

            return (graphics, nil)
        } catch {
            Logger.warning("⚠️ Graphics extraction failed for \(filename): \(error.localizedDescription)", category: .ai)
            return (nil, error.localizedDescription)
        }
    }

    // MARK: - Vision Text Extraction

    /// Extract text from a PDF using Gemini vision.
    /// Used when PDFKit text extraction fails (e.g., complex fonts).
    /// Automatically chooses single-pass or chunked extraction based on page count.
    ///
    /// - Parameters:
    ///   - pdfData: The PDF file data
    ///   - filename: Display name for the file
    ///   - pageCount: Number of pages in the PDF
    ///   - progress: Progress handler for UI updates
    /// - Returns: Extracted text content
    func extractWithVision(
        pdfData: Data,
        filename: String,
        pageCount: Int,
        progress: ExtractionProgressHandler?
    ) async throws -> String {
        if pageCount <= ExtractionConfig.singlePassThreshold {
            return try await extractTextSinglePass(
                pdfData: pdfData,
                filename: filename,
                pageCount: pageCount,
                progress: progress
            )
        } else {
            return try await extractTextChunked(
                pdfData: pdfData,
                filename: filename,
                pageCount: pageCount,
                progress: progress
            )
        }
    }

    /// Single-pass vision text extraction for documents ≤30 pages.
    private func extractTextSinglePass(
        pdfData: Data,
        filename: String,
        pageCount: Int,
        progress: ExtractionProgressHandler?
    ) async throws -> String {
        guard let facade = llmFacade else {
            throw ExtractionError.llmNotConfigured
        }

        await progress?(ExtractionProgressUpdate(
            stage: .aiExtraction,
            state: .active,
            detail: "Extracting text from \(pageCount) pages..."
        ))

        let prompt = DocumentExtractionPrompts.visionTextExtractionPrompt(
            filename: filename,
            pageCount: pageCount
        )

        let startTime = Date()

        let (text, tokenUsage) = try await facade.generateFromPDF(
            pdfData: pdfData,
            filename: filename,
            prompt: prompt,
            maxOutputTokens: ExtractionConfig.singlePassMaxTokens
        )

        let duration = Date().timeIntervalSince(startTime)

        Logger.info(
            "Single-pass vision extraction complete",
            category: .ai,
            metadata: [
                "chars": "\(text.count)",
                "duration_sec": String(format: "%.1f", duration),
                "input_tokens": "\(tokenUsage?.promptTokenCount ?? 0)",
                "output_tokens": "\(tokenUsage?.candidatesTokenCount ?? 0)"
            ]
        )

        // Emit token usage
        if let usage = tokenUsage, let eventBus = eventBus {
            let modelId = currentModelId()
            await eventBus.publish(.llmTokenUsageReceived(
                modelId: modelId,
                inputTokens: usage.promptTokenCount,
                outputTokens: usage.candidatesTokenCount,
                cachedTokens: 0,
                reasoningTokens: 0,
                source: .documentExtraction
            ))
        }

        await progress?(ExtractionProgressUpdate(
            stage: .aiExtraction,
            state: .active,
            detail: "Extracted \(text.count.formatted()) characters"
        ))

        return text
    }

    /// Chunked vision text extraction for documents >30 pages with streaming progress.
    private func extractTextChunked(
        pdfData: Data,
        filename: String,
        pageCount: Int,
        progress: ExtractionProgressHandler?
    ) async throws -> String {
        guard let document = PDFDocument(data: pdfData) else {
            throw ExtractionError.unreadableData
        }

        let chunkSize = ExtractionConfig.chunkSize
        let totalChunks = (pageCount + chunkSize - 1) / chunkSize
        var chunks: [String] = []
        var totalCharsExtracted = 0
        let overallStart = Date()

        Logger.info(
            "Starting chunked extraction: \(pageCount) pages in \(totalChunks) chunks",
            category: .ai
        )

        for (chunkIndex, chunkStart) in stride(from: 0, to: pageCount, by: chunkSize).enumerated() {
            let chunkEnd = min(chunkStart + chunkSize, pageCount)
            let chunkNum = chunkIndex + 1
            let percentComplete = Int((Double(chunkIndex) / Double(totalChunks)) * 100)

            // Calculate time estimate
            let elapsed = Date().timeIntervalSince(overallStart)
            let avgSecsPerChunk = chunkIndex > 0 ? elapsed / Double(chunkIndex) : 5.0
            let remainingChunks = totalChunks - chunkIndex
            let estimatedRemaining = Int(avgSecsPerChunk * Double(remainingChunks))

            // Stream progress to UI
            let progressDetail: String
            if estimatedRemaining > 60 {
                progressDetail = "Extracting pages \(chunkStart + 1)-\(chunkEnd) of \(pageCount) " +
                               "(\(percentComplete)%) - ~\(estimatedRemaining / 60)m remaining"
            } else if estimatedRemaining > 10 {
                progressDetail = "Extracting pages \(chunkStart + 1)-\(chunkEnd) of \(pageCount) " +
                               "(\(percentComplete)%) - ~\(estimatedRemaining)s remaining"
            } else {
                progressDetail = "Extracting pages \(chunkStart + 1)-\(chunkEnd) of \(pageCount) (\(percentComplete)%)"
            }

            await progress?(ExtractionProgressUpdate(
                stage: .aiExtraction,
                state: .active,
                detail: progressDetail
            ))

            // Create PDF subset for this chunk
            let chunkDocument = PDFDocument()
            for pageIndex in chunkStart..<chunkEnd {
                if let page = document.page(at: pageIndex) {
                    chunkDocument.insert(page, at: chunkDocument.pageCount)
                }
            }

            guard let chunkData = chunkDocument.dataRepresentation() else {
                Logger.warning("Failed to create chunk PDF for pages \(chunkStart + 1)-\(chunkEnd)", category: .ai)
                continue
            }

            // Extract this chunk with retry
            let chunkText = try await extractChunkWithRetry(
                pdfData: chunkData,
                filename: filename,
                startPage: chunkStart + 1,
                endPage: chunkEnd,
                totalPages: pageCount,
                chunkNumber: chunkNum,
                totalChunks: totalChunks
            )

            chunks.append(chunkText)
            totalCharsExtracted += chunkText.count

            Logger.info(
                "Chunk \(chunkNum)/\(totalChunks) complete: \(chunkText.count) chars",
                category: .ai
            )

            // Rate limit protection between chunks
            if chunkEnd < pageCount {
                try await Task.sleep(for: .milliseconds(ExtractionConfig.interChunkDelayMs))
            }
        }

        let totalDuration = Date().timeIntervalSince(overallStart)

        Logger.info(
            "Chunked extraction complete",
            category: .ai,
            metadata: [
                "total_chars": "\(totalCharsExtracted)",
                "chunks": "\(chunks.count)/\(totalChunks)",
                "duration_sec": String(format: "%.1f", totalDuration)
            ]
        )

        // Final progress update
        await progress?(ExtractionProgressUpdate(
            stage: .aiExtraction,
            state: .active,
            detail: "Extracted \(totalCharsExtracted.formatted()) characters from \(pageCount) pages"
        ))

        guard !chunks.isEmpty else {
            throw ExtractionError.noTextExtracted
        }

        // Combine chunks with page markers
        return chunks.enumerated().map { (index, text) in
            let startPage = index * chunkSize + 1
            let endPage = min(startPage + chunkSize - 1, pageCount)
            return "--- PAGES \(startPage)-\(endPage) ---\n\n\(text)"
        }.joined(separator: "\n\n")
    }

    /// Extract a single chunk with retry logic.
    private func extractChunkWithRetry(
        pdfData: Data,
        filename: String,
        startPage: Int,
        endPage: Int,
        totalPages: Int,
        chunkNumber: Int,
        totalChunks: Int
    ) async throws -> String {
        guard let facade = llmFacade else {
            throw ExtractionError.llmNotConfigured
        }

        let prompt = DocumentExtractionPrompts.visionTextExtractionPromptForChunk(
            filename: filename,
            startPage: startPage,
            endPage: endPage,
            totalPages: totalPages,
            chunkNumber: chunkNumber,
            totalChunks: totalChunks
        )

        var lastError: Error?
        let maxRetries = ExtractionConfig.maxChunkRetries

        for attempt in 1...(maxRetries + 1) {
            do {
                let (text, tokenUsage) = try await facade.generateFromPDF(
                    pdfData: pdfData,
                    filename: "\(filename)_pages_\(startPage)-\(endPage)",
                    prompt: prompt,
                    maxOutputTokens: ExtractionConfig.chunkMaxTokens
                )

                // Emit token usage
                if let usage = tokenUsage, let eventBus = eventBus {
                    let modelId = currentModelId()
                    await eventBus.publish(.llmTokenUsageReceived(
                        modelId: modelId,
                        inputTokens: usage.promptTokenCount,
                        outputTokens: usage.candidatesTokenCount,
                        cachedTokens: 0,
                        reasoningTokens: 0,
                        source: .documentExtraction
                    ))
                }

                return text
            } catch {
                lastError = error
                Logger.warning(
                    "Chunk \(chunkNumber) attempt \(attempt) failed: \(error.localizedDescription)",
                    category: .ai
                )
                if attempt <= maxRetries {
                    try await Task.sleep(for: .seconds(Double(attempt) * 2))
                }
            }
        }

        throw lastError ?? ExtractionError.llmFailed("Chunk extraction failed after \(maxRetries + 1) attempts")
    }

}
