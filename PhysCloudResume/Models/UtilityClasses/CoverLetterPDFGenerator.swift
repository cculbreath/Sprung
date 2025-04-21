import AppKit
import CoreText
import Foundation
import PDFKit
import SwiftUI

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
    
    /// Add signature image to PDF if available
    private static func addSignature(to context: CGContext, in rect: CGRect) {
        // Try to load the signature image
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let possiblePaths = [
            "/Users/cculbreath/devlocal/PhysCloudResume/signature.pdf",
            "/Users/cculbreath/devlocal/PhysCloudResume/signature.png",
            homeDir.appendingPathComponent("signature.pdf").path,
            homeDir.appendingPathComponent("signature.png").path
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                if path.hasSuffix(".pdf"), let pdfDoc = CGPDFDocument(URL(fileURLWithPath: path) as CFURL) {
                    if let page = pdfDoc.page(at: 1) {
                        let sigRect = CGRect(x: rect.origin.x + 30, y: rect.origin.y + 100, width: 150, height: 50)
                        context.saveGState()
                        context.translateBy(x: sigRect.origin.x, y: sigRect.origin.y)
                        context.scaleBy(x: sigRect.width / page.getBoxRect(.mediaBox).width, 
                                       y: sigRect.height / page.getBoxRect(.mediaBox).height)
                        context.drawPDFPage(page)
                        context.restoreGState()
                    }
                    return
                } else if let image = NSImage(contentsOfFile: path) {
                    let sigRect = CGRect(x: rect.origin.x + 30, y: rect.origin.y + 100, width: 150, height: 50)
                    context.saveGState()
                    
                    // Draw image preserving transparency
                    if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        context.translateBy(x: 0, y: rect.height)
                        context.scaleBy(x: 1.0, y: -1.0)
                        context.draw(cgImage, in: sigRect)
                    }
                    
                    context.restoreGState()
                    return
                }
            }
        }
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
        let leftMargin: CGFloat = 1.3 * 72 // 1.3 inches
        let rightMargin: CGFloat = 2.5 * 72 // 2.5 inches
        let topMargin: CGFloat = 0.75 * 72 // 0.75 inches
        let bottomMargin: CGFloat = 0.75 * 72 // 0.75 inches

        // Prepare text attributes with Futura Light font
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        paragraphStyle.paragraphSpacing = 12
        paragraphStyle.alignment = .natural
        
        // Register the Futura Light font from the system
        var font: NSFont?
        
        // Try loading from specific path provided
        let futuraPaths = [
            "/Library/Fonts/futuralight.ttf", 
            "/System/Library/Fonts/Supplemental/Futura.ttc"
        ]
        
        // Register fonts for use
        for path in futuraPaths {
            if FileManager.default.fileExists(atPath: path) {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, &error)
            }
        }
        
        // Try different possible font names for Futura Light
        let fontNames = ["FuturaLight", "Futura-Light", "Futura Light"]
        for name in fontNames {
            if let loadedFont = NSFont(name: name, size: 11) {
                font = loadedFont
                break
            }
        }
        
        // Fallback to system font if Futura Light isn't available
        if font == nil {
            font = NSFont.systemFont(ofSize: 11)
        }
        
        print("Using font: \(font!.fontName)")

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font!,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle,
        ]

        // Determine how many pages we need
        var done = false
        var fontSize: CGFloat = 11
        var currentLeftMargin = leftMargin
        var currentRightMargin = rightMargin

        // Create a direct PDF approach - no image conversion
        let pdfDocument = PDFDocument()
        
        // Try different margin and font size combinations
        while !done && (currentLeftMargin >= 0.5 * 72 || currentRightMargin >= 0.5 * 72) {
            print("Trying with margins: left=\(currentLeftMargin / 72)in, right=\(currentRightMargin / 72)in")

            // Recalculate the text rectangle with current margins
            let currentTextRect = NSRect(
                x: currentLeftMargin,
                y: bottomMargin,
                width: pageRect.width - currentLeftMargin - currentRightMargin,
                height: pageRect.height - topMargin - bottomMargin
            )

            // Create attributed text with current font size
            let currentAttributes = attributes.merging([:]) { current, _ in current }
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
                print("Text fits on one page with margins: left=\(currentLeftMargin / 72)in, right=\(currentRightMargin / 72)in")
                // Text fits on one page, create the page using direct PDF generation
                let page = createDirectPDFPage(text: text, attributes: currentAttributes, pageRect: pageRect, textRect: currentTextRect)
                if let page = page {
                    pdfDocument.insert(page, at: 0)
                    done = true
                } else {
                    print("Failed to create page, trying different margins")
                }
            }

            if !done {
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
            let currentFont = NSFont(name: font!.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let currentAttributes = attributes.merging([.font: currentFont]) { _, new in new }

            // Create a framesetter for the current attributed text
            let currentAttributedText = NSAttributedString(string: text, attributes: currentAttributes)
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
                let page = createDirectPDFPage(text: text, attributes: currentAttributes, pageRect: pageRect, textRect: finalTextRect)
                if let page = page {
                    pdfDocument.insert(page, at: 0)
                    done = true
                } else {
                    print("Failed to create page, trying smaller font")
                }
            }
            
            if !done {
                // Try a smaller font size
                fontSize -= 0.5
            }
        }

        // If we couldn't fit on one page, create a multi-page PDF document
        if pdfDocument.pageCount == 0 {
            print("Creating multi-page PDF with minimum settings")
            
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
            
            // Create attributes with minimum font size
            let currentFont = NSFont(name: font!.fontName, size: minFontSize) ?? NSFont.systemFont(ofSize: minFontSize)
            let currentAttributes = attributes.merging([.font: currentFont]) { _, new in new }
            
            // Create a blank document
            let defaultPage = createSimplePDFPage(text: text, attributes: currentAttributes, pageRect: pageRect, textRect: finalTextRect)
            if let page = defaultPage {
                pdfDocument.insert(page, at: 0)
            }
        }

        // Return the PDF data
        if let pdfData = pdfDocument.dataRepresentation() {
            print("Created PDF with \(pdfDocument.pageCount) pages, \(pdfData.count) bytes")
            return pdfData
        }

        print("Failed to create PDF, returning empty data")
        return Data()
    }
    
    /// Creates a PDF page using a direct CoreGraphics PDF creation approach
    private static func createDirectPDFPage(text: String, attributes: [NSAttributedString.Key: Any], pageRect: NSRect, textRect: NSRect) -> PDFPage? {
        // Create a direct PDF document
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height)
        
        // Create a PDF context directly
        guard let pdfContext = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!,
                                        mediaBox: &mediaBox,
                                        nil) else {
            print("Failed to create PDF context")
            return nil
        }
        
        // Begin a new PDF page
        pdfContext.beginPage(mediaBox: &mediaBox)
        
        // Fill the background with white
        pdfContext.setFillColor(NSColor.white.cgColor)
        pdfContext.fill(mediaBox)
        
        // Flip coordinates for PDF rendering (PDF uses bottom-left origin)
        pdfContext.saveGState()
        pdfContext.translateBy(x: 0, y: pageRect.height)
        pdfContext.scaleBy(x: 1.0, y: -1.0)
        
        // Draw text using CoreText
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let framePath = CGPath(rect: CGRect(x: textRect.origin.x, 
                                           y: 0,
                                           width: textRect.width, 
                                           height: textRect.height), 
                              transform: nil)
        
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), framePath, nil)
        
        CTFrameDraw(frame, pdfContext)
        
        // Try to add signature image if available
        addSignature(to: pdfContext, in: textRect)
        pdfContext.restoreGState()
        
        // End the PDF page
        pdfContext.endPage()
        
        // Create a PDF document from the data
        if let pdfDocument = PDFDocument(data: data as Data), pdfDocument.pageCount > 0 {
            // Return the first page of the document
            return pdfDocument.page(at: 0)
        }
        
        // Fallback to a simpler approach if the CoreText approach failed
        return createSimplePDFPage(text: text, attributes: attributes, pageRect: pageRect, textRect: textRect)
    }
    
    /// Creates a simple PDF page using PDFKit's built-in capabilities
    private static func createSimplePDFPage(text: String, attributes: [NSAttributedString.Key: Any], pageRect: NSRect, textRect: NSRect) -> PDFPage? {
        // Create a PDF document
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        
        // Create a drawing area and draw into it
        let image = NSImage(size: pageRect.size)
        image.lockFocus()
        
        // Fill background with white
        NSColor.white.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: pageRect.size))
        
        // Draw text
        attributedText.draw(in: textRect)
        
        // Complete drawing
        image.unlockFocus()
        
        // Create PDF page from image
        return PDFPage(image: image)
    }
}