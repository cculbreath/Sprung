//
//  PDFExtractionMethod.swift
//  Sprung
//
//  Defines extraction methods for PDF documents.
//
import Foundation

/// Extraction method for PDF documents
enum LargePDFExtractionMethod: String, CaseIterable {
    case chunkedNative = "chunked"
    case textExtract = "text_extract"

    var displayName: String {
        switch self {
        case .chunkedNative: return "Native PDF"
        case .textExtract: return "Text extraction"
        }
    }

    var description: String {
        switch self {
        case .chunkedNative: return "Best quality - sends PDF directly to AI"
        case .textExtract: return "Faster - extracts text locally first"
        }
    }
}
