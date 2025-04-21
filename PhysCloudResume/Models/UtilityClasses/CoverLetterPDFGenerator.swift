import AppKit
import Foundation
import PDFKit
import SwiftUI
import CoreText

enum CoverLetterPDFGenerator {
    static func generatePDF(from coverLetter: CoverLetter, applicant: Applicant) -> Data {
        print("Generating PDF from cover letter...")
        let text = buildLetterText(from: coverLetter, applicant: applicant)
        let pdfData = createPDFFromString(text)
        
        // Debug - save PDF to desktop
        saveDebugPDF(pdfData)
        
        return pdfData
    }
    
    private static func saveDebugPDF(_ data: Data) {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let debugPath = homeDirectory.appendingPathComponent("Desktop/debug_coverletter.pdf")
        
        do {
            try data.write(to: debugPath)
            print("Debug PDF saved to: \(debugPath.path)")
        } catch {
            print("Error saving debug PDF: \(error)")
        }
    }

    // MARK: - Private Helpers
    
    private static func buildLetterText(from cover: CoverLetter, applicant: Applicant) -> String {
        """
        \(formattedToday())
        
        Dear Hiring Manager,
        
        \(cover.content)
        
        Best Regards,
        
        \(applicant.name)
        
        \(applicant.phone) | \(applicant.address), \(applicant.city), \(applicant.state) \(applicant.zip)
        \(applicant.email) | \(applicant.websites)
        """
    }
    
    private static func formattedToday() -> String {
        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        return df.string(from: Date())
    }
    
    private static func createPDFFromString(_ text: String) -> Data {
        print("Creating high-quality vector PDF with text: \(text.count) chars")
        
        // Page setup
        let pageRect = NSRect(x: 0, y: 0, width: 8.5 * 72, height: 11 * 72) // Letter size
        let leftMargin: CGFloat = 1.3 * 72    // 1.3 inches
        let rightMargin: CGFloat = 2.5 * 72   // 2.5 inches
        let topMargin: CGFloat = 0.75 * 72    // 0.75 inches
        let bottomMargin: CGFloat = 0.75 * 72 // 0.75 inches
        
        // Create a PDF document
        let pdfDocument = PDFDocument()
        
        // Prepare text attributes with Futura font
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 10
        
        let font = NSFont(name: "Futura-Light", size: 11) ?? NSFont.systemFont(ofSize: 11)
        print("Using font: \(font.fontName)")
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]
        
        // Create attributed text
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        
        // Set up the drawing rectangle
        let textRect = NSRect(
            x: leftMargin,
            y: bottomMargin,
            width: pageRect.width - leftMargin - rightMargin,
            height: pageRect.height - topMargin - bottomMargin
        )
        
        // Create a framesetter for the attributed text
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        
        // Determine how many pages we need
        var textPos = 0
        var done = false
        var pageNumber = 0
        var fontSize: CGFloat = 11
        var pdfPage: PDFPage?
        
        // Try to fit the text on a single page if possible
        while !done && fontSize >= 9 {
            print("Trying font size: \(fontSize)")
            
            // Create a new graphics context
            let context = NSGraphicsContext.current
            let mediaBox = CGRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height)
            
            // Size constraints
            let sizeConstraints = CGSize(width: textRect.width, height: CGFloat.greatestFiniteMagnitude)
            
            // Calculate the total height needed
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: attributedText.length),
                nil,
                sizeConstraints,
                nil
            )
            
            print("Suggested size: \(suggestedSize.width)x\(suggestedSize.height), text rect height: \(textRect.height)")
            
            if suggestedSize.height <= textRect.height {
                print("Text fits on one page with font size \(fontSize)")
                // Text fits on one page, create the page
                pdfPage = createPDFPage(attributedText: attributedText, pageRect: pageRect, textRect: textRect)
                done = true
            } else {
                // Try a smaller font
                fontSize -= 0.5
                
                // Update the font size in the attributes
                let newFont = NSFont(name: font.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                let newAttributes = attributes.merging([.font: newFont]) { (_, new) in new }
                let newAttributedText = NSAttributedString(string: text, attributes: newAttributes)
                attributedText = newAttributedText
                framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
            }
        }
        
        // If we couldn't fit on one page with reasonable font size, use the current font size
        // and accept multiple pages
        if pdfPage == nil {
            print("Using multi-page layout with font size \(fontSize)")
            pdfPage = createPDFPage(attributedText: attributedText, pageRect: pageRect, textRect: textRect)
        }
        
        // Add the page to the document
        if let page = pdfPage {
            pdfDocument.insert(page, at: 0)
        }
        
        // Return the PDF data
        if let pdfData = pdfDocument.dataRepresentation() {
            print("Created PDF with \(pdfDocument.pageCount) pages, \(pdfData.count) bytes")
            return pdfData
        }
        
        print("Failed to create PDF data")
        return Data()
    }
    
    private static func createPDFPage(attributedText: NSAttributedString, pageRect: NSRect, textRect: NSRect) -> PDFPage {
        // Create a PDF context
        let data = NSMutableData()
        let mediaBox = CGRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height)
        
        // Create a graphics context to render into
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pageRect.width),
            pixelsHigh: Int(pageRect.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        
        // Set up the graphics context with the bitmap representation
        let context = NSGraphicsContext(bitmapImageRep: bitmapRep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        // Fill background with white
        NSColor.white.set()
        NSBezierPath.fill(NSRect(origin: .zero, size: pageRect.size))
        
        // Draw the text at the correct position
        attributedText.draw(in: textRect)
        
        // Restore the previous graphics context
        NSGraphicsContext.restoreGraphicsState()
        
        // Create a PDF document with the drawn content
        let pdfData = NSMutableData()
        var mediaBoxCG = mediaBox
        
        guard let pdfContext = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!, mediaBox: &mediaBoxCG, nil) else {
            // Fallback to image-based PDF if CGContext creation fails
            let image = NSImage(size: pageRect.size)
            image.addRepresentation(bitmapRep)
            return PDFPage(image: image)!
        }
        
        // Begin the PDF page
        pdfContext.beginPage(mediaBox: &mediaBoxCG)
        
        // Create a PDF graphics context
        let pdfNSContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = pdfNSContext
        
        // Draw the text directly into the PDF context
        attributedText.draw(in: textRect)
        
        // Restore the graphics state
        NSGraphicsContext.restoreGraphicsState()
        
        // End the PDF page
        pdfContext.endPage()
        
        // Create a PDF page from the generated data
        let pdfPage = PDFPage(image: NSImage(data: pdfData as Data)!)!
        
        return pdfPage
    }
}