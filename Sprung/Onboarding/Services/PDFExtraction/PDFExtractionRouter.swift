//
//  PDFExtractionRouter.swift
//  Sprung
//
//  Routes PDF extraction to optimal method based on LLM judgment.
//  Integrates with AgentActivityTracker for status display.
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
    private weak var agentTracker: AgentActivityTracker?

    // MARK: - State

    private var currentAgentId: String?
    private var workspace: PDFExtractionWorkspace?

    // MARK: - Init

    init(llmFacade: LLMFacade, agentTracker: AgentActivityTracker?) {
        self.llmFacade = llmFacade
        self.agentTracker = agentTracker
        self.rasterizer = PDFRasterizer()
        self.judge = PDFExtractionJudge(llmFacade: llmFacade)
        self.visionOCR = VisionOCRService()
        self.parallelExtractor = ParallelPageExtractor(llmFacade: llmFacade)
    }

    // MARK: - Main Entry Point

    /// Extract text from PDF using optimal method with full status tracking
    func extractText(
        from pdfData: Data,
        filename: String
    ) async throws -> PDFExtractionResult {

        // Create workspace for temp files
        let ws = try PDFExtractionWorkspace(documentName: filename)
        self.workspace = ws

        // Write input PDF
        try pdfData.write(to: await ws.inputPDFURL)

        // Register as tracked agent
        let agentId = UUID().uuidString
        self.currentAgentId = agentId

        await registerAgent(id: agentId, name: "PDF: \(filename)")

        do {
            let result = try await performExtraction(
                pdfData: pdfData,
                filename: filename,
                workspace: ws,
                agentId: agentId
            )

            // Save output for debugging
            try? await ws.saveOutput(result.text)

            // Cleanup workspace on success
            await ws.cleanup()

            await completeAgent(id: agentId)

            return result

        } catch {
            await failAgent(id: agentId, error: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Extraction Pipeline

    private func performExtraction(
        pdfData: Data,
        filename: String,
        workspace: PDFExtractionWorkspace,
        agentId: String
    ) async throws -> PDFExtractionResult {

        // Step 1: Parse PDF
        await updateStatus(agentId, "Analyzing PDF structure...")
        await logTranscript(agentId, .system, "Starting extraction for \(filename)")

        guard let pdfDocument = PDFDocument(data: pdfData) else {
            throw RouterError.invalidPDF
        }
        let pageCount = pdfDocument.pageCount
        await logTranscript(agentId, .system, "PDF has \(pageCount) pages")

        // Step 2: Quick PDFKit extraction
        await updateStatus(agentId, "Extracting text layer...")
        let pdfKitText = extractWithPDFKit(pdfDocument)
        let hasNullChars = pdfKitText.contains("\u{0000}")

        if hasNullChars {
            await logTranscript(agentId, .system, "⚠️ Null characters detected in text layer")
        }
        await logTranscript(agentId, .system, "PDFKit extracted \(pdfKitText.count) characters")

        // Step 3: Rasterize samples for judge
        await updateStatus(agentId, "Rasterizing sample pages...")
        let samplePages = await rasterizer.selectSamplePages(pageCount: pageCount)
        await logTranscript(agentId, .system, "Sampling pages: \(samplePages.map { $0 + 1 })")

        let pageImages = try await rasterizer.rasterizePages(
            pdfDocument: pdfDocument,
            pages: samplePages,
            config: .judge,
            workspace: workspace
        )

        // Step 4: Create 4-up composites
        await updateStatus(agentId, "Creating comparison composites...")
        let composites = try await rasterizer.createFourUpComposites(
            pageImages: pageImages,
            workspace: workspace
        )
        await logTranscript(agentId, .system, "Created \(composites.count) composite images (16 pages sampled)")

        // Step 5: LLM Judge
        await updateStatus(agentId, "Analyzing extraction quality...")
        await logTranscript(agentId, .tool, "Calling LLM judge to compare text vs images")

        let judgment = try await judge.judge(
            compositeImages: composites,
            pdfKitText: pdfKitText,
            samplePages: samplePages,
            hasNullCharacters: hasNullChars
        )

        await logTranscript(
            agentId, .assistant,
            "Judgment: fidelity=\(judgment.textFidelity)%, " +
            "layout=\(judgment.layoutComplexity.rawValue), " +
            "recommended=\(judgment.recommendedMethod.rawValue)"
        )

        if !judgment.issuesFound.isEmpty {
            await logTranscript(agentId, .system, "Issues: \(judgment.issuesFound.joined(separator: ", "))")
        }

        // Step 6: Route to extractor
        let (text, method) = try await routeExtraction(
            pdfDocument: pdfDocument,
            pageCount: pageCount,
            pdfKitText: pdfKitText,
            judgment: judgment,
            workspace: workspace,
            agentId: agentId
        )

        // Step 7: Sanitize
        await updateStatus(agentId, "Finalizing extraction...")
        let sanitizedText = sanitize(text)

        await logTranscript(
            agentId, .system,
            "Extraction complete: \(sanitizedText.count) characters via \(method.displayDescription)"
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
        agentId: String
    ) async throws -> (String, PDFExtractionMethod) {

        switch judgment.recommendedMethod {

        case .pdfkit:
            await updateStatus(agentId, "Using native text extraction")
            await logTranscript(agentId, .system, "Route: PDFKit (fidelity \(judgment.textFidelity)% acceptable)")
            return (pdfKitText, .pdfkit)

        case .visionOCR:
            await updateStatus(agentId, "Using native Vision OCR...")
            await logTranscript(agentId, .system, "Route: Vision OCR (free, native)")

            // Rasterize all pages for OCR
            await updateStatus(agentId, "Rasterizing all \(pageCount) pages...")
            let allPages = try await rasterizer.rasterizePages(
                pdfDocument: pdfDocument,
                pages: Array(0..<pageCount),
                config: .extraction,
                workspace: workspace
            )

            // Run Vision OCR
            await updateStatus(agentId, "Running OCR on \(pageCount) pages...")
            let text = try await visionOCR.recognizeImages(allPages) { [weak self] completed, total in
                await self?.updateStatus(agentId, "OCR: \(completed)/\(total) pages")
            }

            await logTranscript(agentId, .system, "Vision OCR extracted \(text.count) characters")
            return (text, .visionOCR)

        case .llmVision:
            await logTranscript(agentId, .system, "Route: LLM Vision (complex layout/content)")
            return try await extractWithLLMVision(
                pdfDocument: pdfDocument,
                pageCount: pageCount,
                workspace: workspace,
                agentId: agentId
            )
        }
    }

    // MARK: - LLM Vision Extraction (Parallel)

    private func extractWithLLMVision(
        pdfDocument: PDFDocument,
        pageCount: Int,
        workspace: PDFExtractionWorkspace,
        agentId: String
    ) async throws -> (String, PDFExtractionMethod) {

        // Rasterize all pages
        await updateStatus(agentId, "Rasterizing \(pageCount) pages for vision extraction...")
        let allPages = try await rasterizer.rasterizePages(
            pdfDocument: pdfDocument,
            pages: Array(0..<pageCount),
            config: .extraction,
            workspace: workspace
        )

        // Extract in parallel
        let maxConcurrent = UserDefaults.standard.integer(forKey: "maxConcurrentPDFExtractions")
        await logTranscript(agentId, .system, "Starting parallel vision extraction (max \(max(maxConcurrent, 4)) concurrent)")

        let pageTexts = try await parallelExtractor.extractPages(images: allPages) { [weak self] status in
            await self?.updateStatus(agentId, status)
        }

        let combinedText = pageTexts.enumerated().map { index, text in
            "--- Page \(index + 1) ---\n\(text)"
        }.joined(separator: "\n\n")

        await logTranscript(agentId, .system, "LLM Vision extracted \(combinedText.count) characters from \(pageCount) pages")

        return (combinedText, .llmVision)
    }

    // MARK: - Agent Tracking

    @MainActor
    private func registerAgentOnMain(_ tracker: AgentActivityTracker, id: String, name: String) {
        _ = tracker.trackAgent(
            id: id,
            type: .pdfExtraction,
            name: name,
            status: .running,
            task: nil as Task<Void, Never>?
        )
    }

    private func registerAgent(id: String, name: String) async {
        guard let tracker = agentTracker else { return }
        await registerAgentOnMain(tracker, id: id, name: name)
    }

    @MainActor
    private func updateStatusOnMain(_ tracker: AgentActivityTracker, agentId: String, message: String) {
        tracker.updateStatusMessage(agentId: agentId, message: message)
    }

    private func updateStatus(_ agentId: String, _ message: String) async {
        guard let tracker = agentTracker else { return }
        await updateStatusOnMain(tracker, agentId: agentId, message: message)
    }

    @MainActor
    private func logTranscriptOnMain(_ tracker: AgentActivityTracker, agentId: String, type: AgentTranscriptEntry.EntryType, content: String) {
        tracker.appendTranscript(
            agentId: agentId,
            entryType: type,
            content: content
        )
    }

    private func logTranscript(_ agentId: String, _ type: AgentTranscriptEntry.EntryType, _ content: String) async {
        guard let tracker = agentTracker else { return }
        await logTranscriptOnMain(tracker, agentId: agentId, type: type, content: content)
    }

    @MainActor
    private func completeAgentOnMain(_ tracker: AgentActivityTracker, id: String) {
        tracker.markCompleted(agentId: id)
    }

    private func completeAgent(id: String) async {
        guard let tracker = agentTracker else { return }
        await completeAgentOnMain(tracker, id: id)
    }

    @MainActor
    private func failAgentOnMain(_ tracker: AgentActivityTracker, id: String, error: String) {
        tracker.markFailed(agentId: id, error: error)
    }

    private func failAgent(id: String, error: String) async {
        guard let tracker = agentTracker else { return }
        await failAgentOnMain(tracker, id: id, error: error)
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
