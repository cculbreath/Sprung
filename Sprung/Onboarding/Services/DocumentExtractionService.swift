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
                return "PDF extraction model is not configured. Add a Gemini API key in Settings."
            case .corruptedOutput(let description):
                return "PDF extraction produced corrupted output: \(description). Try using a different extraction method or model."
            }
        }
    }

    // MARK: - Private Properties
    private var llmFacade: LLMFacade?
    private let googleAIService = GoogleAIService()
    private let defaultModelId = "gemini-2.0-flash"
    private var eventBus: EventCoordinator?

    init(llmFacade: LLMFacade?, eventBus: EventCoordinator? = nil) {
        self.llmFacade = llmFacade
        self.eventBus = eventBus
    }

    func updateLLMFacade(_ facade: LLMFacade?) {
        self.llmFacade = facade
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
            metadata: metadata
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

    // MARK: - PDF Extraction

    /// Extract content from a PDF using Google's Files API
    /// Handles PDFs up to 2GB natively without chunking
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

        let modelId = currentModelId()
        let sizeMB = Double(sizeInBytes) / 1_048_576.0
        let pageCount = PDFDocument(data: fileData)?.pageCount

        await notifyProgress(.fileAnalysis, .active, detail: "Preparing PDF (\(String(format: "%.1f", sizeMB)) MB)...")

        Logger.info(
            "📄 Starting Google Files API extraction",
            category: .ai,
            metadata: [
                "filename": filename,
                "size_mb": String(format: "%.1f", sizeMB),
                "model": modelId,
                "page_count": pageCount.map(String.init) ?? "unknown"
            ]
        )

        await notifyProgress(.fileAnalysis, .completed, detail: "Using \(modelId)")
        await notifyProgress(.aiExtraction, .active, detail: "Uploading \(filename) to Google...")

        let extractionPrompt = DocumentExtractionPrompts.promptWithDocumentHints(
            filename: filename,
            pageCount: pageCount,
            sizeInBytes: sizeInBytes
        )

        // Keep short docs eligible for verbatim transcription, but prevent runaway outputs on long docs.
        let maxOutputTokens: Int = {
            if let pageCount, pageCount <= 10 { return 32768 }
            if sizeMB <= 2.0 { return 24576 }
            return 16384
        }()

        let llmStart = Date()
        do {
            let (extractedTitle, extractedText, tokenUsage) = try await googleAIService.extractTextFromPDF(
                pdfData: fileData,
                filename: filename,
                modelId: modelId,
                prompt: extractionPrompt,
                maxOutputTokens: maxOutputTokens
            )

            let llmDurationMs = Int(Date().timeIntervalSince(llmStart) * 1000)
            Logger.info(
                "📄 Google Files API extraction completed",
                category: .diagnostics,
                metadata: [
                    "filename": filename,
                    "duration_ms": "\(llmDurationMs)",
                    "chars": "\(extractedText.count)",
                    "page_count": pageCount.map(String.init) ?? "unknown",
                    "max_output_tokens": "\(maxOutputTokens)"
                ]
            )

            // Emit token usage event if available
            if let usage = tokenUsage, let eventBus = eventBus {
                await eventBus.publish(.llmTokenUsageReceived(
                    modelId: modelId,
                    inputTokens: usage.promptTokenCount,
                    outputTokens: usage.candidatesTokenCount,
                    cachedTokens: 0,
                    reasoningTokens: 0,
                    source: .documentExtraction
                ))
            }

            if extractedText.isEmpty {
                await notifyProgress(.aiExtraction, .failed, detail: "No text extracted")
                throw ExtractionError.noTextExtracted
            }

            await notifyProgress(.aiExtraction, .completed)

            var metadata: [String: Any] = [
                "character_count": extractedText.count,
                "source_format": contentType,
                "purpose": purpose,
                "source_file_url": fileURL.absoluteString,
                "source_filename": filename,
                "extraction_method": "google_files_api",
                "max_output_tokens": maxOutputTokens
            ]
            if let pageCount {
                metadata["page_count"] = pageCount
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
                extractedContent: extractedText,
                metadata: metadata
            )

            let quality = Quality(confidence: estimateConfidence(for: extractedText, issues: []), issues: [])

            return ExtractionResult(
                status: .ok,
                artifact: artifact,
                quality: quality,
                derivedApplicantProfile: nil,
                derivedSkeletonTimeline: nil,
                persisted: false
            )
        } catch let error as GoogleAIService.GoogleAIError {
            Logger.error("📄 Google Files API extraction failed: \(error.localizedDescription)", category: .ai)
            await notifyProgress(.aiExtraction, .failed, detail: error.localizedDescription)
            throw ExtractionError.llmFailed(error.localizedDescription)
        } catch {
            Logger.error("📄 PDF extraction failed: \(error.localizedDescription)", category: .ai)
            await notifyProgress(.aiExtraction, .failed, detail: error.localizedDescription)
            throw ExtractionError.llmFailed(error.localizedDescription)
        }
    }
}
