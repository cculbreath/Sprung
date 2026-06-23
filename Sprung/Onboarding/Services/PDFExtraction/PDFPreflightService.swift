//
//  PDFPreflightService.swift
//  Sprung
//
//  PDFKit-based preflight for Anthropic document analysis.
//  Rejects encrypted PDFs and splits documents into page-range chunks that
//  satisfy the Anthropic Messages API document limits (page count, raw size)
//  and a verified input-token budget.
//

import Foundation
import PDFKit
import SwiftOpenAI

/// A page-range slice of a PDF prepared for Anthropic document analysis.
struct PDFChunk: Sendable {
    /// Raw PDF bytes for this chunk (the original data when the document fits in one chunk).
    let data: Data
    /// 1-based inclusive page range within the original document.
    let pageRange: ClosedRange<Int>
    /// 0-based chunk index.
    let index: Int
}

enum PDFPreflightError: LocalizedError {
    case encryptedPDF(filename: String)
    case unreadablePDF(filename: String)
    case emptyPDF(filename: String)
    case chunkingFailed(filename: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .encryptedPDF(let filename):
            return "\(filename) is password-protected. Remove the password and upload it again."
        case .unreadablePDF(let filename):
            return "\(filename) could not be read as a PDF. The file may be corrupted."
        case .emptyPDF(let filename):
            return "\(filename) contains no pages."
        case .chunkingFailed(let filename, let detail):
            return "Could not prepare \(filename) for analysis: \(detail)"
        }
    }
}

/// Splits PDFs into small page-range chunks (default `targetPagesPerChunk`) so each
/// chunk's transcription stays well under the model's output ceiling and the chunks
/// can be transcribed in parallel. A document at or under the target passes through
/// as a single chunk; a token-budget verification still backstops every chunk.
actor PDFPreflightService {

    /// Target pages per transcription chunk. Small chunks bound each transcription's
    /// OUTPUT size — a 100-page chunk overflowed the 32K-token ceiling and truncated
    /// mid-JSON, and a whole-document chunk timed out — and let chunks transcribe
    /// concurrently. Well under Anthropic's hard limit of 100 pages per document block.
    static let targetPagesPerChunk = 10

    /// Anthropic Messages API limit: at most 20 MB of raw PDF data per document block.
    static let maxChunkBytes = 20 * 1024 * 1024

    /// Maximum input tokens allowed for a chunk's document block, verified via the
    /// token-counting endpoint before any analysis pass runs.
    ///
    /// 180K is a conservative floor for 200K-context models: the Models API does not
    /// expose context windows, so we assume the smallest current window (200K) and
    /// reserve ~20K tokens of headroom for system prompt, per-pass instructions, and
    /// extracted-card context in the enrichment pass.
    static let inputTokenBudget = 180_000

    private let llmFacade: LLMFacade

    init(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }

    /// Validate a PDF and split it into chunks that each satisfy the page, size,
    /// and token limits. Throws a user-facing error for encrypted or unreadable PDFs.
    func makeChunks(pdfData: Data, filename: String, modelId: String) async throws -> [PDFChunk] {
        guard let document = PDFDocument(data: pdfData) else {
            throw PDFPreflightError.unreadablePDF(filename: filename)
        }
        if document.isEncrypted {
            throw PDFPreflightError.encryptedPDF(filename: filename)
        }
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw PDFPreflightError.emptyPDF(filename: filename)
        }

        var chunks: [PDFChunk] = []
        var startPage = 0 // 0-based

        while startPage < pageCount {
            var span = min(Self.targetPagesPerChunk, pageCount - startPage)

            while true {
                let candidateData: Data
                if startPage == 0 && span == pageCount {
                    // Whole document fits in one candidate — use the original bytes.
                    candidateData = pdfData
                } else {
                    candidateData = try subdocumentData(
                        of: document,
                        startPage: startPage,
                        pageSpan: span,
                        filename: filename
                    )
                }

                if candidateData.count > Self.maxChunkBytes {
                    span = try halve(span, filename: filename, reason: "exceeds \(Self.maxChunkBytes / 1_048_576) MB")
                    continue
                }

                let tokens = try await countDocumentTokens(candidateData, modelId: modelId)
                if tokens > Self.inputTokenBudget {
                    span = try halve(span, filename: filename, reason: "exceeds the \(Self.inputTokenBudget)-token budget (\(tokens) tokens)")
                    continue
                }

                let chunk = PDFChunk(
                    data: candidateData,
                    pageRange: (startPage + 1)...(startPage + span),
                    index: chunks.count
                )
                chunks.append(chunk)
                Logger.info(
                    "📄 PDF chunk \(chunk.index + 1) ready: pages \(chunk.pageRange.lowerBound)–\(chunk.pageRange.upperBound), \(candidateData.count) bytes, \(tokens) tokens",
                    category: .ai
                )
                startPage += span
                break
            }
        }

        return chunks
    }

    // MARK: - Helpers

    private func halve(_ span: Int, filename: String, reason: String) throws -> Int {
        guard span > 1 else {
            throw PDFPreflightError.chunkingFailed(
                filename: filename,
                detail: "a single page \(reason)"
            )
        }
        return span / 2
    }

    /// Build a sub-PDF containing `pageSpan` pages starting at `startPage` (0-based).
    private func subdocumentData(
        of document: PDFDocument,
        startPage: Int,
        pageSpan: Int,
        filename: String
    ) throws -> Data {
        let subdocument = PDFDocument()
        for offset in 0..<pageSpan {
            guard let page = document.page(at: startPage + offset),
                  let pageCopy = page.copy() as? PDFPage else {
                throw PDFPreflightError.chunkingFailed(
                    filename: filename,
                    detail: "failed to copy page \(startPage + offset + 1)"
                )
            }
            subdocument.insert(pageCopy, at: offset)
        }
        guard let data = subdocument.dataRepresentation() else {
            throw PDFPreflightError.chunkingFailed(
                filename: filename,
                detail: "failed to serialize pages \(startPage + 1)–\(startPage + pageSpan)"
            )
        }
        return data
    }

    /// Count input tokens for a request containing just the chunk's document block.
    private func countDocumentTokens(_ data: Data, modelId: String) async throws -> Int {
        let documentBlock = AnthropicContentBlock.document(
            AnthropicDocumentBlock(
                source: .base64(mediaType: "application/pdf", data: data.base64EncodedString())
            )
        )
        let parameters = AnthropicTokenCountParameter(
            model: modelId,
            messages: [AnthropicMessage(role: "user", content: .blocks([documentBlock]))]
        )
        let response = try await llmFacade.anthropicCountTokens(parameters: parameters)
        return response.inputTokens
    }
}
