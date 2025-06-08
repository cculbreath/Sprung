//
//  PDFPreviewView.swift
//  PhysCloudResume
//
//  PDF preview with overlay support for template editing
//

import SwiftUI
import PDFKit
import AppKit

struct PDFPreviewView: NSViewRepresentable {
    let pdfData: Data
    let overlayPDFData: Data?
    let overlayOpacity: Double
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.minScaleFactor = 0.25
        pdfView.maxScaleFactor = 5.0
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if let overlayData = overlayPDFData {
            // Create merged PDF with overlay
            if let mergedPDF = createMergedPDF(mainData: pdfData, overlayData: overlayData, opacity: overlayOpacity) {
                nsView.document = mergedPDF
            } else {
                // Fallback to main PDF only
                nsView.document = PDFDocument(data: pdfData)
            }
        } else {
            // No overlay, just show main PDF
            nsView.document = PDFDocument(data: pdfData)
        }
    }
    
    private func createMergedPDF(mainData: Data, overlayData: Data, opacity: Double) -> PDFDocument? {
        guard let mainPDF = PDFDocument(data: mainData),
              let overlayPDF = PDFDocument(data: overlayData) else {
            return nil
        }
        
        let mergedPDF = PDFDocument()
        
        // Process each page of the main PDF
        for pageIndex in 0..<mainPDF.pageCount {
            guard let mainPage = mainPDF.page(at: pageIndex) else { continue }
            
            // Get the overlay page (use first page if overlay has fewer pages)
            let overlayPageIndex = min(pageIndex, overlayPDF.pageCount - 1)
            guard let overlayPage = overlayPDF.page(at: overlayPageIndex) else {
                // No overlay page, just add main page
                mergedPDF.insert(mainPage, at: mergedPDF.pageCount)
                continue
            }
            
            // Create a new page with both main and overlay content
            let mainBounds = mainPage.bounds(for: .mediaBox)
            let overlayBounds = overlayPage.bounds(for: .mediaBox)
            
            // Create an image with the merged content
            let image = NSImage(size: mainBounds.size)
            image.lockFocus()
            
            guard let context = NSGraphicsContext.current?.cgContext else {
                image.unlockFocus()
                mergedPDF.insert(mainPage, at: mergedPDF.pageCount)
                continue
            }
            
            // Draw main page
            context.saveGState()
            mainPage.draw(with: .mediaBox, to: context)
            context.restoreGState()
            
            // Draw overlay with opacity and proper scaling
            context.saveGState()
            context.setAlpha(CGFloat(opacity))
            
            // Scale overlay to match main page size
            let scaleX = mainBounds.width / overlayBounds.width
            let scaleY = mainBounds.height / overlayBounds.height
            context.scaleBy(x: scaleX, y: scaleY)
            
            overlayPage.draw(   with: .mediaBox, to: context)
            context.restoreGState()
            
            image.unlockFocus()
            
            // Create a new PDF page from the merged image
            if let newPage = PDFPage(image: image) {
                mergedPDF.insert(newPage, at: mergedPDF.pageCount)
            } else {
                // Fallback to main page if image conversion fails
                mergedPDF.insert(mainPage, at: mergedPDF.pageCount)
            }
        }
        
        return mergedPDF
    }
}
