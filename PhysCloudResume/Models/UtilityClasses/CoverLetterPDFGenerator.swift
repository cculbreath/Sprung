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
        
        // Determine how many pages we need
        var done = false
        var fontSize: CGFloat = 11
        var currentLeftMargin = leftMargin
        var currentRightMargin = rightMargin
        var pdfPage: PDFPage?
        
        // First try reducing margins before reducing font size
        while !done && (currentLeftMargin >= 0.5 * 72 || currentRightMargin >= 0.5 * 72) {
            print("Trying with margins: left=\(currentLeftMargin/72)in, right=\(currentRightMargin/72)in")
            
            // Recalculate the text rectangle with current margins
            let currentTextRect = NSRect(
                x: currentLeftMargin,
                y: bottomMargin,
                width: pageRect.width - currentLeftMargin - currentRightMargin,
                height: pageRect.height - topMargin - bottomMargin
            )
            
            // Create attributed text with current font size
            let currentAttributes = attributes.merging([:]) { (current, _) in current }
            let currentAttributedText = NSAttributedString(string: text, attributes: currentAttributes)
            
            // Create a framesetter for the current attributed text
            let framesetter = CTFramesetterCreateWithAttributedString(currentAttributedText as CFAttributedString)
            
            // Size constraints
            let sizeConstraints = CGSize(width: currentTextRect.width, height: CGFloat.greatestFiniteMagnitude)
            
            // Calculate the total height needed
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: currentAttributedText.length),
                nil,
                sizeConstraints,
                nil
            )
            
            print("Suggested size: \(suggestedSize.width)x\(suggestedSize.height), text rect height: \(currentTextRect.height)")
            
            if suggestedSize.height <= currentTextRect.height {
                print("Text fits on one page with margins: left=\(currentLeftMargin/72)in, right=\(currentRightMargin/72)in")
                // Text fits on one page, create the page
                pdfPage = createPDFPage(attributedText: currentAttributedText, pageRect: pageRect, textRect: currentTextRect)
                done = true
            } else {
                // Try reducing margins first (evenly from both sides)
                if currentLeftMargin > 0.5 * 72 && currentRightMargin > 0.5 * 72 {
                    // Reduce both margins by 0.1 inches
                    currentLeftMargin -= 0.1 * 72
                    currentRightMargin -= 0.1 * 72
                } else if currentLeftMargin > 0.5 * 72 {
                    // Only reduce left margin
                    currentLeftMargin -= 0.1 * 72
                } else if currentRightMargin > 0.5 * 72 {
                    // Only reduce right margin
                    currentRightMargin -= 0.1 * 72
                } else {
                    // Minimum margins reached, try reducing font size next
                    break
                }
            }
        }
        
        // If reducing margins didn't work, try reducing font size
        while !done && fontSize >= 9 {
            print("Trying font size: \(fontSize)")
            
            // Use minimum margins
            let minLeftMargin: CGFloat = 0.5 * 72
            let minRightMargin: CGFloat = 0.5 * 72
            
            // Recalculate the text rectangle with minimum margins
            let finalTextRect = NSRect(
                x: minLeftMargin,
                y: bottomMargin,
                width: pageRect.width - minLeftMargin - minRightMargin,
                height: pageRect.height - topMargin - bottomMargin
            )
            
            // Create a new font with the current size
            let currentFont = NSFont(name: font.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let currentAttributes = attributes.merging([.font: currentFont]) { (_, new) in new }
            let currentAttributedText = NSAttributedString(string: text, attributes: currentAttributes)
            
            // Create a new framesetter
            let framesetter = CTFramesetterCreateWithAttributedString(currentAttributedText as CFAttributedString)
            
            // Size constraints
            let sizeConstraints = CGSize(width: finalTextRect.width, height: CGFloat.greatestFiniteMagnitude)
            
            // Calculate the total height needed
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: currentAttributedText.length),
                nil,
                sizeConstraints,
                nil
            )
            
            print("Suggested size with font \(fontSize)pt: \(suggestedSize.width)x\(suggestedSize.height), text rect height: \(finalTextRect.height)")
            
            if suggestedSize.height <= finalTextRect.height {
                print("Text fits on one page with font size \(fontSize)pt and minimum margins")
                // Text fits on one page, create the page
                pdfPage = createPDFPage(attributedText: currentAttributedText, pageRect: pageRect, textRect: finalTextRect)
                done = true
            } else {
                // Try a smaller font size
                fontSize -= 0.5
            }
        }
        
        // If we couldn't fit on one page with reasonable font size, use the minimum font size
        // and minimum margins
        if pdfPage == nil {
            print("Using multi-page layout with minimum font size 9pt and minimum margins")
            
            // Use minimum margins and font size
            let minLeftMargin: CGFloat = 0.5 * 72
            let minRightMargin: CGFloat = 0.5 * 72
            let minFontSize: CGFloat = 9
            
            // Recalculate the text rectangle with minimum margins
            let finalTextRect = NSRect(
                x: minLeftMargin,
                y: bottomMargin,
                width: pageRect.width - minLeftMargin - minRightMargin,
                height: pageRect.height - topMargin - bottomMargin
            )
            
            // Create a new font with the minimum size
            let currentFont = NSFont(name: font.fontName, size: minFontSize) ?? NSFont.systemFont(ofSize: minFontSize)
            let currentAttributes = attributes.merging([.font: currentFont]) { (_, new) in new }
            let currentAttributedText = NSAttributedString(string: text, attributes: currentAttributes)
            
            // Create the page with minimum settings
            pdfPage = createPDFPage(attributedText: currentAttributedText, pageRect: pageRect, textRect: finalTextRect)
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