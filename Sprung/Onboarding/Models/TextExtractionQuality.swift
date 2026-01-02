//
//  TextExtractionQuality.swift
//  Sprung
//
//  Quality metrics for text extraction validation.
//  Used to detect PDFKit extraction failures (e.g., complex fonts producing garbage)
//  and determine when to fall back to Gemini vision extraction.
//

import Foundation

/// Quality metrics for text extraction validation
struct TextExtractionQuality {
    let characterCount: Int
    let nullCharacterCount: Int
    let nullCharacterRatio: Double
    let wordCount: Int
    let averageWordLength: Double
    let pageCount: Int
    let expectedCharCountForPages: Int
    let contentRatio: Double  // actual / expected

    /// Quality score from 0.0 (garbage) to 1.0 (perfect)
    var score: Double {
        var s = 1.0

        // Primary failure mode: null characters from font encoding issues
        // 1% nulls = -0.1, 5% nulls = -0.5, 10%+ nulls = fail
        s -= nullCharacterRatio * 10

        // Missing content penalty
        // Less than 30% expected content = suspicious
        if contentRatio < 0.3 {
            s -= (0.3 - contentRatio) * 2
        }

        // Sanity check: words should average 3-15 chars
        if averageWordLength < 2.0 || averageWordLength > 20.0 {
            s -= 0.3
        }

        // Minimum viable content
        if characterCount < 100 {
            s = 0.0
        }

        return max(0.0, min(1.0, s))
    }

    /// True if text quality is acceptable for downstream processing
    var isAcceptable: Bool { score >= 0.7 }

    /// True if quality is so low that vision fallback is required
    var requiresVisionFallback: Bool { score < 0.5 }

    /// Diagnostic summary for logging
    var diagnosticSummary: String {
        let status = isAcceptable ? "OK" : requiresVisionFallback ? "FAIL" : "WARN"
        return "[\(status)] Quality: \(String(format: "%.0f%%", score * 100)) | " +
               "Chars: \(characterCount)/\(expectedCharCountForPages) expected | " +
               "Nulls: \(String(format: "%.1f%%", nullCharacterRatio * 100))"
    }
}

/// Validate text extraction quality by analyzing content characteristics
/// - Parameters:
///   - text: The extracted text to validate
///   - pageCount: Number of pages in the source document
/// - Returns: Quality metrics for the extraction
func validateTextExtraction(text: String, pageCount: Int) -> TextExtractionQuality {
    // Count null characters (primary indicator of font encoding failure)
    let nullCount = text.unicodeScalars.filter { $0 == "\u{0000}" }.count
    let totalChars = max(text.count, 1)
    let nullRatio = Double(nullCount) / Double(totalChars)

    // Count actual content characters (non-whitespace, non-null)
    let contentChars = text.filter { !$0.isWhitespace && $0 != "\u{0000}" }.count

    // Extract words for sanity check
    let words = text
        .replacingOccurrences(of: "\u{0000}", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .filter { $0.count >= 2 }

    let wordCount = words.count
    let avgWordLen = wordCount > 0
        ? Double(words.map(\.count).reduce(0, +)) / Double(wordCount)
        : 0.0

    // Expected chars: ~3000 per page for typical technical documents
    let expectedChars = pageCount * 3000
    let contentRatio = expectedChars > 0
        ? min(Double(contentChars) / Double(expectedChars), 2.0)
        : 0.0

    return TextExtractionQuality(
        characterCount: contentChars,
        nullCharacterCount: nullCount,
        nullCharacterRatio: nullRatio,
        wordCount: wordCount,
        averageWordLength: avgWordLen,
        pageCount: pageCount,
        expectedCharCountForPages: expectedChars,
        contentRatio: contentRatio
    )
}
