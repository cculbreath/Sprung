//
//  ExtractionConfig.swift
//  Sprung
//
//  Configuration parameters for document extraction pipeline.
//

import Foundation

/// Configuration for document extraction pipeline
enum ExtractionConfig {
    /// Max characters for summary input
    static let summaryInputLimit = 100_000

    /// Max characters for inventory input
    static let inventoryInputLimit = 200_000
}
