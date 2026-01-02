//
//  ExtractionMethod.swift
//  Sprung
//
//  Extraction method used for PDF text extraction.
//

import Foundation

/// Extraction method used for a PDF
enum PDFExtractionMethod: String, Codable {
    case pdfkit      // Native text extraction (free, fast)
    case visionOCR   // Native Vision framework OCR (free, slower)
    case llmVision   // LLM vision on rasterized images (paid, best quality)

    var cost: Double {
        switch self {
        case .pdfkit: return 0
        case .visionOCR: return 0
        case .llmVision: return 0.15  // approximate per document
        }
    }

    var displayDescription: String {
        switch self {
        case .pdfkit: return "PDFKit text extraction"
        case .visionOCR: return "Vision OCR"
        case .llmVision: return "LLM Vision extraction"
        }
    }
}
