import AppKit
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

    private static func formattedToday() -> String {
        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        return df.string(from: Date())
    }

    private static func createPDFFromString(_ text: String) -> Data {
        print("Creating PDF with text length: \(text.count) chars")
        
        // Create a PDF context
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)  // US Letter
        let margin: CGFloat = 72.0  // 1-inch margins
        
        // Create a data object to hold the PDF content
        let pdfData = NSMutableData()
        
        // Create a PDF context
        var mediaBox = pageRect
        guard let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!, 
                                      mediaBox: &mediaBox, 
                                      nil) else {
            print("Failed to create PDF context")
            return Data()
        }
        
        // Begin PDF and first page
        context.beginPDF(mediaBox: &mediaBox)
        context.beginPage(mediaBox: &mediaBox)
        
        // Calculate the drawing rectangle (with margins)
        let drawingRect = CGRect(x: margin, 
                                y: margin, 
                                width: pageRect.width - (2 * margin), 
                                height: pageRect.height - (2 * margin))
        
        // Fill with white
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageRect)
        
        // Create attributed string
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural
        paragraphStyle.lineSpacing = 6
        paragraphStyle.paragraphSpacing = 12
        
        let font = NSFont.systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        print("Created attributed string")
        
        // Create a temporary frame to calculate layout
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        let path = CGMutablePath()
        path.addRect(drawingRect)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        // Draw the text frame
        context.saveGState()
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, context)
        context.restoreGState()
        
        // End the page and PDF
        context.endPage()
        context.endPDF()
        
        print("PDF created with size: \(pdfData.length) bytes")
        
        // Debug - save a copy of the drawing rectangle
        let debugImage = NSImage(size: pageRect.size)
        debugImage.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: pageRect.size).fill()
        NSColor.blue.set()
        NSRect(x: margin, y: margin, width: pageRect.width - (2 * margin), height: pageRect.height - (2 * margin)).stroke()
        NSColor.black.set()
        attributedString.draw(in: NSRect(x: margin, y: margin, width: pageRect.width - (2 * margin), height: pageRect.height - (2 * margin)))
        debugImage.unlockFocus()
        
        if let tiffData = debugImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let debugImagePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/debug_image.png")
            do {
                try pngData.write(to: debugImagePath)
                print("Debug image saved to: \(debugImagePath.path)")
            } catch {
                print("Error saving debug image: \(error)")
            }
        }
        
        return pdfData as Data
    }
}
