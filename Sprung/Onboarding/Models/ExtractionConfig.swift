//
//  ExtractionConfig.swift
//  Sprung
//
//  Configuration parameters for PDF extraction pipeline.
//  Tunable parameters for quality thresholds, chunking, and rate limiting.
//

import Foundation

/// Configuration for PDF extraction pipeline
enum ExtractionConfig {
    /// Pages per chunk for large documents
    static let chunkSize = 25

    /// Max pages for single-pass extraction
    static let singlePassThreshold = 30

    /// Quality score threshold for PDFKit acceptance
    static let pdfKitQualityThreshold = 0.7

    /// Quality score below which vision extraction is required
    static let visionFallbackThreshold = 0.5

    /// Max characters for summary input
    static let summaryInputLimit = 100_000

    /// Max characters for inventory input
    static let inventoryInputLimit = 200_000

    /// Delay between chunks (rate limiting) in milliseconds
    static let interChunkDelayMs = 300

    /// Max retry attempts per chunk
    static let maxChunkRetries = 2

    /// Max output tokens for single-pass vision extraction
    static let singlePassMaxTokens = 65536

    /// Max output tokens for chunked vision extraction
    static let chunkMaxTokens = 50000
}
