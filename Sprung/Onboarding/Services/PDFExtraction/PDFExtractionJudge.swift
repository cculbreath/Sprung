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

    /// Judge extraction quality by comparing PDFKit text to rasterized images
    func judge(
        compositeImages: [URL],
        pdfKitText: String,
        samplePages: [Int],
        hasNullCharacters: Bool
    ) async throws -> ExtractionJudgment {

        // If null characters detected, skip straight to OCR recommendation
        if hasNullCharacters {
            Logger.info("📊 Judge: Null characters detected - recommending Vision OCR", category: .ai)
            return ExtractionJudgment.quickFail(reason: "null_characters_detected")
        }

        // Load composite images
        var imageData: [Data] = []
        for url in compositeImages {
            let data = try Data(contentsOf: url)
            imageData.append(data)
        }

        // Prepare text samples (truncate if very long)
        let textSample = String(pdfKitText.prefix(8000))

        let prompt = buildJudgePrompt(
            textSample: textSample,
            samplePages: samplePages,
            imageCount: compositeImages.count
        )

        // Call Gemini via LLMFacade
        Logger.info("📊 Judge: Sending \(compositeImages.count) composite images to LLM for analysis", category: .ai)

        let response = try await llmFacade.executeTextWithImages(
            prompt: prompt,
            modelId: "gemini-2.5-flash",
            images: imageData,
            temperature: 0.1,
            backend: .gemini
        )

        // Parse structured response
        return try parseJudgment(response)
    }

    // MARK: - Prompt Building

    private func buildJudgePrompt(textSample: String, samplePages: [Int], imageCount: Int) -> String {
        """
        You are evaluating PDF text extraction quality.

        I'm showing you \(imageCount) composite images, each containing 4 pages from the document.
        The pages sampled are: \(samplePages.map { String($0 + 1) }.joined(separator: ", "))

        Below is the text extracted by PDFKit from these same pages:

        <extracted_text>
        \(textSample)
        </extracted_text>

        Compare the extracted text to what you see in the images and respond with JSON:

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

        **text_fidelity** (how well does extracted text match visible text?):
        - 95-100: Perfect or near-perfect match
        - 85-94: Minor whitespace/formatting differences only
        - 70-84: Some words wrong, garbled, or missing
        - 50-69: Significant portions wrong (e.g., single letters instead of words)
        - 0-49: Mostly broken or missing

        **layout_complexity**:
        - low: Single column, standard paragraphs, minimal graphics
        - medium: Multi-column, tables, or moderate graphics
        - high: Complex layouts, heavy graphics, forms, or scientific notation

        **issues_found** (check for these):
        - "broken_smallcaps" - Single uppercase letters where words should be
        - "missing_text" - Text visible in image but absent from extraction
        - "garbled_text" - Nonsense characters or encoding issues
        - "missing_tables" - Tables visible but not extracted properly
        - "missing_equations" - Math/equations not captured
        - "wrong_reading_order" - Text extracted in wrong sequence

        **recommended_method**:
        - "pdfkit": Use if text_fidelity >= 90 AND layout is simple
        - "visionOCR": Use if text_fidelity < 90 AND layout is simple/medium
        - "llmVision": Use if layout is complex OR has math/equations OR OCR would struggle

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
