//
//  ExtractionJudgment.swift
//  Sprung
//
//  Result from LLM judge comparing PDFKit text to rasterized images.
//

import Foundation

/// Decision from LLM judge on which extraction method to use
enum ExtractionDecision: String, Codable {
    case ok    // PDFKit extraction is acceptable quality
    case ocr   // Use conventional OCR (Vision/Tesseract)
    case llm   // Use page-by-page LLM vision extraction
    case error // Judge encountered an error
}

/// Result from LLM judge comparing PDFKit text to rasterized images
struct ExtractionJudgment: Codable {
    /// The extraction method decision
    let decision: ExtractionDecision

    /// Reasoning for the decision
    let reasoning: String

    /// Create a quick judgment for known failure cases (e.g., null characters)
    static func quickFail(reason: String) -> ExtractionJudgment {
        ExtractionJudgment(
            decision: .ocr,
            reasoning: reason
        )
    }

    /// Create an error judgment
    static func error(_ message: String) -> ExtractionJudgment {
        ExtractionJudgment(
            decision: .error,
            reasoning: message
        )
    }

    /// Map decision to extraction method
    var recommendedMethod: PDFExtractionMethod {
        switch decision {
        case .ok:
            return .pdfkit
        case .ocr:
            return .visionOCR
        case .llm, .error:
            return .llmVision
        }
    }

    /// JSON Schema for Gemini structured output
    static var jsonSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "decision": [
                    "type": "string",
                    "enum": ["ok", "ocr", "llm"]
                ],
                "reasoning": [
                    "type": "string"
                ]
            ],
            "required": ["decision", "reasoning"]
        ]
    }
}
