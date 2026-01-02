//
//  PDFExtractionRouter.swift
//  Sprung
//
//  Routes PDF extraction to optimal method based on LLM judgment.
//  Status updates are reported via progress callback to the caller.
//

import Foundation
import PDFKit

/// Result of PDF extraction
struct PDFExtractionResult {
    let text: String
    let method: PDFExtractionMethod
    let judgment: ExtractionJudgment
    let pageCount: Int
}

/// Routes PDF extraction to optimal method based on LLM judgment.
actor PDFExtractionRouter {

    // MARK: - Dependencies

    private let rasterizer: PDFRasterizer
    private let judge: PDFExtractionJudge
    private let visionOCR: VisionOCRService
    private let parallelExtractor: ParallelPageExtractor
    private let llmFacade: LLMFacade

    // MARK: - Init

    init(llmFacade: LLMFacade, agentTracker: AgentActivityTracker?) {
        self.llmFacade = llmFacade
        // agentTracker is no longer used - status updates go through progress callback
        self.rasterizer = PDFRasterizer()
        self.judge = PDFExtractionJudge(llmFacade: llmFacade)
        self.visionOCR = VisionOCRService()
        self.parallelExtractor = ParallelPageExtractor(llmFacade: llmFacade)
    }

    // MARK: - Main Entry Point

    /// Extract text from PDF using optimal method
    /// - Parameters:
    ///   - pdfData: The PDF file data
    ///   - filename: Display name for status updates
    ///   - progress: Optional callback for status updates
    func extractText(
        from pdfData: Data,
        filename: String,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> PDFExtractionResult {

        // Create workspace for temp files
        let ws = try PDFExtractionWorkspace(documentName: filename)

        // Write input PDF
        try pdfData.write(to: await ws.inputPDFURL)

        do {
            let result = try await performExtraction(
                pdfData: pdfData,
                filename: filename,
                workspace: ws,
                progress: progress
            )

            // Save output for debugging
            try? await ws.saveOutput(result.text)

            // Cleanup workspace on success
            await ws.cleanup()

            return result

        } catch {
            throw error
        }
    }

    // MARK: - Extraction Pipeline

    private func performExtraction(
        pdfData: Data,
        filename: String,
        workspace: PDFExtractionWorkspace,
        progress: (@Sendable (String) -> Void)?
    ) async throws -> PDFExtractionResult {

        // Step 1: Parse PDF
        progress?("Analyzing PDF structure...")
        Logger.info("📄 PDFRouter: Starting extraction for \(filename)", category: .ai)

        guard let pdfDocument = PDFDocument(data: pdfData) else {
            throw RouterError.invalidPDF
        }
        let pageCount = pdfDocument.pageCount
        Logger.info("📄 PDFRouter: PDF has \(pageCount) pages", category: .ai)

        // Step 2: Quick PDFKit extraction
        progress?("Extracting text layer...")
        let pdfKitText = extractWithPDFKit(pdfDocument)
        let hasNullChars = pdfKitText.contains("\u{0000}")

        if hasNullChars {
            Logger.info("📄 PDFRouter: Null characters detected in text layer", category: .ai)
        }
        Logger.info("📄 PDFRouter: PDFKit extracted \(pdfKitText.count) characters", category: .ai)

        // Step 3: Rasterize sample pages for judge (~5% of pages, min 3, max 10)
        let judgeConfig = RasterConfig.judge
        progress?("Rasterizing sample pages...")
        let samplePages = await rasterizer.selectSamplePages(pageCount: pageCount)
        Logger.info("📄 PDFRouter: Sampling \(samplePages.count) pages (~5%): \(samplePages.map { $0 + 1 })", category: .ai)

        let pageImages = try await rasterizer.rasterizePages(
            pdfDocument: pdfDocument,
            pages: samplePages,
            config: judgeConfig,
            workspace: workspace
        )

        // Step 4: Optionally create 4-up composites based on settings
        let judgeImages: [URL]
        if judgeConfig.compositeMode == .fourUp {
            progress?("Creating comparison composites...")
            judgeImages = try await rasterizer.createFourUpComposites(
                pageImages: pageImages,
                workspace: workspace
            )
            Logger.info("📄 PDFRouter: Created \(judgeImages.count) composite images (4-up)", category: .ai)
        } else {
            judgeImages = pageImages
            Logger.info("📄 PDFRouter: Using \(judgeImages.count) individual page images", category: .ai)
        }

        // Step 5: LLM Judge
        progress?("Analyzing extraction quality...")
        let isComposite = judgeConfig.compositeMode == .fourUp
        Logger.info("📄 PDFRouter: Sending \(judgeImages.count) images to judge (\(judgeConfig.dpi) DPI, composite=\(isComposite))", category: .ai)

        let judgment = try await judge.judge(
            pageImages: judgeImages,
            pdfKitText: pdfKitText,
            samplePages: samplePages,
            hasNullCharacters: hasNullChars,
            isComposite: isComposite
        )

        Logger.info(
            "📄 PDFRouter: Judgment: decision=\(judgment.decision.rawValue), reasoning=\(judgment.reasoning.prefix(100))...",
            category: .ai
        )

        // Step 6: Route to extractor
        let (text, method) = try await routeExtraction(
            pdfDocument: pdfDocument,
            pageCount: pageCount,
            pdfKitText: pdfKitText,
            judgment: judgment,
            workspace: workspace,
            progress: progress
        )

        // Step 7: Sanitize
        progress?("Extracted via \(method.displayDescription)")
        let sanitizedText = sanitize(text)

        Logger.info(
            "📄 PDFRouter: Extraction complete: \(sanitizedText.count) characters via \(method.displayDescription)",
            category: .ai
        )

        return PDFExtractionResult(
            text: sanitizedText,
            method: method,
            judgment: judgment,
            pageCount: pageCount
        )
    }

    // MARK: - Routing

    private func routeExtraction(
        pdfDocument: PDFDocument,
        pageCount: Int,
        pdfKitText: String,
        judgment: ExtractionJudgment,
        workspace: PDFExtractionWorkspace,
        progress: (@Sendable (String) -> Void)?
    ) async throws -> (String, PDFExtractionMethod) {

        switch judgment.recommendedMethod {

        case .pdfkit:
            progress?("Using native text extraction")
            Logger.info("📄 PDFRouter: Route: PDFKit (extraction quality acceptable)", category: .ai)
            return (pdfKitText, .pdfkit)

        case .visionOCR:
            progress?("Using native Vision OCR...")
            Logger.info("📄 PDFRouter: Route: Vision OCR (free, native)", category: .ai)

            // Rasterize all pages for OCR
            progress?("Rasterizing all \(pageCount) pages...")
            let allPages = try await rasterizer.rasterizePages(
                pdfDocument: pdfDocument,
                pages: Array(0..<pageCount),
                config: .extraction,
                workspace: workspace
            )

            // Run Vision OCR
            progress?("Running OCR on \(pageCount) pages...")
            let text = try await visionOCR.recognizeImages(allPages) { completed, total in
                progress?("OCR: \(completed)/\(total) pages")
            }

            Logger.info("📄 PDFRouter: Vision OCR extracted \(text.count) characters", category: .ai)
            return (text, .visionOCR)

        case .llmVision:
            Logger.info("📄 PDFRouter: Route: LLM Vision (complex layout/content)", category: .ai)
            return try await extractWithLLMVision(
                pdfDocument: pdfDocument,
                pageCount: pageCount,
                workspace: workspace,
                progress: progress
            )
        }
    }

    // MARK: - LLM Vision Extraction (Parallel)

    private func extractWithLLMVision(
        pdfDocument: PDFDocument,
        pageCount: Int,
        workspace: PDFExtractionWorkspace,
        progress: (@Sendable (String) -> Void)?
    ) async throws -> (String, PDFExtractionMethod) {

        // Rasterize all pages
        progress?("Rasterizing \(pageCount) pages for vision extraction...")
        let allPages = try await rasterizer.rasterizePages(
            pdfDocument: pdfDocument,
            pages: Array(0..<pageCount),
            config: .extraction,
            workspace: workspace
        )

        // Extract in parallel
        let maxConcurrent = UserDefaults.standard.integer(forKey: "maxConcurrentPDFExtractions")
        Logger.info("📄 PDFRouter: Starting parallel vision extraction (max \(max(maxConcurrent, 4)) concurrent)", category: .ai)

        let pageResults = try await parallelExtractor.extractPages(images: allPages) { status in
            progress?(status)
        }

        // Combine text and graphics content
        let combinedText = formatExtractionResults(pageResults)

        // Log graphics summary
        let totalGraphics = pageResults.reduce(0) { $0 + $1.graphics.numberOfGraphics }
        Logger.info("📄 PDFRouter: LLM Vision extracted \(combinedText.count) characters, \(totalGraphics) graphics from \(pageCount) pages", category: .ai)

        return (combinedText, .llmVision)
    }

    /// Format page extraction results into combined text with graphics descriptions
    private func formatExtractionResults(_ results: [PageExtractionResult]) -> String {
        var output: [String] = []

        for (index, result) in results.enumerated() {
            var pageContent = "--- Page \(index + 1) ---\n\(result.text)"

            // Append graphics descriptions with skills assessment if present
            if result.graphics.numberOfGraphics > 0 {
                pageContent += "\n\n[Graphics on this page: \(result.graphics.numberOfGraphics)]"

                for (i, content) in result.graphics.graphicsContent.enumerated() {
                    let skills = i < result.graphics.qualitativeAssessment.count
                        ? result.graphics.qualitativeAssessment[i]
                        : "skills assessment unavailable"
                    pageContent += "\n• Figure \(i + 1): \(content)"
                    pageContent += "\n  Skills demonstrated: \(skills)"
                }
            }

            output.append(pageContent)
        }

        return output.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    private func extractWithPDFKit(_ document: PDFDocument) -> String {
        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i),
               let pageText = page.string {
                text += pageText + "\n\n"
            }
        }
        return text
    }

    private func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .precomposedStringWithCanonicalMapping
    }

    // MARK: - Error Types

    enum RouterError: Error, LocalizedError {
        case invalidPDF

        var errorDescription: String? {
            switch self {
            case .invalidPDF: return "Could not parse PDF document"
            }
        }
    }
}
