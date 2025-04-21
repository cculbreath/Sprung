import AppKit
import CoreText
import Foundation
import PDFKit
import SwiftUI

enum CoverLetterPDFGenerator {
    static func generatePDF(from coverLetter: CoverLetter, applicant: Applicant) -> Data {
        print("Generating PDF from cover letter...")
        let text = buildLetterText(from: coverLetter, applicant: applicant)
        let pdfData = createPDFFromString(text, applicant: applicant)

        // Debug - save PDF to desktop
        saveDebugPDF(pdfData)

        return pdfData
    }

    private static func saveDebugPDF(_ data: Data) {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let debugPath = downloadsURL.appendingPathComponent("debug_coverletter.pdf")

        do {
            try data.write(to: debugPath)
            print("Debug PDF saved to: \(debugPath.path)")
        } catch {
            print("Error saving debug PDF: \(error)")
        }
    }

    // MARK: - Private Helpers

    private static func buildLetterText(from cover: CoverLetter, applicant: Applicant) -> String {
        // Extract just the body of the letter
        let letterContent = extractLetterBody(from: cover.content)

        return """
        \(formattedToday())

        Dear Hiring Manager,
        \(letterContent)

        Best Regards,

        \(applicant.name)

        \(applicant.phone) | \(applicant.address), \(applicant.city), \(applicant.state)
        \(applicant.email) | \(applicant.websites)
        """
    }

    /// Extract only the body of the letter, removing salutation, signature, date, etc.
    private static func extractLetterBody(from content: String) -> String {
        // First check if we have "best regards" or similar closing text
        let commonClosings = [
            "Best Regards", "Best regards", "Sincerely", "Thank you,", 
            "Thank you for your consideration,", "Regards,", "Best,", "Yours,"
        ]
        let lines = content.components(separatedBy: .newlines)
        let applicantName = "Christopher Culbreath" // Hardcoded for now

        // Find the start and end indices
        var startIndex = -1
        var endIndex = lines.count
        
        // Clean lowercase closings with case-insensitive search
        for (i, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Try to find where salutation ends
            if trimmedLine.contains("Dear") && startIndex == -1 {
                startIndex = i + 1 // Start after "Dear" line
                // Skip any blank lines after salutation
                while startIndex < lines.count && lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    startIndex += 1
                }
            }

            // Try to find where closing begins - case insensitive
            for closing in commonClosings {
                if trimmedLine.range(of: closing, options: .caseInsensitive) != nil && i > startIndex && i < endIndex {
                    endIndex = i
                    break
                }
            }

            // Also look for the name in the signature
            if trimmedLine.contains(applicantName) && i > startIndex && i < endIndex {
                endIndex = i
            }
        }

        // If we found valid start/end points
        if startIndex >= 0 && startIndex < endIndex && endIndex <= lines.count {
            let bodyLines = Array(lines[startIndex ..< endIndex])
            let bodyText = bodyLines.joined(separator: "\n")

            // Clean up common issues and preserve paragraph structure
            var cleanedText = bodyText
                .replacingOccurrences(of: "\n\n\n", with: "\n\n")  // Triple newlines to double
                .replacingOccurrences(of: "best regards", with: "", options: .caseInsensitive) // Remove any embedded closing
                .replacingOccurrences(of: "sincerely", with: "", options: .caseInsensitive) // Remove any embedded closing
                .trimmingCharacters(in: .whitespacesAndNewlines) // Trim start/end whitespace
            
            // Ensure no trailing commas at the end from partial closings
            if cleanedText.hasSuffix(",") {
                cleanedText = String(cleanedText.dropLast())
            }
            
            return cleanedText
        }

        // If extraction failed, return the original content with minimal cleanup
        return content
            .replacingOccurrences(of: "Dear Hiring Manager,", with: "")
            .replacingOccurrences(of: "Best Regards,", with: "")
            .replacingOccurrences(of: "Best regards,", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formattedToday() -> String {
        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        return df.string(from: Date())
    }

    private static func createPDFFromString(_ text: String, applicant: Applicant) -> Data {
        print("Creating high-quality vector PDF with text: \(text.count) chars")

        // Page setup
        let pageRect = NSRect(x: 0, y: 0, width: 8.5 * 72, height: 11 * 72) // Letter size
        let leftMargin: CGFloat = 1.3 * 72 // Left margin (1.3 inches)
        let rightMargin: CGFloat = 2.5 * 72 // Right margin (2.5 inches)
        let topMargin: CGFloat = 0.75 * 72 // 0.75 inches
        let bottomMargin: CGFloat = 0.75 * 72 // 0.75 inches

        // Prepare text attributes with Futura Light font
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 14.0 - 9.8 // 14pt line spacing (line height minus font size)
        paragraphStyle.paragraphSpacing = 7.0 // 7pt after paragraph spacing
        paragraphStyle.alignment = .natural

        // Register the Futura Light font from the system
        var font: NSFont?

        // Try specifically the requested font path first
        let specificFuturaLightPath = "/Library/Fonts/Futura Light.otf"
        if FileManager.default.fileExists(atPath: specificFuturaLightPath) {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: specificFuturaLightPath) as CFURL, .process, &error)
            print("Registered Futura Light from: \(specificFuturaLightPath)")
        }

