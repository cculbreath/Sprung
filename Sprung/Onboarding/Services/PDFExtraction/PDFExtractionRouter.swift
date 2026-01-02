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

    // MARK: - State

    private var workspace: PDFExtractionWorkspace?
    private var progressCallback: (@Sendable (String) -> Void)?

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
        self.workspace = ws
        self.progressCallback = progress

        // Write input PDF
        try pdfData.write(to: await ws.inputPDFURL)

        do {
            let result = try await performExtraction(
                pdfData: pdfData,
                filename: filename,
                workspace: ws
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

    // MARK: - Progress Reporting

    private func reportProgress(_ message: String) {
        progressCallback?(message)
    }

    // MARK: - Extraction Pipeline

    private func performExtraction(
        pdfData: Data,
        filename: String,
        workspace: PDFExtractionWorkspace
    ) async throws -> PDFExtractionResult {

        // Step 1: Parse PDF
        reportProgress("Analyzing PDF structure...")
        Logger.info("📄 PDFRouter: Starting extraction for \(filename)", category: .ai)

        guard let pdfDocument = PDFDocument(data: pdfData) else {
            throw RouterError.invalidPDF
        }
        let pageCount = pdfDocument.pageCount
        Logger.info("📄 PDFRouter: PDF has \(pageCount) pages", category: .ai)

        // Step 2: Quick PDFKit extraction
        reportProgress("Extracting text layer...")
        let pdfKitText = extractWithPDFKit(pdfDocument)
        let hasNullChars = pdfKitText.contains("\u{0000}")

        if hasNullChars {
            Logger.info("📄 PDFRouter: Null characters detected in text layer", category: .ai)
        }
        Logger.info("📄 PDFRouter: PDFKit extracted \(pdfKitText.count) characters", category: .ai)

        // Step 3: Rasterize samples for judge
        reportProgress("Rasterizing sample pages...")
        let samplePages = await rasterizer.selectSamplePages(pageCount: pageCount)
        Logger.info("📄 PDFRouter: Sampling pages: \(samplePages.map { $0 + 1 })", category: .ai)

        let pageImages = try await rasterizer.rasterizePages(
            pdfDocument: pdfDocument,
            pages: samplePages,
            config: .judge,
            workspace: workspace
        )

        // Step 4: Create 4-up composites
        reportProgress("Creating comparison composites...")
        let composites = try await rasterizer.createFourUpComposites(
            pageImages: pageImages,
            workspace: workspace
        )
        Logger.info("📄 PDFRouter: Created \(composites.count) composite images", category: .ai)

        // Step 5: LLM Judge
        reportProgress("Analyzing extraction quality...")
        Logger.info("📄 PDFRouter: Calling LLM judge to compare text vs images", category: .ai)

        let judgment = try await judge.judge(
            compositeImages: composites,
            pdfKitText: pdfKitText,
            samplePages: samplePages,
            hasNullCharacters: hasNullChars
        )

        Logger.info(
            "📄 PDFRouter: Judgment: fidelity=\(judgment.textFidelity)%, " +
            "layout=\(judgment.layoutComplexity.rawValue), " +
            "recommended=\(judgment.recommendedMethod.rawValue)",
            category: .ai
        )

        if !judgment.issuesFound.isEmpty {
            Logger.info("📄 PDFRouter: Issues: \(judgment.issuesFound.joined(separator: ", "))", category: .ai)
        }

        // Step 6: Route to extractor
        let (text, method) = try await routeExtraction(
            pdfDocument: pdfDocument,
            pageCount: pageCount,
            pdfKitText: pdfKitText,
            judgment: judgment,
            workspace: workspace
        )

        // Step 7: Sanitize
        reportProgress("Extracted via \(method.displayDescription)")
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
        workspace: PDFExtractionWorkspace
    ) async throws -> (String, PDFExtractionMethod) {

        switch judgment.recommendedMethod {

        case .pdfkit:
            reportProgress("Using native text extraction")
            Logger.info("📄 PDFRouter: Route: PDFKit (fidelity \(judgment.textFidelity)% acceptable)", category: .ai)
            return (pdfKitText, .pdfkit)

        case .visionOCR:
            reportProgress("Using native Vision OCR...")
            Logger.info("📄 PDFRouter: Route: Vision OCR (free, native)", category: .ai)

            // Rasterize all pages for OCR
            reportProgress("Rasterizing all \(pageCount) pages...")
            let allPages = try await rasterizer.rasterizePages(
                pdfDocument: pdfDocument,
                pages: Array(0..<pageCount),
                config: .extraction,
                workspace: workspace
            )

            // Run Vision OCR
            reportProgress("Running OCR on \(pageCount) pages...")
            let callback = progressCallback
            let text = try await visionOCR.recognizeImages(allPages) { completed, total in
                callback?("OCR: \(completed)/\(total) pages")
            }

            Logger.info("📄 PDFRouter: Vision OCR extracted \(text.count) characters", category: .ai)
            return (text, .visionOCR)

        case .llmVision:
            Logger.info("📄 PDFRouter: Route: LLM Vision (complex layout/content)", category: .ai)
            return try await extractWithLLMVision(
                pdfDocument: pdfDocument,
                pageCount: pageCount,
                workspace: workspace
            )
        }
    }

    // MARK: - LLM Vision Extraction (Parallel)

    private func extractWithLLMVision(
        pdfDocument: PDFDocument,
        pageCount: Int,
        workspace: PDFExtractionWorkspace
    ) async throws -> (String, PDFExtractionMethod) {

        // Rasterize all pages
        reportProgress("Rasterizing \(pageCount) pages for vision extraction...")
        let allPages = try await rasterizer.rasterizePages(
            pdfDocument: pdfDocument,
            pages: Array(0..<pageCount),
            config: .extraction,
            workspace: workspace
        )

        // Extract in parallel
        let maxConcurrent = UserDefaults.standard.integer(forKey: "maxConcurrentPDFExtractions")
        Logger.info("📄 PDFRouter: Starting parallel vision extraction (max \(max(maxConcurrent, 4)) concurrent)", category: .ai)

        let callback = progressCallback
        let pageTexts = try await parallelExtractor.extractPages(images: allPages) { status in
            callback?(status)
        }

        let combinedText = pageTexts.enumerated().map { index, text in
            "--- Page \(index + 1) ---\n\(text)"
        }.joined(separator: "\n\n")

        Logger.info("📄 PDFRouter: LLM Vision extracted \(combinedText.count) characters from \(pageCount) pages", category: .ai)

        return (combinedText, .llmVision)
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
