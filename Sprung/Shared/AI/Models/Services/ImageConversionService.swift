//
//  ImageConversionService.swift
//  Sprung
//
//  Created by Team on 5/13/25.
//
import Foundation
import PDFKit
import AppKit
import SwiftUI
/// Service for converting PDF data to images
class ImageConversionService {
    /// Shared instance of the service
    static let shared = ImageConversionService()
    private init() {}
    /// Converts a PDF to a base64 encoded image (first page only)
    /// - Parameter pdfData: PDF data to convert
    /// - Returns: Base64 encoded image string or nil if conversion failed
    func convertPDFToBase64Image(pdfData: Data) -> String? {
        guard let pdfDocument = PDFDocument(data: pdfData),
              let pdfPage = pdfDocument.page(at: 0) // Always use the first page
        else {
            return nil
        }
        return convertPageToBase64Image(pdfPage)
    }

    /// Converts multiple PDF pages to base64 encoded images
    /// - Parameters:
    ///   - pdfData: PDF data to convert
    ///   - maxPages: Maximum number of pages to convert (default 10)
    /// - Returns: Array of base64 encoded image strings, or nil if conversion failed
    func convertPDFPagesToBase64Images(pdfData: Data, maxPages: Int = 10) -> [String]? {
        guard let pdfDocument = PDFDocument(data: pdfData) else {
            return nil
        }

        let pageCount = min(pdfDocument.pageCount, maxPages)
        guard pageCount > 0 else { return nil }

        var images: [String] = []
        for index in 0..<pageCount {
            guard let pdfPage = pdfDocument.page(at: index),
                  let base64Image = convertPageToBase64Image(pdfPage) else {
                continue
            }
            images.append(base64Image)
        }

        return images.isEmpty ? nil : images
    }

    /// Get the page count of a PDF
    /// - Parameter pdfData: PDF data
    /// - Returns: Number of pages, or nil if PDF is invalid
    func getPDFPageCount(pdfData: Data) -> Int? {
        guard let pdfDocument = PDFDocument(data: pdfData) else {
            return nil
        }
        return pdfDocument.pageCount
    }

    /// Converts a single PDF page to base64 encoded PNG
    private func convertPageToBase64Image(_ pdfPage: PDFPage) -> String? {
        let pageRect = pdfPage.bounds(for: .mediaBox)
        let renderer = NSImage(size: pageRect.size)
        renderer.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.white.set() // Ensure a white background
        NSRect(origin: .zero, size: pageRect.size).fill()
        if let ctx = NSGraphicsContext.current?.cgContext {
            pdfPage.draw(with: .mediaBox, to: ctx)
        } else {
            renderer.unlockFocus()
            return nil
        }
        renderer.unlockFocus()
        guard let tiffData = renderer.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:])
        else {
            return nil
        }
        return pngData.base64EncodedString()
    }
}
