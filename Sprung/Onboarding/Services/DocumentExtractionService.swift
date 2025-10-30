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
    struct ExtractionRequest {
        let fileURL: URL
        let purpose: String
        let returnTypes: [String]
        let autoPersist: Bool
        let timeout: TimeInterval?
    }

    struct ArtifactRecord {
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
        let artifact: ArtifactRecord?
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
            }
        }
    }

    // MARK: - Private Properties

    private let requestExecutor: LLMRequestExecutor
    private let maxCharactersForPrompt = 18_000
    private let defaultModelId = "google/gemini-2.0-flash"

    init(requestExecutor: LLMRequestExecutor) {
        self.requestExecutor = requestExecutor
    }

    // MARK: - Public API

    func extract(using request: ExtractionRequest) async throws -> ExtractionResult {
        try await ensureExecutorConfigured()

        let fileURL = request.fileURL
        let filename = fileURL.lastPathComponent
        let sizeInBytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        let contentType = contentTypeForFile(at: fileURL) ?? "application/octet-stream"

        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw ExtractionError.unreadableData
        }

        let sha256 = sha256Hex(for: fileData)
        let (rawText, initialIssues) = extractPlainText(from: fileURL)
        guard let rawText, !rawText.isEmpty else {
            throw ExtractionError.noTextExtracted
        }

        let (markdown, markdownIssues) = await enrichText(rawText, purpose: request.purpose, timeout: request.timeout)
        let enrichedContent = markdown ?? rawText

        var issues = initialIssues
        issues.append(contentsOf: markdownIssues)

        let confidence = estimateConfidence(for: enrichedContent, issues: issues)

        var metadata: [String: Any] = [
            "character_count": enrichedContent.count,
            "source_format": contentType,
            "purpose": request.purpose
        ]
        if initialIssues.contains("truncated_input") {
            metadata["truncated_input"] = true
        }

        let artifact = ArtifactRecord(
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

    private func ensureExecutorConfigured() async throws {
        if !(await requestExecutor.isConfigured()) {
            await requestExecutor.configureClient()
        }
        guard await requestExecutor.isConfigured() else {
            throw ExtractionError.llmFailed("PDF extraction model is not configured. Add an OpenRouter API key in Settings.")
        }
    }

    private func currentModelId() -> String {
        UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId") ?? defaultModelId
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
                if let plain = try? String(contentsOf: url) {
                    return (plain, issues)
                }
                return (nil, issues)
            }
        }

        if let text = try? String(contentsOf: url) {
            return (text, issues)
        }

        return (nil, ["text_extraction_warning"])
    }

    private func enrichText(_ rawText: String, purpose: String, timeout: TimeInterval?) async -> (String?, [String]) {
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
}
