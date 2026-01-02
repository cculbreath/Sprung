//
//  ExtractionJudgment.swift
//  Sprung
//
//  Result from LLM judge comparing PDFKit text to rasterized images.
//

import Foundation

/// Result from LLM judge comparing PDFKit text to rasterized images
struct ExtractionJudgment: Codable {
    /// How well PDFKit text matches visible content (0-100)
    let textFidelity: Int

    /// Document layout complexity
    let layoutComplexity: LayoutComplexity

    /// Whether document contains math, symbols, or special notation
    let hasMathOrSymbols: Bool

    /// Specific issues detected
    let issuesFound: [String]

    /// LLM's recommended extraction method
    let recommendedMethod: PDFExtractionMethod

    /// Confidence in the recommendation (0-100)
    let confidence: Int

    enum LayoutComplexity: String, Codable {
        case low      // Single column, standard paragraphs
        case medium   // Multi-column, tables, moderate graphics
        case high     // Complex layouts, forms, heavy graphics
    }

    /// Create a quick judgment for known failure cases (e.g., null characters)
    static func quickFail(reason: String) -> ExtractionJudgment {
        ExtractionJudgment(
            textFidelity: 0,
            layoutComplexity: .low,
            hasMathOrSymbols: false,
            issuesFound: [reason],
            recommendedMethod: .visionOCR,
            confidence: 100
        )
    }
}
