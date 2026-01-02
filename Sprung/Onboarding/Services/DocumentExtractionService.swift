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
    private var pdfRouter: PDFExtractionRouter?
    private weak var agentTracker: AgentActivityTracker?

    init(llmFacade: LLMFacade?, eventBus: EventCoordinator? = nil) {
        self.llmFacade = llmFacade
        self.eventBus = eventBus
    }

    func updateEventBus(_ bus: EventCoordinator?) {
        self.eventBus = bus
    }

    /// Set the agent tracker for PDF extraction status display.
    /// The router will be created lazily when first needed.
    func setAgentTracker(_ tracker: AgentActivityTracker) {
        self.agentTracker = tracker
    }

    /// Get or create the PDF extraction router.
    /// Creates lazily on first use with available dependencies.
    private func getOrCreateRouter() -> PDFExtractionRouter? {
        if let router = pdfRouter {
            return router
        }
        guard let facade = llmFacade else {
            Logger.warning("Cannot create PDF router: LLMFacade not available", category: .ai)
            return nil
        }
        let router = PDFExtractionRouter(llmFacade: facade, agentTracker: agentTracker)
        self.pdfRouter = router
        Logger.info("📄 PDF extraction router created", category: .ai)
        return router
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

    // MARK: - PDF Extraction (Router-Based)

    /// Extract content from a PDF using the intelligent extraction router.
    /// The router uses LLM judgment to select the optimal extraction method:
    /// - PDFKit: For high-quality text layer extraction (free, fast)
    /// - Vision OCR: For documents with problematic fonts (free, native)
    /// - LLM Vision: For complex layouts requiring AI understanding (paid, best quality)
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

        let sizeMB = Double(sizeInBytes) / 1_048_576.0
        let pageCount = PDFDocument(data: fileData)?.pageCount ?? 0

        await notifyProgress(.fileAnalysis, .active, detail: "Preparing PDF (\(String(format: "%.1f", sizeMB)) MB)...")

        Logger.info(
            "📄 Starting PDF extraction via router",
            category: .ai,
            metadata: [
                "filename": filename,
                "size_mb": String(format: "%.1f", sizeMB),
                "page_count": "\(pageCount)"
            ]
        )

        await notifyProgress(.fileAnalysis, .completed)
        await notifyProgress(.aiExtraction, .active, detail: "Analyzing document...")

        let extractionStart = Date()

        // Use the intelligent extraction router
        guard let router = getOrCreateRouter() else {
            // Fall back to simple PDFKit if router not configured
            Logger.warning("PDF router not configured, falling back to simple PDFKit extraction", category: .ai)
            let (text, issues, _) = extractPlainText(from: fileURL)

            guard let extractedText = text, !extractedText.isEmpty else {
                await notifyProgress(.aiExtraction, .failed, detail: "No text extracted")
                throw ExtractionError.noTextExtracted
            }

            await notifyProgress(.aiExtraction, .completed)

            return createExtractionResult(
                text: extractedText,
                method: .pdfkit,
                textFidelity: 70,
                filename: filename,
                fileURL: fileURL,
                contentType: contentType,
                sizeInBytes: sizeInBytes,
                sha256: sha256,
                purpose: purpose,
                pageCount: pageCount,
                issues: issues
            )
        }

        // Use the router for intelligent extraction
        let result = try await router.extractText(from: fileData, filename: filename)

        let durationMs = Int(Date().timeIntervalSince(extractionStart) * 1000)
        Logger.info(
            "📄 PDF extraction completed",
            category: .diagnostics,
            metadata: [
                "filename": filename,
                "duration_ms": "\(durationMs)",
                "text_chars": "\(result.text.count)",
                "method": result.method.rawValue,
                "fidelity": "\(result.judgment.textFidelity)%",
                "page_count": "\(result.pageCount)"
            ]
        )

        await notifyProgress(.aiExtraction, .completed, detail: "Extracted via \(result.method.displayDescription)")

        // Build issues list based on extraction result
        var issues: [String] = []
        issues.append(contentsOf: result.judgment.issuesFound)
        if result.method == .visionOCR {
            issues.append("vision_ocr_used")
        } else if result.method == .llmVision {
            issues.append("llm_vision_used")
        }

        return createExtractionResult(
            text: result.text,
            method: result.method,
            textFidelity: result.judgment.textFidelity,
            filename: filename,
            fileURL: fileURL,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            sha256: sha256,
            purpose: purpose,
            pageCount: result.pageCount,
            issues: issues
        )
    }

    /// Create an ExtractionResult from the extraction data.
    private func createExtractionResult(
        text: String,
        method: PDFExtractionMethod,
        textFidelity: Int,
        filename: String,
        fileURL: URL,
        contentType: String,
        sizeInBytes: Int,
        sha256: String,
        purpose: String,
        pageCount: Int,
        issues: [String]
    ) -> ExtractionResult {
        let derivedTitle = filename
            .replacingOccurrences(of: ".pdf", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        let metadata: [String: Any] = [
            "character_count": text.count,
            "plain_text_chars": text.count,
            "source_format": contentType,
            "purpose": purpose,
            "source_file_url": fileURL.absoluteString,
            "source_filename": filename,
            "extraction_method": method.rawValue,
            "text_fidelity": textFidelity,
            "page_count": pageCount
        ]

        let artifact = ExtractedArtifact(
            id: UUID().uuidString,
            filename: filename,
            title: derivedTitle,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            sha256: sha256,
            extractedContent: text,
            metadata: metadata,
            plainTextContent: text,
            graphicsContent: nil,
            graphicsExtractionStatus: .skipped
        )

        let quality = Quality(
            confidence: estimateConfidence(for: text, issues: issues),
            issues: issues
        )

        return ExtractionResult(
            status: issues.isEmpty ? .ok : .partial,
            artifact: artifact,
            quality: quality,
            derivedApplicantProfile: nil,
            derivedSkeletonTimeline: nil,
            persisted: false
        )
    }

}