        // Backup paths if primary fails
        let futuraPaths = [
            "/Library/Fonts/futuralight.ttf",
            "/System/Library/Fonts/Supplemental/Futura.ttc",
        ]

        // Register backup fonts for use
        for path in futuraPaths {
            if FileManager.default.fileExists(atPath: path) {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, &error)
            }
        }

        // Use exact font size as specified
        let initialFontSize: CGFloat = 9.8

        // Try with the specific requested font first
        if let loadedFont = NSFont(name: "Futura Light", size: initialFontSize) {
            font = loadedFont
            print("Successfully loaded Futura Light at \(initialFontSize)pt")
        } else {
            // Try other possible font names for Futura Light
            let fontNames = ["FuturaLight", "Futura-Light", "Futura"]
            for name in fontNames {
                if let loadedFont = NSFont(name: name, size: initialFontSize) {
                    font = loadedFont
                    print("Loaded alternative font: \(name) at \(initialFontSize)pt")
                    break
                }
            }
        }

        // Fallback to system font if Futura Light isn't available
        if font == nil {
            font = NSFont.systemFont(ofSize: initialFontSize)
            print("Fallback to system font at \(initialFontSize)pt")
        }

        print("Using font: \(font!.fontName)")

        // Create URL attributes for email and website with proper hyperlinking
        let linkFont = font!
        let urlAttributes: [NSAttributedString.Key: Any] = [
            .font: linkFont,
            .foregroundColor: NSColor.black, // Black text instead of blue
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.black, // Black underline instead of blue
            // No hardcoded email - we'll set proper links in createFormattedText
        ]

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font!,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle,
        ]

        // Determine how many pages we need
        var done = false
        var currentFontSize: CGFloat = initialFontSize // Use the initial font size
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

            // Create modified text with hyperlinks
            let formattedText = createFormattedText(text: text, attributes: currentAttributes, urlAttributes: urlAttributes, applicant: applicant)

            // Create a framesetter for the current attributed text
            let framesetter = CTFramesetterCreateWithAttributedString(formattedText as CFAttributedString)

            // Size constraints
            let sizeConstraints = CGSize(width: currentTextRect.width, height: CGFloat.greatestFiniteMagnitude)

            // Calculate the total height needed
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: formattedText.length),
                nil,
                sizeConstraints,
                nil
            )

            print("Suggested size: \(suggestedSize.width)x\(suggestedSize.height), text rect height: \(currentTextRect.height)")

            if suggestedSize.height <= currentTextRect.height {
                print("Text fits on one page with margins: left=\(currentLeftMargin / 72)in, right=\(currentRightMargin / 72)in")
                // Text fits on one page, create the page using direct PDF generation
                let page = createDirectPDFPage(attributedText: formattedText, pageRect: pageRect, textRect: currentTextRect)
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
        while !done && currentFontSize >= 7 {
            print("Trying font size: \(currentFontSize)")

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
            let currentFont = NSFont(name: font!.fontName, size: currentFontSize) ?? NSFont.systemFont(ofSize: currentFontSize)
            let currentAttributes = attributes.merging([.font: currentFont]) { _, new in new }
            let currentLinkAttributes = urlAttributes.merging([.font: currentFont]) { _, new in new }

            // Create formatted text with hyperlinks
            let formattedText = createFormattedText(text: text, attributes: currentAttributes, urlAttributes: currentLinkAttributes, applicant: applicant)

            // Create a framesetter
            let framesetter = CTFramesetterCreateWithAttributedString(formattedText as CFAttributedString)

            // Size constraints
            let sizeConstraints = CGSize(width: finalTextRect.width, height: CGFloat.greatestFiniteMagnitude)

            // Calculate the total height needed
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: formattedText.length),
                nil,
                sizeConstraints,
                nil
            )

            print("Suggested size with font \(currentFontSize)pt: \(suggestedSize.width)x\(suggestedSize.height), text rect height: \(finalTextRect.height)")

            if suggestedSize.height <= finalTextRect.height {
                print("Text fits on one page with font size \(currentFontSize)pt and minimum margins")
                // Text fits on one page, create the page
                let page = createDirectPDFPage(attributedText: formattedText, pageRect: pageRect, textRect: finalTextRect)
                if let page = page {
                    pdfDocument.insert(page, at: 0)
                    done = true
                } else {
                    print("Failed to create page, trying smaller font")
                }
            }

            if !done {
                // Try a smaller font size
                currentFontSize -= 0.5
            }
        }

        // If we couldn't fit on one page, create a multi-page PDF document
        if pdfDocument.pageCount == 0 {
            print("Creating multi-page PDF with minimum settings")

            // Use minimum margins and font size
            let minLeftMargin: CGFloat = 0.5 * 72
            let minRightMargin: CGFloat = 0.5 * 72
            let minFontSize: CGFloat = 7

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
            let currentLinkAttributes = urlAttributes.merging([.font: currentFont]) { _, new in new }

            // Create formatted text with hyperlinks
            let formattedText = createFormattedText(text: text, attributes: currentAttributes, urlAttributes: currentLinkAttributes, applicant: applicant)

            // Create a blank document
            let defaultPage = createSimplePDFPage(attributedText: formattedText, pageRect: pageRect, textRect: finalTextRect)
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

    /// Creates formatted text with hyperlinks for email and website
    private static func createFormattedText(text: String, attributes: [NSAttributedString.Key: Any], urlAttributes: [NSAttributedString.Key: Any], applicant: Applicant) -> NSAttributedString {
        let attributedText = NSMutableAttributedString(string: text, attributes: attributes)

        // Find and format email addresses and websites
        let emailPattern = #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#
        let urlPattern = #"(https?://)?(www\.)?[A-Za-z0-9.-]+\.(com|org|net|edu|io|dev)"#

        if let emailRegex = try? NSRegularExpression(pattern: emailPattern),
           let urlRegex = try? NSRegularExpression(pattern: urlPattern)
        {
            // Find emails
            let emailMatches = emailRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in emailMatches {
                if let range = Range(match.range, in: text) {
                    let email = String(text[range])
                    var emailAttributes = urlAttributes
                    // Create a proper email mailto link using either the detected email or the applicant's email
                    let emailToUse = email == applicant.email ? applicant.email : email
                    emailAttributes[.link] = URL(string: "mailto:\(emailToUse)")
                    attributedText.setAttributes(emailAttributes, range: match.range)
                }
            }

            // Find URLs
            let urlMatches = urlRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in urlMatches {
                if let range = Range(match.range, in: text) {
                    let urlString = String(text[range])
                    var websiteAttributes = urlAttributes
                    // Create a proper web URL using either the detected URL or the applicant's website
                    let websiteToUse = urlString == applicant.websites ? applicant.websites : urlString
                    let fullURL = websiteToUse.hasPrefix("http") ? websiteToUse : "https://\(websiteToUse)"
                    websiteAttributes[.link] = URL(string: fullURL)
                    attributedText.setAttributes(websiteAttributes, range: match.range)
                }
            }
        }

        return attributedText
    }

    /// Creates a PDF page using a direct CoreGraphics PDF creation approach
    private static func createDirectPDFPage(attributedText: NSAttributedString, pageRect: NSRect, textRect: NSRect) -> PDFPage? {
        // Create a direct PDF document
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height)

        // Create a PDF context directly
        guard let pdfContext = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!,
                                         mediaBox: &mediaBox,
                                         nil)
        else {
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
        let framePath = CGPath(rect: CGRect(x: textRect.origin.x,
                                            y: 0,
                                            width: textRect.width,
                                            height: textRect.height),
                               transform: nil)

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), framePath, nil)

        CTFrameDraw(frame, pdfContext)
        pdfContext.restoreGState()

        // End the PDF page
        pdfContext.endPage()

        // Create a PDF document from the data
        if let pdfDocument = PDFDocument(data: data as Data), pdfDocument.pageCount > 0 {
            // Return the first page of the document
            return pdfDocument.page(at: 0)
        }

        // Fallback to a simpler approach if the CoreText approach failed
        return createSimplePDFPage(attributedText: attributedText, pageRect: pageRect, textRect: textRect)
    }

    /// Creates a simple PDF page using PDFKit's built-in capabilities
    private static func createSimplePDFPage(attributedText: NSAttributedString, pageRect: NSRect, textRect: NSRect) -> PDFPage? {
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
