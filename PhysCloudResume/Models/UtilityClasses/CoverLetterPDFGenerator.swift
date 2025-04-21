import AppKit
import Foundation
import PDFKit
import SwiftUI

enum CoverLetterPDFGenerator {
    static func generatePDF(from coverLetter: CoverLetter, applicant: Applicant) -> Data {
        let text = buildLetterText(from: coverLetter, applicant: applicant)
        return createPDFFromString(text)
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
        // Create the PDF document
        let pdfDocument = PDFDocument()
        
        // Create a scrollable text view
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612-144, height: 792-144))
        textView.string = text
        textView.backgroundColor = .white
        
        // Set paragraph style and font
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 10
        
        let font = NSFont.systemFont(ofSize: 12)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        textView.textStorage?.setAttributedString(attributedString)
        
        // Render the text view to an image
        let textImage = NSImage(size: textView.bounds.size)
        textImage.lockFocus()
        textView.draw(textView.frame)
        textImage.unlockFocus()
        
        // Create a PDF page from the image
        if let pdfPage = PDFPage(image: textImage) {
            pdfDocument.insert(pdfPage, at: 0)
            return pdfDocument.dataRepresentation() ?? Data()
        }
        
        return Data()
    }
}