import AppKit
import CoreText
import Foundation
import PDFKit

// Removed SwiftUI import; not needed in PDF generator

enum CoverLetterPDFGenerator {
    static func generatePDF(from coverLetter: CoverLetter, applicant: Applicant) -> Data {
        print("Generating PDF from cover letter...")
        let text = buildLetterText(from: coverLetter, applicant: applicant)

        // Use a better PDF generation approach that guarantees vector text
        let pdfData = createPaginatedPDFFromString(text)

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

        // Create explicit signature block with tighter contact info spacing
        let signatureBlock = """
        Best Regards,

        \(applicant.name)
        \(applicant.phone) | \(applicant.address), \(applicant.city), \(applicant.state)
        \(applicant.email) | \(applicant.websites)
        """

        return """
        \(formattedToday())
        Dear Hiring Manager,
        \(letterContent)
        \(signatureBlock)
        """
    }

    /// Extract only the body of the letter, removing salutation, signature, date, etc.
    static func extractLetterBody(from content: String) -> String {
        // First check if we have "best regards" or similar closing text
        let commonClosings = [
            "Best Regards", "Best regards", "Sincerely", "Thank you,",
            "Thank you for your consideration,", "Regards,", "Best,", "Yours,",
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
                .replacingOccurrences(of: "\n\n\n", with: "\n\n") // Triple newlines to double
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

    #if false // hide old PDF generation helpers

        private static func createPDFFromString(_ text: String, applicant: Applicant) -> Data {
            print("Creating high-quality vector PDF with text: \(text.count) chars")

            // Page setup - use exact measurements that match desired output
            let pageRect = NSRect(x: 0, y: 0, width: 8.5 * 72, height: 11 * 72) // Letter size
            // Fixed margins - don't auto-adjust these!
            let leftMargin: CGFloat = 1.3 * 72 // Left margin (1.3 inches)
            let rightMargin: CGFloat = 2.5 * 72 // Right margin (2.5 inches)
            let topMargin: CGFloat = 0.75 * 72 // 0.75 inches
            let bottomMargin: CGFloat = 0.5 * 72 // Reduced bottom margin to ensure contact info is visible

            // Prepare text attributes with Futura Light font
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 11.5 - 9.8 // 11.5pt line spacing (reduced further for exact match)
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
            // IMPORTANT: These must be entirely black, not blue!
            let urlAttributes: [NSAttributedString.Key: Any] = [
                .font: linkFont,
                .foregroundColor: NSColor.black, // MUST be black text
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor.black, // MUST be black underline
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

            // Skip margin adjustments and use exact specified margins
            // Only one attempt with the exact margins we specified
            do {
                print("Using fixed margins: left=\(leftMargin / 72)in, right=\(rightMargin / 72)in")

                // Use exact text rectangle with our specified margins
                let currentTextRect = NSRect(
                    x: leftMargin,
                    y: bottomMargin,
                    width: pageRect.width - leftMargin - rightMargin,
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

                // Always create the page with our fixed margins, even if the text doesn't fit perfectly
                print("Creating PDF page with fixed margins: left=\(leftMargin / 72)in, right=\(rightMargin / 72)in")

                // ONLY use direct vector PDF generation - NEVER fall back to image-based rendering
                let page = createDirectPDFPage(attributedText: formattedText, pageRect: pageRect, textRect: currentTextRect)
                if let page = page {
                    pdfDocument.insert(page, at: 0)
                    done = true
                    print("Successfully created vector PDF page with fixed margins")
                } else {
                    print("First attempt failed, retrying direct PDF generation with stronger settings")
                    // Try once more with direct PDF generation, never fall back to image rendering
                    let retryFormattedText = forceBlackHyperlinks(attributedText: formattedText)
                    if let retryPage = createDirectPDFPage(attributedText: retryFormattedText, pageRect: pageRect, textRect: currentTextRect) {
                        pdfDocument.insert(retryPage, at: 0)
                        done = true
                        print("Successfully created vector PDF page on retry")
                    } else {
                        print("Failed on retry - PDF creation issues")
                    }
                }

                // Exit the do block - we're done trying
            }

            // Skip the margin and font size adjustment, just use fixed settings
            /* Disabled auto-adjustment code - we want fixed margins and font size
             // Auto-adjustment code was previously here
             */

            // If we still couldn't create a PDF, make one last attempt with direct vector rendering
            if pdfDocument.pageCount == 0 {
                print("Creating last-resort PDF with fixed settings (still using vector text)")

                // Use the same fixed margins and font
                let textRect = NSRect(
                    x: leftMargin,
                    y: bottomMargin,
                    width: pageRect.width - leftMargin - rightMargin,
                    height: pageRect.height - topMargin - bottomMargin
                )

                // Create attributes with our fixed font size
                let currentAttributes = attributes

                // Create formatted text with hyperlinks
                let formattedText = createFormattedText(text: text, attributes: currentAttributes, urlAttributes: urlAttributes, applicant: applicant)

                // Force all hyperlinks to be black
                let forcedBlackText = forceBlackHyperlinks(attributedText: formattedText)

                // Create a direct vector PDF page - NEVER use the image-based fallback
                let defaultPage = createDirectPDFPage(attributedText: forcedBlackText, pageRect: pageRect, textRect: textRect)
                if let page = defaultPage {
                    pdfDocument.insert(page, at: 0)
                    print("Created vector text PDF as last resort")
                } else {
                    print("WARNING: All PDF generation attempts failed!")
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

                        // Make a copy of urlAttributes with black text and underline
                        var emailAttributes = urlAttributes

                        // Force black color for email links
                        emailAttributes[.foregroundColor] = NSColor.black
                        emailAttributes[.underlineColor] = NSColor.black

                        // Create a proper email mailto link using either the detected email or the applicant's email
                        let emailToUse = email == applicant.email ? applicant.email : email
                        emailAttributes[.link] = URL(string: "mailto:\(emailToUse)")

                        // Apply these black settings
                        attributedText.setAttributes(emailAttributes, range: match.range)
                    }
                }

                // Find URLs
                let urlMatches = urlRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in urlMatches {
                    if let range = Range(match.range, in: text) {
                        let urlString = String(text[range])

                        // Make a copy of urlAttributes with black text and underline
                        var websiteAttributes = urlAttributes

                        // Force black color for website links
                        websiteAttributes[.foregroundColor] = NSColor.black
                        websiteAttributes[.underlineColor] = NSColor.black

                        // Create a proper web URL using either the detected URL or the applicant's website
                        let websiteToUse = urlString == applicant.websites ? applicant.websites : urlString
                        let fullURL = websiteToUse.hasPrefix("http") ? websiteToUse : "https://\(websiteToUse)"
                        websiteAttributes[.link] = URL(string: fullURL)

                        // Apply these black settings
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
//        pdfContext.translateBy(x: 0, y: pageRect.height)
//        pdfContext.scaleBy(x: 1.0, y: -1.0)

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

            // Don't fall back to image-based rendering - just return nil and let the caller try again
            // with different settings
            print("Direct PDF generation failed - no fallback to image rendering")
            return nil
        }

        /// Creates a simple PDF page using PDFKit's built-in capabilities - AVOID USING THIS
        private static func createSimplePDFPage(attributedText: NSAttributedString, pageRect: NSRect, textRect: NSRect) -> PDFPage? {
            // THIS METHOD CREATES RASTER IMAGES INSTEAD OF VECTOR TEXT - AVOID IF POSSIBLE

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

        /// Force all hyperlinks to be black, regardless of default system behavior
        private static func forceBlackHyperlinks(attributedText: NSAttributedString) -> NSAttributedString {
            let result = NSMutableAttributedString(attributedString: attributedText)

            // Find all hyperlinks and force them to be black
            attributedText.enumerateAttribute(.link, in: NSRange(location: 0, length: attributedText.length)) { value, range, _ in
                if value != nil {
                    // Force black color for all link text
                    result.addAttribute(.foregroundColor, value: NSColor.black, range: range)
                    result.addAttribute(.underlineColor, value: NSColor.black, range: range)
                    // Ensure links are underlined
                    result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
            }

            return result
        }

    #endif // end hiding old PDF generation helpers
    /// Creates a PDF with guaranteed vector text using NSAttributedString and PDFKit
    private static func createVectorPDFFromString(_ text: String) -> Data {
        print("Creating vector PDF from text using PDFKit...")

        // Page setup with our preferred margins
        let pageRect = CGRect(x: 0, y: 0, width: 8.5 * 72, height: 11 * 72) // Letter size
        let leftMargin: CGFloat = 1.3 * 72 // Left margin (1.3 inches)
        let rightMargin: CGFloat = 2.5 * 72 // Right margin (2.5 inches)
        let topMargin: CGFloat = 0.75 * 72 // Top margin (0.75 inches)
        let bottomMargin: CGFloat = 0.5 * 72 // Bottom margin (0.5 inches)

        // Set up text rectangle
        let textRect = CGRect(
            x: leftMargin,
            y: bottomMargin,
            width: pageRect.width - leftMargin - rightMargin,
            height: pageRect.height - topMargin - bottomMargin
        )

        // Prepare paragraph style with exact spacing requirements
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 11.5 - 9.8 // 11.5pt line spacing
        paragraphStyle.paragraphSpacing = 7.0 // 7pt after paragraph spacing
        paragraphStyle.alignment = .natural

        // Set up Futura Light font
        var font: NSFont?
        let fontSize: CGFloat = 9.8

        // Try to load the font
        if let loadedFont = NSFont(name: "Futura Light", size: fontSize) {
            font = loadedFont
            print("Using existing Futura Light font at \(fontSize)pt")
        } else {
            // Try registering Futura Light from the specific path
            let specificFuturaLightPath = "/Library/Fonts/Futura Light.otf"
            if FileManager.default.fileExists(atPath: specificFuturaLightPath) {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: specificFuturaLightPath) as CFURL, .process, &error)
                print("Registered Futura Light for vector PDF")

                // Try loading the font again after registration
                if let loadedFont = NSFont(name: "Futura Light", size: fontSize) {
                    font = loadedFont
                } else {
                    // Fallback to system font
                    font = NSFont.systemFont(ofSize: fontSize)
                    print("Falling back to system font at \(fontSize)pt")
                }
            } else {
                // Fallback to system font
                font = NSFont.systemFont(ofSize: fontSize)
                print("Falling back to system font at \(fontSize)pt - Font not found")
            }
        }

        // Create base text attributes
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font!,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle,
        ]

        // Create link attributes with BLACK links (which is key!)
        let urlAttributes: [NSAttributedString.Key: Any] = [
            .font: font!,
            .foregroundColor: NSColor.black,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.black,
        ]

        // Create initial attributed string
        let attributedString = NSMutableAttributedString(string: text, attributes: attributes)

        // Find and format hyperlinks
        let emailPattern = #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#
        let urlPattern = #"(https?://)?(www\.)?[A-Za-z0-9.-]+\.(com|org|net|edu|io|dev)"#

        if let emailRegex = try? NSRegularExpression(pattern: emailPattern),
           let urlRegex = try? NSRegularExpression(pattern: urlPattern)
        {
            // Find and format emails
            let emailMatches = emailRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in emailMatches {
                if let range = Range(match.range, in: text) {
                    let email = String(text[range])
                    var linkAttrs = urlAttributes
                    linkAttrs[.link] = URL(string: "mailto:\(email)")
                    attributedString.setAttributes(linkAttrs, range: match.range)
                    print("Added mailto link for: \(email)")
                }
            }

            // Find and format URLs
            let urlMatches = urlRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in urlMatches {
                if let range = Range(match.range, in: text) {
                    let urlString = String(text[range])
                    var linkAttrs = urlAttributes
                    let fullURL = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
                    linkAttrs[.link] = URL(string: fullURL)
                    attributedString.setAttributes(linkAttrs, range: match.range)
                    print("Added http link for: \(urlString)")
                }
            }
        }

        // Create a proper PDF context for macOS
        let pdfMetaData = [
            kCGPDFContextCreator: "Physics Cloud Resume" as CFString,
            kCGPDFContextTitle: "Cover Letter" as CFString,
        ]

        let data = NSMutableData()
        var mediaBox = pageRect

        // Create a PDF context directly using CGContext
        guard let pdfContext = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!,
                                         mediaBox: &mediaBox,
                                         pdfMetaData as CFDictionary)
        else {
            print("Failed to create PDF context")
            return Data()
        }

        // Begin a PDF page
        pdfContext.beginPage(mediaBox: &mediaBox)

        // Fill with white background
        pdfContext.setFillColor(NSColor.white.cgColor)
        pdfContext.fill(mediaBox)

        // Flip for proper text orientation (PDF has bottom-left origin)
        pdfContext.saveGState()
//        pdfContext.translateBy(x: 0, y: pageRect.height)
//        pdfContext.scaleBy(x: 1.0, y: -1.0)

        // Create frame for the text
        let framePath = CGPath(rect: CGRect(x: textRect.origin.x,
                                            y: textRect.origin.y, // Position at the top after flipping
                                            width: textRect.width,
                                            height: textRect.height),
                               transform: nil)

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), framePath, nil)

        // Draw the text
        CTFrameDraw(frame, pdfContext)

        // Restore graphics state and end the page
        pdfContext.restoreGState()
        pdfContext.endPage()
        pdfContext.closePDF()

        // Create the final PDF document
        if let pdfDoc = PDFDocument(data: data as Data), pdfDoc.pageCount > 0 {
            print("Successfully created vector PDF with \(pdfDoc.pageCount) pages and size: \(data.length) bytes")
            return data as Data
        }

        print("Failed to create vector PDF - trying alternate approach")

        // Last resort: Direct PDF drawing with CGContext
        print("Using direct PDF drawing with CGContext...")

        // Create a PDF context
        let pdfData = NSMutableData()
        var pdfMediaBox = pageRect

        guard let pdfContext = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                         mediaBox: &pdfMediaBox,
                                         nil)
        else {
            print("Failed to create direct PDF context")
            return Data()
        }

        // Begin PDF page
        pdfContext.beginPage(mediaBox: &pdfMediaBox)

        // Fill with white background
        pdfContext.setFillColor(NSColor.white.cgColor)
        pdfContext.fill(pdfMediaBox)

        // Set up for text rendering
        pdfContext.saveGState()
//        pdfContext.translateBy(x: 0, y: pageRect.height)
//        pdfContext.scaleBy(x: 1.0, y: -1.0)

        // Draw text using Core Text for proper vector text
        let pathForText = CGPath(rect: CGRect(x: textRect.origin.x,
                                              y: textRect.origin.y,
                                              width: textRect.width,
                                              height: textRect.height),
                                 transform: nil)

        let textFramesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        let textFrame = CTFramesetterCreateFrame(textFramesetter, CFRangeMake(0, 0), pathForText, nil)

        // Draw the text
        CTFrameDraw(textFrame, pdfContext)

        // Clean up
        pdfContext.restoreGState()
        pdfContext.endPage()
        pdfContext.closePDF()

        // Get PDF data
        if pdfData.length > 0 {
            print("Created direct vector PDF with size: \(pdfData.length)")
            return pdfData as Data
        }

        print("All PDF generation methods failed")
        return Data()
    }

    /// Paginated vector PDF generation using CoreText framesetter
    private static func createPaginatedPDFFromString(_ text: String) -> Data {
        // Register and log Futura Light font file usage
        let specificFuturaPath = "/Library/Fonts/Futura Light.otf"
        var registeredFontFilePath: String? = nil
        if FileManager.default.fileExists(atPath: specificFuturaPath) {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: specificFuturaPath) as CFURL, .process, &error)
            registeredFontFilePath = specificFuturaPath
        } else {
            let futuraPaths = [
                "/Library/Fonts/futuralight.ttf",
                "/System/Library/Fonts/Supplemental/Futura.ttc",
            ]
            for path in futuraPaths {
                if FileManager.default.fileExists(atPath: path) {
                    var error: Unmanaged<CFError>?
                    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, &error)
                    registeredFontFilePath = path
                    break
                }
            }
        }
        if let path = registeredFontFilePath {
            print("Using Futura Light font from file: \(path)")
        } else {
            print("No Futura Light font file found, relying on system fonts")
        }

        // Auto-fit settings
        let pageRect = CGRect(x: 0, y: 0, width: 8.5 * 72, height: 11 * 72)
        let defaultLeftMargin: CGFloat = 1.3 * 72
        let defaultRightMargin: CGFloat = 2.5 * 72
        let topMargin: CGFloat = 0.75 * 72
        let bottomMargin: CGFloat = 0.5 * 72
        let minMargin: CGFloat = 0.75 * 72
        let marginStep: CGFloat = 0.1 * 72
        let initialFontSize: CGFloat = 9.8
        let minFontSize: CGFloat = 8.5
        let fontStep: CGFloat = 0.1
        let baseLineSpacing: CGFloat = 11.5 - initialFontSize

        // Helper to count pages for given layout
        func pageCount(fontSize: CGFloat, leftMargin: CGFloat, rightMargin: CGFloat) -> Int {
            let paragraphStyleTest = NSMutableParagraphStyle()
            paragraphStyleTest.lineSpacing = baseLineSpacing
            paragraphStyleTest.paragraphSpacing = 7.0
            paragraphStyleTest.alignment = .natural

            let testFont = NSFont(name: "Futura Light", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let testAttributes: [NSAttributedString.Key: Any] = [
                .font: testFont,
                .paragraphStyle: paragraphStyleTest,
            ]
            let testString = NSMutableAttributedString(string: text, attributes: testAttributes)

            let framesetter = CTFramesetterCreateWithAttributedString(testString as CFAttributedString)
            var count = 0
            var currentLoc = 0
            let frameRect = CGRect(x: leftMargin,
                                   y: bottomMargin,
                                   width: pageRect.width - leftMargin - rightMargin,
                                   height: pageRect.height - topMargin - bottomMargin)
            let framePath = CGPath(rect: frameRect, transform: nil)
            while currentLoc < testString.length {
                let frame = CTFramesetterCreateFrame(framesetter,
                                                     CFRange(location: currentLoc, length: 0),
                                                     framePath,
                                                     nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { break }
                currentLoc += visible.length
                count += 1
                if count > 1 { break }
            }
            return count
        }

        // Determine best margins and font size
        var chosenFontSize = initialFontSize
        var chosenLeft = defaultLeftMargin
        var chosenRight = defaultRightMargin
        var fitsOne = false

        // Try reducing margins
        var testLeft = defaultLeftMargin
        var testRight = defaultRightMargin
        while testLeft > minMargin || testRight > minMargin {
            testLeft = max(testLeft - marginStep, minMargin)
            testRight = max(testRight - marginStep, minMargin)
            if pageCount(fontSize: initialFontSize, leftMargin: testLeft, rightMargin: testRight) <= 1 {
                chosenLeft = testLeft
                chosenRight = testRight
                fitsOne = true
                break
            }
        }

        // Try reducing font size if needed
        if !fitsOne {
            testLeft = minMargin
            testRight = minMargin
            var testFontSize = initialFontSize
            while testFontSize > minFontSize {
                testFontSize = max(testFontSize - fontStep, minFontSize)
                if pageCount(fontSize: testFontSize, leftMargin: testLeft, rightMargin: testRight) <= 1 {
                    chosenFontSize = testFontSize
                    chosenLeft = testLeft
                    chosenRight = testRight
                    fitsOne = true
                    break
                }
                if testFontSize == minFontSize { break }
            }
        }

        // Restore defaults if still too long
        if !fitsOne {
            chosenFontSize = initialFontSize
            chosenLeft = defaultLeftMargin
            chosenRight = defaultRightMargin
        }

        // Build final attributed string
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseLineSpacing
        paragraphStyle.paragraphSpacing = 7.0
        paragraphStyle.alignment = .natural

        let finalFont = NSFont(name: "Futura Light", size: chosenFontSize) ?? NSFont.systemFont(ofSize: chosenFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: finalFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle,
        ]
        let urlAttributes: [NSAttributedString.Key: Any] = [
            .font: finalFont,
            .foregroundColor: NSColor.black,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.black,
        ]
        let attributedString = NSMutableAttributedString(string: text, attributes: attributes)
        let fullRange = NSRange(location: 0, length: attributedString.length)
        // Email & URL regex
        let emailPattern = #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#
        let urlPattern = #"(https?://)?(www\.)?[A-Za-z0-9.-]+\.(com|org|net|edu|io|dev)"#
        if let emailRegex = try? NSRegularExpression(pattern: emailPattern),
           let urlRegex = try? NSRegularExpression(pattern: urlPattern)
        {
            emailRegex.enumerateMatches(in: attributedString.string, options: [], range: fullRange) { match, _, _ in
                if let match = match {
                    let email = (attributedString.string as NSString).substring(with: match.range)
                    var attrs = urlAttributes
                    attrs[.link] = URL(string: "mailto:\(email)")
                    attributedString.addAttributes(attrs, range: match.range)
                }
            }
            urlRegex.enumerateMatches(in: attributedString.string, options: [], range: fullRange) { match, _, _ in
                if let match = match {
                    let urlString = (attributedString.string as NSString).substring(with: match.range)
                    var attrs = urlAttributes
                    let fullURL = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
                    attrs[.link] = URL(string: fullURL)
                    attributedString.addAttributes(attrs, range: match.range)
                }
            }
        }

        // Adjust signature block spacing: reduce paragraphSpacing for contact lines
        let signatureSpacing: CGFloat = 4.0
        let textNSString = attributedString.string as NSString
        textNSString.enumerateSubstrings(in: fullRange, options: .byParagraphs) { substring, substringRange, _, _ in
            guard let substring = substring else { return }
            let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("|") {
                let newPS = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
                newPS.paragraphSpacing = signatureSpacing
                attributedString.addAttribute(.paragraphStyle, value: newPS, range: substringRange)
            }
        }

        // Setup PDF context
        let data = NSMutableData()
        let pdfMetaData = [
            kCGPDFContextCreator: "Physics Cloud Resume" as CFString,
            kCGPDFContextTitle: "Cover Letter" as CFString,
        ] as CFDictionary
        var mediaBoxCopy = pageRect
        guard let pdfContext = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!,
                                         mediaBox: &mediaBoxCopy,
                                         pdfMetaData)
        else {
            return Data()
        }

        // Text container for drawing
        let textRect = CGRect(x: chosenLeft,
                              y: bottomMargin,
                              width: pageRect.width - chosenLeft - chosenRight,
                              height: pageRect.height - topMargin - bottomMargin)

        // Paginate using CoreText
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        var currentLocation = 0
        let totalLength = attributedString.length
        while currentLocation < totalLength {
            pdfContext.beginPage(mediaBox: &mediaBoxCopy)
            pdfContext.setFillColor(NSColor.white.cgColor)
            pdfContext.fill(mediaBoxCopy)
            pdfContext.saveGState()

            let framePath = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter,
                                                 CFRange(location: currentLocation, length: 0),
                                                 framePath,
                                                 nil)
            CTFrameDraw(frame, pdfContext)
            pdfContext.restoreGState()
            pdfContext.endPage()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentLocation += visibleRange.length
        }

        pdfContext.closePDF()
        return data as Data
    }
}
