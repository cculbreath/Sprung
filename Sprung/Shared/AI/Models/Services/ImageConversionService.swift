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

    /// Converts all pages of a PDF to PNG image data
    /// - Parameter pdfData: PDF data to convert
    /// - Returns: Array of PNG image data for each page, or nil if conversion failed
    func convertPDFToAllPageImages(pdfData: Data) -> [Data]? {
        guard let pdfDocument = PDFDocument(data: pdfData), pdfDocument.pageCount > 0 else {
            return nil
        }
        var pages: [Data] = []
        for i in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: i),
                  let imageData = convertPageToImageData(page) else {
                return nil
            }
            pages.append(imageData)
        }
        return pages.isEmpty ? nil : pages
    }

    /// Converts a single PDF page to base64 encoded PNG
    private func convertPageToBase64Image(_ pdfPage: PDFPage) -> String? {
        guard let pngData = convertPageToImageData(pdfPage) else {
            return nil
        }
        return pngData.base64EncodedString()
    }

    /// Converts a single PDF page to PNG image data
    private func convertPageToImageData(_ pdfPage: PDFPage) -> Data? {
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
        return pngData
    }
}
