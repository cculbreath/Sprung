//
//  PDFRasterizer.swift
//  Sprung
//
//  Rasterizes PDF pages to JPEG images using native PDFKit + CoreGraphics.
//  This is THE FIREWALL that destroys font encoding bugs.
//  No external dependencies required.
//

import Foundation
import PDFKit
import CoreGraphics
import AppKit

/// Rasterizes PDF pages to JPEG images using native PDFKit + CoreGraphics.
actor PDFRasterizer {

    // MARK: - Page Selection

    /// Select pages to sample for quality judgment.
    /// Uses ~5% of pages, with min 3 and max 10 to balance coverage vs API cost.
    func selectSamplePages(pageCount: Int) -> [Int] {
        let minSamples = 3
        let maxSamples = 10

        // Calculate 5% of pages, clamped to min/max
        let targetSamples = max(minSamples, min(maxSamples, Int(ceil(Double(pageCount) * 0.05))))

        if pageCount <= targetSamples {
            return Array(0..<pageCount)
        }

        // Spread samples evenly across document
        let step = max(1, pageCount / targetSamples)
        return (0..<targetSamples).map { min($0 * step, pageCount - 1) }
    }

    // MARK: - Rasterization

    /// Rasterize specific pages from PDF into workspace
    func rasterizePages(
        pdfDocument: PDFDocument,
        pages: [Int],
        config: RasterConfig,
        workspace: PDFExtractionWorkspace
    ) async throws -> [URL] {
        var pageImages: [URL] = []

        for pageIndex in pages {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            let outputURL = await workspace.pageImageURL(pageIndex: pageIndex)
            let image = try renderPageToImage(page: page, dpi: config.dpi)
            try saveAsJPEG(image: image, to: outputURL, quality: config.jpegQuality)

            pageImages.append(outputURL)
        }

        return pageImages
    }

    /// Create 4-up composites from page images (2x2 grid)
    func createFourUpComposites(
        pageImages: [URL],
        workspace: PDFExtractionWorkspace
    ) async throws -> [URL] {
        var composites: [URL] = []
        let chunks = pageImages.chunked(into: 4)

        for (index, chunk) in chunks.enumerated() {
            let outputURL = await workspace.compositeURL(index: index)
            let composite = try createCompositeImage(from: chunk)
            try saveAsJPEG(image: composite, to: outputURL, quality: RasterConfig.judge.jpegQuality)
            composites.append(outputURL)
        }

        return composites
    }

    // MARK: - Private Rendering Methods

    /// Render a PDF page to CGImage at specified DPI
    private func renderPageToImage(page: PDFPage, dpi: Int) throws -> CGImage {
        let pageRect = page.bounds(for: .mediaBox)

        // Calculate pixel dimensions based on DPI
        // PDF points are 72 per inch
        let scale = CGFloat(dpi) / 72.0
        let pixelWidth = Int(pageRect.width * scale)
        let pixelHeight = Int(pageRect.height * scale)

        // Create bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw RasterizerError.contextCreationFailed
        }

        // Fill with white background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // Scale and render PDF page
        context.scaleBy(x: scale, y: scale)

        // PDFPage draws with origin at bottom-left, same as CGContext
        page.draw(with: .mediaBox, to: context)

        guard let image = context.makeImage() else {
            throw RasterizerError.imageCreationFailed
        }

        return image
    }

    /// Create a 2x2 composite image from up to 4 page images
    private func createCompositeImage(from imageURLs: [URL]) throws -> CGImage {
        // Load images
        var images: [CGImage] = []
        for url in imageURLs {
            guard let dataProvider = CGDataProvider(url: url as CFURL),
                  let image = CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
                throw RasterizerError.imageLoadFailed(url.lastPathComponent)
            }
            images.append(image)
        }

        guard !images.isEmpty else {
            throw RasterizerError.noImages
        }

        // Calculate composite dimensions
        // Use first image dimensions as reference, add 4px gap
        let gap = 4
        let cellWidth = images[0].width
        let cellHeight = images[0].height
        let compositeWidth = cellWidth * 2 + gap * 3  // gap | img | gap | img | gap
        let compositeHeight = cellHeight * 2 + gap * 3

        // Create composite context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: compositeWidth,
            height: compositeHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw RasterizerError.contextCreationFailed
        }

        // Fill with white background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: compositeWidth, height: compositeHeight))

        // Draw images in 2x2 grid
        // CGContext origin is bottom-left, so:
        // Position 0 (top-left)     -> bottom-left in CG  -> (gap, cellHeight + gap*2)
        // Position 1 (top-right)    -> bottom-right in CG -> (cellWidth + gap*2, cellHeight + gap*2)
        // Position 2 (bottom-left)  -> top-left in CG     -> (gap, gap)
        // Position 3 (bottom-right) -> top-right in CG    -> (cellWidth + gap*2, gap)

        let positions = [
            CGRect(x: gap, y: cellHeight + gap * 2, width: cellWidth, height: cellHeight),           // top-left
            CGRect(x: cellWidth + gap * 2, y: cellHeight + gap * 2, width: cellWidth, height: cellHeight), // top-right
            CGRect(x: gap, y: gap, width: cellWidth, height: cellHeight),                             // bottom-left
            CGRect(x: cellWidth + gap * 2, y: gap, width: cellWidth, height: cellHeight)              // bottom-right
        ]

        for (index, image) in images.enumerated() {
            guard index < positions.count else { break }
            context.draw(image, in: positions[index])
        }

        guard let composite = context.makeImage() else {
            throw RasterizerError.imageCreationFailed
        }

        return composite
    }

    /// Save CGImage as JPEG
    private func saveAsJPEG(image: CGImage, to url: URL, quality: Int) throws {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: Double(quality) / 100.0]
              ) else {
            throw RasterizerError.jpegEncodingFailed
        }

        try jpegData.write(to: url)
    }

    // MARK: - Error Types

    enum RasterizerError: Error, LocalizedError {
        case contextCreationFailed
        case imageCreationFailed
        case imageLoadFailed(String)
        case jpegEncodingFailed
        case noImages

        var errorDescription: String? {
            switch self {
            case .contextCreationFailed: return "Failed to create graphics context"
            case .imageCreationFailed: return "Failed to create image from context"
            case .imageLoadFailed(let name): return "Failed to load image: \(name)"
            case .jpegEncodingFailed: return "Failed to encode JPEG"
            case .noImages: return "No images to composite"
            }
        }
    }
}
