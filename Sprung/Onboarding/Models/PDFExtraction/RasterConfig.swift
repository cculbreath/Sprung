//
//  RasterConfig.swift
//  Sprung
//
//  Configuration for PDF rasterization.
//

import Foundation

/// Configuration for PDF rasterization
struct RasterConfig {
    let dpi: Int
    let jpegQuality: Int
    let compositeMode: CompositeMode

    enum CompositeMode {
        case single   // One image per page (for extraction)
        case fourUp   // 2x2 grid (for judge step - 4x coverage)
    }

    /// For judge step: 4-up at 300 DPI for maximum coverage
    static let judge = RasterConfig(dpi: 300, jpegQuality: 70, compositeMode: .fourUp)

    /// For extraction: single pages at 200 DPI
    static let extraction = RasterConfig(dpi: 200, jpegQuality: 70, compositeMode: .single)
}
