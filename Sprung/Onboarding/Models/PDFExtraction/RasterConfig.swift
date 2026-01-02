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

    /// For judge step: reads DPI and composite mode from Settings
    static var judge: RasterConfig {
        let dpi = UserDefaults.standard.integer(forKey: "pdfJudgeDPI")
        let useFourUp = UserDefaults.standard.bool(forKey: "pdfJudgeUseFourUp")
        return RasterConfig(
            dpi: dpi > 0 ? dpi : 150,  // Default 150 DPI
            jpegQuality: 70,
            compositeMode: useFourUp ? .fourUp : .single
        )
    }

    /// For extraction: single pages at 200 DPI
    static let extraction = RasterConfig(dpi: 200, jpegQuality: 70, compositeMode: .single)
}
