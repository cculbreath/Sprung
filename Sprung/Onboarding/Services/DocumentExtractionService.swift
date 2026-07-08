import Foundation
import PDFKit
import UniformTypeIdentifiers
import CryptoKit
import SwiftyJSON

/// Lightweight service that orchestrates document text extraction for storage.
/// - PDFs: PDFKit native text extraction only (may be sparse for scanned
///   documents — acceptable; the Anthropic document-analysis passes see the
///   actual PDF and carry the content via summary/cards/skills)
/// - Text/DOCX: Extracted directly without LLM processing, preserving original content
actor DocumentExtractionService {

    struct ExtractionRequest {
        let fileURL: URL
        let purpose: String
        let returnTypes: [String]
        let autoPersist: Bool
        let timeout: TimeInterval?
        /// Original filename for user-facing messages (storage URL may have UUID prefix)
        let displayFilename: String?

        init(
            fileURL: URL,
            purpose: String,
            returnTypes: [String] = [],
            autoPersist: Bool = false,
            timeout: TimeInterval? = nil,
            displayFilename: String? = nil
        ) {
            self.fileURL = fileURL
            self.purpose = purpose
            self.returnTypes = returnTypes
            self.autoPersist = autoPersist
            self.timeout = timeout
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
        let extractedContent: String      // Native text extraction (PDFKit for PDFs)
        let metadata: [String: Any]
    }

    struct ExtractionResult {
        enum Status: String {
            case ok
            case partial
            case failed
        }
        let status: Status
        let artifact: ExtractedArtifact?
    }

    enum ExtractionError: Error {
        case unsupportedType(String)
        case unreadableData
        case noTextExtracted
        case encryptedPDF(String)

        var userFacingMessage: String {
            switch self {
            case .unsupportedType:
                return "Unsupported document format. Please upload a PDF, DOCX, or plain text file."
            case .unreadableData:
                return "The document could not be read. Please try another file."
            case .noTextExtracted:
                return "The document did not contain extractable text."
            case .encryptedPDF(let filename):
                return "\(filename) is password-protected. Remove the password and upload it again."
            }
        }
    }

    init() {}

    // MARK: - Public API

    func extract(using request: ExtractionRequest, progress: ExtractionProgressHandler? = nil) async throws -> ExtractionResult {
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
                "sizeBytes": "\(sizeInBytes)",
                "purpose": request.purpose
            ]
        )

        @Sendable func notifyProgress(_ stage: ExtractionProgressStage, _ state: ExtractionProgressStageState, detail: String? = nil) async {
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
        let isPDF = fileURL.pathExtension.lowercased() == "pdf"

        // PDFs: stored text comes from PDFKit native extraction only. Reject
        // encrypted PDFs here so the failure is a clear, user-facing error.
        if isPDF {
            guard let document = PDFDocument(data: fileData) else {
                await notifyProgress(.fileAnalysis, .failed, detail: "Unreadable PDF")
                throw ExtractionError.unreadableData
            }
            if document.isEncrypted {
                await notifyProgress(.fileAnalysis, .failed, detail: "Password-protected PDF")
                throw ExtractionError.encryptedPDF(filename)
            }
        }

        let (rawText, initialIssues, pageCount) = extractPlainText(from: fileURL)

        // Non-PDF documents must contain extractable text. Scanned PDFs may have
        // an empty text layer — acceptable, because the Anthropic analysis passes
        // see the actual PDF.
        let extractedText: String
        if let rawText, !rawText.isEmpty {
            extractedText = rawText
        } else if isPDF {
            extractedText = ""
            Logger.info("📄 PDF has no extractable text layer (likely scanned): \(filename)", category: .ai)
        } else {
            await notifyProgress(.fileAnalysis, .failed, detail: "No extractable text")
            throw ExtractionError.noTextExtracted
        }

        await notifyProgress(.fileAnalysis, .completed)
        await notifyProgress(.aiExtraction, .completed, detail: "Text extracted directly")

        // Derive title from filename (remove extension)
        let derivedTitle = filename
            .replacingOccurrences(of: ".\(fileURL.pathExtension)", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        var metadata: [String: Any] = [
            "character_count": extractedText.count,
            "source_format": contentType,
            "purpose": request.purpose,
            "source_file_url": fileURL.absoluteString,
            "source_filename": filename,
            "extraction_method": isPDF ? "pdfkit" : "direct_text"
        ]
        if let pageCount {
            metadata["page_count"] = pageCount
        }

        let artifact = ExtractedArtifact(
            id: UUID().uuidString,
            filename: filename,
            title: derivedTitle,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
            sha256: sha256,
            extractedContent: extractedText,
            metadata: metadata
        )

        let status: ExtractionResult.Status = initialIssues.contains("textExtractionWarning") ? .partial : .ok

        let totalMs = Int(Date().timeIntervalSince(extractionStart) * 1000)
        Logger.info(
            "📄 Text extraction finished",
            category: .diagnostics,
            metadata: [
                "filename": filename,
                "duration_ms": "\(totalMs)",
                "chars": "\(extractedText.count)"
            ]
        )

        return ExtractionResult(
            status: status,
            artifact: artifact
        )
    }

    // MARK: - Helpers

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
                return (nil, ["textExtractionWarning"], nil)
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
                return (nil, ["textExtractionWarning"], pageCount)
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
                    return (nil, ["textExtractionWarning"], nil)
                }
                return (text, issues, nil)
            } else {
                issues.append("textExtractionWarning")
                if let plain = try? String(contentsOf: url, encoding: .utf8) {
                    return (plain, issues, nil)
                }
                return (nil, issues, nil)
            }
        }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return (text, issues, nil)
        }

        return (nil, ["textExtractionWarning"], nil)
    }

    private func estimateConfidence(for text: String, issues: [String]) -> Double {
        var confidence = min(0.95, Double(text.count) / 10_000.0 + 0.4)
        if issues.contains("textExtractionWarning") {
            confidence = min(confidence, 0.5)
        }
        return max(0.1, min(confidence, 0.95))
    }

    private func sha256Hex(for data: Data) -> String {
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
