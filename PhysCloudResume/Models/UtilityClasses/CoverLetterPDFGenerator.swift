import Foundation
import CoreText
import PDFKit
import SwiftUI

struct CoverLetterPDFGenerator {
    
    static func generatePDF(from coverLetter: CoverLetter, applicant: Applicant) -> Data {
        let text = buildLetterText(from: coverLetter, applicant: applicant)
        return makePDF(fromPlainText: text)
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
        \(applicant.email) | \(applicant.websites) | \(applicant.phone)
        """
    }
    
    private static func formattedToday() -> String {
        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        return df.string(from: Date())
    }
    
    private static func makePDF(fromPlainText text: String) -> Data {
        let pageSize = CGSize(width: 612, height: 792)                // U.S. Letter
        var margins = NSEdgeInsets(top: 54, left: 94, bottom: 54, right: 180)
        var fontSize: CGFloat = 11                                   // starting size
        
        func attributed(_ text: String, size: CGFloat) -> CFAttributedString {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 2
            para.paragraphSpacing = 6
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "FuturaPT-Light", size: size) ?? .systemFont(ofSize: size),
                .paragraphStyle: para
            ]
            return NSAttributedString(string: text, attributes: attrs) as CFAttributedString
        }
        
        func layOut(fontSize: CGFloat, margins: NSEdgeInsets) -> (Data, pages: Int) {
            let buf = NSMutableData()
            UIGraphicsBeginPDFContextToData(buf,
                                        CGRect(origin: .zero, size: pageSize),
                                        nil)
            guard let ctx = UIGraphicsGetCurrentContext() else { fatalError() }
            
            let attr = attributed(text, size: fontSize)
            let setter = CTFramesetterCreateWithAttributedString(attr)
            var loc: CFIndex = 0
            var pages = 0
            
            repeat {
                UIGraphicsBeginPDFPage()
                pages += 1
                let frameRect = CGRect(x: margins.left,
                                   y: margins.bottom,
                                   width: pageSize.width - margins.left - margins.right,
                                   height: pageSize.height - margins.top - margins.bottom)
                let framePath = CGPath(rect: frameRect, transform: nil)
                let frame = CTFramesetterCreateFrame(setter,
                                                 CFRange(location: loc, length: 0),
                                                 framePath, nil)
                CTFrameDraw(frame, ctx)
                let visible = CTFrameGetVisibleStringRange(frame)
                loc = visible.location + visible.length
            } while loc < attr.length
            
            UIGraphicsEndPDFContext()
            return (buf as Data, pages)
        }
        
        // Try to fit on one sheet
        var (pdf, pages) = layOut(fontSize: fontSize, margins: margins)
        if pages > 1 {
            var s = fontSize - 0.5
            while pages > 1 && s >= 9 {
                (pdf, pages) = layOut(fontSize: s, margins: margins)
                s -= 0.5
            }
            if pages > 1 {
                margins.right = 72
                (pdf, _) = layOut(fontSize: s + 0.5, margins: margins)
            }
        }
        return pdf
    }
}