import Foundation
import PDFKit
import UniformTypeIdentifiers
import CryptoKit
import SwiftOpenAI
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
    }
    struct ExtractedArtifact {
        let id: String
        let filename: String
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
            }
        }
    }

    /// Maximum pages for image-based PDF extraction
    private let maxPagesForImageExtraction = 10
    // MARK: - Private Properties
    private let requestExecutor: LLMRequestExecutor
    private let maxCharactersForPrompt = 18_000
    private let defaultModelId = "google/gemini-2.0-flash-001"
    private var availableModelIds: [String] = []
    init(requestExecutor: LLMRequestExecutor) {
        self.requestExecutor = requestExecutor
    }
    func updateAvailableModels(_ ids: [String]) {
        availableModelIds = ids
    }
    func setInvalidModelHandler(_ handler: @escaping (String) -> Void) {
        onInvalidModelId = handler
    }
    // MARK: - Public API
    func extract(using request: ExtractionRequest, progress: ExtractionProgressHandler? = nil) async throws -> ExtractionResult {
        try await ensureExecutorConfigured()
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
        let (rawText, initialIssues) = extractPlainText(from: fileURL)

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
        let llmStart = Date()
        let aiStageDetail = request.purpose == "resume_timeline"
            ? "Extracting resume details with Gemini AI..."
            : "Processing document with Gemini AI..."
        await notifyProgress(.aiExtraction, .active, detail: aiStageDetail)
        let (markdown, markdownIssues) = try await enrichText(rawText, purpose: request.purpose, timeout: request.timeout)
        let llmDurationMs = Int(Date().timeIntervalSince(llmStart) * 1000)
        Logger.info(
            "📄 Extraction LLM phase completed",
            category: .diagnostics,
            metadata: [
                "filename": filename,
                "duration_ms": "\(llmDurationMs)"
            ]
        )
        let enrichedContent = markdown ?? rawText
        let aiDetail: String? = {
            if let failure = markdownIssues.first(where: { $0.hasPrefix("llm_failure") }) {
                return failure.replacingOccurrences(of: "llm_failure_", with: "")
            }
            if markdown == nil {
                return "Using original text"
            }
            return nil
        }()
        let aiState: ExtractionProgressStageState = markdownIssues.contains(where: { $0.hasPrefix("llm_failure") }) ? .failed : .completed
        await notifyProgress(.aiExtraction, aiState, detail: aiDetail)
        var issues = initialIssues
        issues.append(contentsOf: markdownIssues)
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
        let artifact = ExtractedArtifact(
            id: UUID().uuidString,
            filename: filename,
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
    private func ensureExecutorConfigured() async throws {
        if !(await requestExecutor.isConfigured()) {
            await requestExecutor.configureClient()
        }
        guard await requestExecutor.isConfigured() else {
            throw ExtractionError.llmFailed("PDF extraction model is not configured. Add an OpenRouter API key in Settings.")
        }
    }
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
    private func extractPlainText(from url: URL) -> (String?, [String]) {
        var issues: [String] = []
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else {
                return (nil, ["text_extraction_warning"])
            }
            var text = ""
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                if let pageText = page.string {
                    text.append(pageText)
                    text.append("\n\n")
                }
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (nil, ["text_extraction_warning"])
            }
            return (text, issues)
        }
        if ext == "docx" {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.officeOpenXML
            ]
            if let attributed = try? NSAttributedString(url: url, options: options, documentAttributes: nil) {
                let text = attributed.string
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (nil, ["text_extraction_warning"])
                }
                return (text, issues)
            } else {
                issues.append("text_extraction_warning")
                if let plain = try? String(contentsOf: url, encoding: .utf8) {
                    return (plain, issues)
                }
                return (nil, issues)
            }
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return (text, issues)
        }
        return (nil, ["text_extraction_warning"])
    }
    private func enrichText(_ rawText: String, purpose: String, timeout: TimeInterval?) async throws -> (String?, [String]) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (nil, ["llm_failure_empty_input"])
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
        prompt += "\nPlain text input begins:\n```\n\(input)\n```\n\nReturn only the formatted Markdown content."
        let parameters = ChatCompletionParameters(
            messages: [
                .text(role: .system, content: "You are a meticulous document extraction assistant that produces Markdown outputs."),
                .text(role: .user, content: prompt)
            ],
            model: .custom(modelId),
            temperature: 0.1
        )
        let response: LLMResponse
        do {
            response = try await requestExecutor.execute(parameters: parameters)
        } catch let llmError as LLMError {
            if case .invalidModelId(let modelId) = llmError {
                onInvalidModelId?(modelId)
                throw ExtractionError.llmFailed("\(modelId) is not a valid model ID.")
            }
            issues.append("llm_failure_\(llmError.localizedDescription)")
            return (nil, issues)
        } catch {
            issues.append("llm_failure_\(error.localizedDescription)")
            return (nil, issues)
        }
        let dto = LLMVendorMapper.responseDTO(from: response)
        guard let text = dto.choices.first?.message?.text, !text.isEmpty else {
            issues.append("llm_failure_empty_response")
            return (nil, issues)
        }
        return (text, issues)
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

        // Convert pages to images
        guard let base64Images = ImageConversionService.shared.convertPDFPagesToBase64Images(pdfData: fileData, maxPages: maxPagesForImageExtraction),
              !base64Images.isEmpty else {
            await notifyProgress(.fileAnalysis, .failed, detail: "Failed to convert PDF pages to images")
            throw ExtractionError.noTextExtracted
        }

        await notifyProgress(.fileAnalysis, .completed, detail: "Converted \(base64Images.count) page(s)")

        // Use vision-capable model to extract content
        let aiStageDetail = "Analyzing \(base64Images.count) page image(s) with AI..."
        await notifyProgress(.aiExtraction, .active, detail: aiStageDetail)

        let llmStart = Date()
        let (extractedText, issues) = try await extractTextFromImages(base64Images, purpose: purpose)

        let llmDurationMs = Int(Date().timeIntervalSince(llmStart) * 1000)
        Logger.info(
            "📄 Image-based extraction LLM phase completed",
            category: .diagnostics,
            metadata: [
                "filename": filename,
                "page_count": "\(base64Images.count)",
                "duration_ms": "\(llmDurationMs)"
            ]
        )

        let aiState: ExtractionProgressStageState = issues.contains(where: { $0.hasPrefix("llm_failure") }) ? .failed : .completed
        await notifyProgress(.aiExtraction, aiState)

        var allIssues = ["image_based_extraction"]
        allIssues.append(contentsOf: issues)

        let confidence = estimateConfidence(for: extractedText, issues: allIssues)
        let metadata: [String: Any] = [
            "character_count": extractedText.count,
            "source_format": contentType,
            "purpose": purpose,
            "source_file_url": fileURL.absoluteString,
            "source_filename": filename,
            "extraction_method": "image_vision",
            "page_count": pageCount
        ]

        let artifact = ExtractedArtifact(
            id: UUID().uuidString,
            filename: filename,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            sha256: sha256,
            extractedContent: extractedText,
            metadata: metadata
        )

        let status: ExtractionResult.Status
        if issues.contains(where: { $0.hasPrefix("llm_failure") }) {
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

    /// Extract text from base64-encoded images using a vision-capable LLM
    private func extractTextFromImages(_ base64Images: [String], purpose: String) async throws -> (String, [String]) {
        typealias MessageContent = ChatCompletionParameters.Message.ContentType.MessageContent

        var issues: [String] = []
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
        prompt += "\n\nExtract the complete content from all page images and return only the formatted Markdown."

        // Build message content with images
        var contentParts: [MessageContent] = []
        contentParts.append(.text(prompt))

        for (index, base64Image) in base64Images.enumerated() {
            let dataURLString = "data:image/png;base64,\(base64Image)"
            guard let imageURL = URL(string: dataURLString) else {
                Logger.warning("⚠️ Failed to create URL for page \(index + 1)", category: .ai)
                continue
            }
            contentParts.append(.imageUrl(MessageContent.ImageDetail(url: imageURL, detail: "high")))
            if base64Images.count > 1 {
                contentParts.append(.text("(Page \(index + 1) of \(base64Images.count))"))
            }
        }

        // Create user message with content array
        let userMessage = ChatCompletionParameters.Message(
            role: .user,
            content: .contentArray(contentParts)
        )

        let parameters = ChatCompletionParameters(
            messages: [
                .text(role: .system, content: "You are a meticulous document extraction assistant that produces Markdown outputs from images."),
                userMessage
            ],
            model: .custom(modelId),
            temperature: 0.1
        )

        let response: LLMResponse
        do {
            response = try await requestExecutor.execute(parameters: parameters)
        } catch let llmError as LLMError {
            if case .invalidModelId(let modelId) = llmError {
                onInvalidModelId?(modelId)
                throw ExtractionError.llmFailed("\(modelId) is not a valid model ID.")
            }
            issues.append("llm_failure_\(llmError.localizedDescription)")
            return ("", issues)
        } catch {
            issues.append("llm_failure_\(error.localizedDescription)")
            return ("", issues)
        }

        let dto = LLMVendorMapper.responseDTO(from: response)
        guard let text = dto.choices.first?.message?.text, !text.isEmpty else {
            issues.append("llm_failure_empty_response")
            return ("", issues)
        }

        return (text, issues)
    }
}
