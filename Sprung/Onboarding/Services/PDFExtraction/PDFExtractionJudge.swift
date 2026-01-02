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

        // If null characters detected, skip straight to OCR recommendation
        if hasNullCharacters {
            Logger.info("📊 Judge: Null characters detected - recommending Vision OCR", category: .ai)
            return ExtractionJudgment.quickFail(reason: "null_characters_detected")
        }

        // Load images
        var imageData: [Data] = []
        for url in pageImages {
            let data = try Data(contentsOf: url)
            imageData.append(data)
        }

        // Prepare text samples (truncate if very long)
        let textSample = String(pdfKitText.prefix(8000))

        let prompt = buildJudgePrompt(
            textSample: textSample,
            samplePages: samplePages,
            imageCount: pageImages.count,
            isComposite: isComposite
        )

        let imageType = isComposite ? "composite" : "page"
        Logger.info("📊 Judge: Sending \(pageImages.count) \(imageType) images to Gemini for analysis", category: .ai)

        // Use Gemini's native vision API for image analysis
        let response = try await llmFacade.analyzeImagesWithGemini(
            images: imageData,
            prompt: prompt
        )

        // Parse structured response
        return try parseJudgment(response)
    }

    // MARK: - Prompt Building

    private func buildJudgePrompt(textSample: String, samplePages: [Int], imageCount: Int, isComposite: Bool) -> String {
        let imageDescription = isComposite
            ? "Each image is a 4-page composite (2x2 grid) from the source PDF."
            : "Each image is a single page from the source PDF."

        return """
        You are evaluating the quality of text extraction/OCR performed by another tool on a PDF document.

        ## Why This Matters

        Your assessment will determine which extraction method we use:
        - If the current extraction is high quality, we'll use it as-is (fast, free)
        - If quality is poor but layout is simple, we'll re-extract using conventional PC-based OCR tools like Apple Vision/Tesseract (fast, free)
        - If quality is poor AND layout is complex, we'll use page-by-page LLM vision extraction (slowest, most expensive, but highest fidelity)

        Your job is to help us choose the right path.

        ## Your Task

        I'm providing you with:
        1. **Sample images**: \(imageCount) images showing pages from the original PDF document. \(imageDescription) These images represent the GROUND TRUTH of what the document actually contains. The sampled pages are: \(samplePages.map { String($0 + 1) }.joined(separator: ", ")).

        2. **Extracted text**: The complete text extraction from the ENTIRE document (may be truncated if very long). This is what a text extraction tool produced.

        Your job is to:
        - Look at the text visible in each sample image
        - Find the corresponding section in the extracted text below
        - Assess whether that extraction accurately captured the visible text
        - Only judge extraction quality for content you can see in the images

        <extracted_text>
        \(textSample)
        </extracted_text>

        ## Response Format

        Respond with this JSON structure:

        ```json
        {
          "text_fidelity": <0-100>,
          "layout_complexity": "low" | "medium" | "high",
          "has_math_or_symbols": true | false,
          "issues_found": ["issue1", "issue2", ...],
          "recommended_method": "pdfkit" | "visionOCR" | "llmVision",
          "confidence": <0-100>
        }
        ```

        ## Scoring Guide

        **text_fidelity** (how accurately does extracted text match what you see in the images?):
        - 95-100: Perfect or near-perfect match
        - 85-94: Minor whitespace/formatting differences only
        - 70-84: Some words wrong, garbled, or missing
        - 50-69: Significant portions wrong (e.g., single letters instead of words)
        - 0-49: Mostly broken or missing

        **layout_complexity** (based on what you observe in the images):
        - low: Single column, standard paragraphs, minimal graphics
        - medium: Multi-column, tables, or moderate graphics
        - high: Complex layouts, heavy graphics, forms, or scientific notation

        **issues_found** (note any of these problems you observe):
        - "broken_smallcaps" - Words rendered as single uppercase letters in extraction
        - "missing_text" - Text visible in image but absent from extracted text
        - "garbled_text" - Nonsense characters or encoding issues
        - "missing_tables" - Tables visible but not properly extracted
        - "missing_equations" - Math/equations not captured
        - "wrong_reading_order" - Text extracted in wrong sequence

        **recommended_method** (choose based on fidelity AND layout complexity):
        - "pdfkit": Current extraction is acceptable quality (fidelity >= 90). Use the existing text.
        - "visionOCR": Extraction quality is poor, but layout is simple/medium. Conventional OCR tools (like Tesseract) will likely produce high-fidelity results.
        - "llmVision": Extraction quality is poor AND layout is complex (multi-column, tables, math, forms). Conventional OCR will struggle; recommend page-by-page LLM vision extraction for reliable results.

        Respond ONLY with the JSON object, no other text.
        """
    }

    // MARK: - Response Parsing

    private func parseJudgment(_ response: String) throws -> ExtractionJudgment {
        // Clean up response (remove markdown code blocks if present)
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            Logger.warning("📊 Judge: Failed to parse response - using fallback", category: .ai)
            throw JudgeError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let judgment = try decoder.decode(ExtractionJudgment.self, from: data)
            Logger.info("📊 Judge: Fidelity=\(judgment.textFidelity)%, Layout=\(judgment.layoutComplexity.rawValue), Recommended=\(judgment.recommendedMethod.rawValue)", category: .ai)
            return judgment
        } catch {
            Logger.warning("📊 Judge: JSON parsing failed (\(error.localizedDescription)) - using fallback", category: .ai)
            // Fallback: assume OCR needed if parsing fails
            return ExtractionJudgment(
                textFidelity: 50,
                layoutComplexity: .medium,
                hasMathOrSymbols: false,
                issuesFound: ["judge_parse_failed"],
                recommendedMethod: .visionOCR,
                confidence: 50
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
