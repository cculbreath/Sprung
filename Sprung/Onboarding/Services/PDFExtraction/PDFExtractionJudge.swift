//
//  PDFExtractionJudge.swift
//  Sprung
//
//  Uses LLM to compare PDFKit text against rasterized images
//  to determine optimal extraction method.
//

import Foundation

/// Uses LLM to compare PDFKit text against rasterized images to determine optimal extraction method.
actor PDFExtractionJudge {

    private let llmFacade: LLMFacade

    init(llmFacade: LLMFacade) {
        self.llmFacade = llmFacade
    }

    // MARK: - Judge Method

    /// Judge extraction quality by comparing PDFKit text to rasterized page images
    /// - Parameters:
    ///   - pageImages: URLs to individual page images or 4-up composites
    ///   - pdfKitText: Text extracted via PDFKit for comparison
    ///   - samplePages: Which page numbers were sampled
    ///   - hasNullCharacters: Whether null characters were detected in PDFKit text
    ///   - isComposite: True if images are 4-up composites, false if individual pages
    func judge(
        pageImages: [URL],
        pdfKitText: String,
        samplePages: [Int],
        hasNullCharacters: Bool,
        isComposite: Bool = false
    ) async throws -> ExtractionJudgment {

        // Load images
        var imageData: [Data] = []
        for url in pageImages {
            let data = try Data(contentsOf: url)
            imageData.append(data)
        }

        // Prepare text samples (truncate if very long)
        let textSample = String(pdfKitText.prefix(8000))

        // Note: hasNullCharacters means PDFKit text is corrupted, so "ok" is never valid
        // We still need to evaluate images for graphics/layout complexity to choose OCR vs LLM
        let prompt = buildJudgePrompt(
            textSample: textSample,
            samplePages: samplePages,
            imageCount: pageImages.count,
            isComposite: isComposite,
            hasNullCharacters: hasNullCharacters
        )

        let imageType = isComposite ? "composite" : "page"
        Logger.info("📊 Judge: Sending \(pageImages.count) \(imageType) images to Gemini for analysis", category: .ai)

        // Use Gemini's structured output for guaranteed valid JSON
        let response = try await llmFacade.analyzeImagesWithGeminiStructured(
            images: imageData,
            prompt: prompt,
            jsonSchema: ExtractionJudgment.jsonSchema
        )

        // Parse structured response, with override if text layer is corrupted
        return try parseJudgment(response, hasNullCharacters: hasNullCharacters)
    }

    // MARK: - Prompt Building

    private func buildJudgePrompt(
        textSample: String,
        samplePages: [Int],
        imageCount: Int,
        isComposite: Bool,
        hasNullCharacters: Bool = false
    ) -> String {
        let imageDescription = isComposite
            ? "Each image is a 4-page composite (2x2 grid) from the source PDF."
            : "Each image is a single page from the source PDF."

        // When null characters detected, PDFKit text is unusable - focus on layout/graphics evaluation
        if hasNullCharacters {
            return """
            You are evaluating a PDF document to determine the best extraction method.

            ## Context

            **IMPORTANT**: The PDF's text layer is CORRUPTED (contains null characters). The extracted text below is unreliable and cannot be used as-is. Your task is to evaluate the document's layout and content complexity to choose between:

            - **ocr**: Simple layout (single column, standard paragraphs, no complex formatting). Conventional OCR tools (Apple Vision, Tesseract) will work well. Fast and free.
            - **llm**: Complex layout (multi-column, tables, forms, math/equations, scientific diagrams) OR contains important graphics that need skill assessment. LLM vision extraction is needed. Slower but higher fidelity.

            **Note**: "ok" is NOT a valid choice because the text layer is corrupted.

            ## Your Task

            I'm providing you with \(imageCount) sample images SAMPLED FROM THROUGHOUT the PDF (not contiguous). \(imageDescription)
            Page numbers sampled: \(samplePages.map { String($0 + 1) }.joined(separator: ", ")).

            Evaluate each page for:
            1. **Layout complexity**: Single column vs multi-column? Tables? Forms? Math notation?
            2. **Graphics with important content**: Diagrams, charts, figures, data visualizations that contain information essential to understanding the document
            3. **Skills demonstration**: Figures that demonstrate professional skills (for resume building context)

            ## Decision Criteria

            Choose **ocr** if:
            - ALL pages have simple layout: single column, standard paragraphs, no tables or complex formatting
            - No graphics with essential information that needs interpretation

            Choose **llm** if:
            - ANY page has complex layout (multi-column, tables, forms, math/equations)
            - ANY page contains diagrams, charts, figures, or graphics with essential information
            - The document appears to be a resume, portfolio, or academic work with skill-demonstrating figures

            **Critical**: If ANY page requires LLM extraction, choose llm for the whole document.

            Provide your decision and briefly explain what you observed about the document's layout and content.
            """
        }

        // Standard prompt when PDFKit text is available for comparison
        return """
        You are evaluating the quality of text extraction performed by another tool on a PDF document.

        ## Context

        Your decision will determine which extraction method we use:
        - **ok**: The current extraction is acceptable quality. We'll use it as-is (fast, free).
        - **ocr**: The extraction has problems, but the document layout is simple enough that conventional OCR tools (like Apple Vision or Tesseract) will produce high-fidelity results (fast, free).
        - **llm**: The extraction has problems AND the document has complex layout (multi-column, tables, forms, math, scientific notation). Conventional OCR will struggle, so we need page-by-page LLM vision extraction (slowest, most expensive, but highest fidelity).

        ## Your Task

        I'm providing you with:
        1. **Sample images**: \(imageCount) images showing pages SAMPLED FROM THROUGHOUT the original PDF (not contiguous). \(imageDescription) These are the GROUND TRUTH. Page numbers sampled: \(samplePages.map { String($0 + 1) }.joined(separator: ", ")).

        2. **Extracted text**: Text extraction from the ENTIRE document (may be truncated). This is what a text extraction tool produced.

        **Important**: The sample images are spread throughout the document, not consecutive pages. Each image shows a different page, and each page's content should appear somewhere in the extracted text (but not necessarily adjacent to other sampled pages).

        ## Evaluation Process

        Go through each sample image one by one:
        1. Look at the text visible in the image
        2. Find the corresponding section in the extracted text below
        3. Assess: Does the extraction accurately capture that page's content?

        **Critical**: If ANY page fails quality checks, return the decision needed for that worst-case page. Do NOT average quality across pages. A single problematic page means the entire document needs the more thorough extraction method.

        <extracted_text>
        \(textSample)
        </extracted_text>

        ## Decision Criteria

        Choose **ok** if:
        - ALL sampled pages match well (minor whitespace differences acceptable)
        - No significant missing, garbled, or wrong text on ANY page

        Choose **ocr** if:
        - ANY page has extraction errors (missing words, garbled characters, wrong reading order)
        - BUT all pages have simple layout: single column, standard paragraphs, no complex formatting

        Choose **llm** if:
        - ANY page has extraction errors AND complex layout (multi-column, tables, forms, math/equations, scientific diagrams)
        - Conventional OCR would likely fail to preserve structure or reading order on that page
        - ANY page contains diagrams, charts, figures, or graphics with essential information NOT captured in the extracted text (e.g., data visualizations, flowcharts, annotated images, infographics)

        Provide your decision and briefly explain what you observed (mention specific pages if they drove the decision).
        """
    }

    // MARK: - Response Parsing

    private func parseJudgment(_ response: String, hasNullCharacters: Bool = false) throws -> ExtractionJudgment {
        guard let data = response.data(using: .utf8) else {
            Logger.warning("📊 Judge: Failed to parse response - using fallback", category: .ai)
            throw JudgeError.invalidResponse
        }

        let decoder = JSONDecoder()

        do {
            var judgment = try decoder.decode(ExtractionJudgment.self, from: data)

            // If text layer is corrupted (null chars), override "ok" to "ocr"
            // This safeguard catches cases where the model ignores the instruction
            if hasNullCharacters && judgment.decision == .ok {
                Logger.info("📊 Judge: Overriding 'ok' to 'ocr' because text layer is corrupted", category: .ai)
                judgment = ExtractionJudgment(
                    decision: .ocr,
                    reasoning: "Text layer corrupted (null characters). Original assessment: \(judgment.reasoning)"
                )
            }

            Logger.info("📊 Judge: Decision=\(judgment.decision.rawValue), Reasoning: \(judgment.reasoning.prefix(100))...", category: .ai)
            return judgment
        } catch {
            Logger.warning("📊 Judge: JSON parsing failed (\(error.localizedDescription)) - using fallback", category: .ai)
            // Fallback: assume OCR needed if parsing fails
            return ExtractionJudgment(
                decision: .ocr,
                reasoning: "Judge response parsing failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Error Types

    enum JudgeError: Error, LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from judge LLM"
            }
        }
    }
}
