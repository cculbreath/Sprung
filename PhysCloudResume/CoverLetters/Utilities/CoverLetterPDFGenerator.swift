import AppKit
import CoreText
import Foundation
import PDFKit

// Removed SwiftUI import; not needed in PDF generator

enum CoverLetterPDFGenerator {
    static func generatePDF(from coverLetter: CoverLetter, applicant: Applicant) -> Data {
        print("Generating PDF from cover letter...")
        let text = buildLetterText(from: coverLetter, applicant: applicant)

        // Get signature image from the applicant profile
        let signatureImage = getSignatureImage(from: applicant)

        // Use a better PDF generation approach that guarantees vector text
        let pdfData = createPaginatedPDFFromString(text, signatureImage: signatureImage)

        // Debug - save PDF to desktop
        saveDebugPDF(pdfData)

        return pdfData
    }

    /// Retrieves the signature image from the applicant profile
    private static func getSignatureImage(from applicant: Applicant) -> NSImage? {
        guard let signatureData = applicant.profile.signatureData else {
            print("No signature image available in applicant profile")
            return nil
        }

        guard let image = NSImage(data: signatureData) else {
            print("Failed to create image from signature data")
            return nil
        }

        print("Successfully retrieved signature image: \(image.size.width)x\(image.size.height)")
        return image
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

            // Clean up common issues and collapse multiple paragraphs into single line breaks
            var cleanedText = bodyText
                .replacingOccurrences(of: "\n\n\n", with: "\n\n") // Triple newlines to double
                .replacingOccurrences(of: "best regards", with: "", options: .caseInsensitive) // Remove any embedded closing
                .replacingOccurrences(of: "sincerely", with: "", options: .caseInsensitive) // Remove any embedded closing
                .trimmingCharacters(in: .whitespacesAndNewlines) // Trim start/end whitespace
            // Collapse any double (or more) line breaks into a single newline
            cleanedText = cleanedText.replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)

            // Ensure no trailing commas at the end from partial closings
            if cleanedText.hasSuffix(",") {
                cleanedText = String(cleanedText.dropLast())
            }

            return cleanedText
        }

        // If extraction failed, return the original content with minimal cleanup
        var fallback = content
            .replacingOccurrences(of: "Dear Hiring Manager,", with: "")
            .replacingOccurrences(of: "Best Regards,", with: "")
            .replacingOccurrences(of: "Best regards,", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse any double (or more) line breaks into a single newline
        fallback = fallback.replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)
        return fallback
    }

    private static func formattedToday() -> String {
        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        return df.string(from: Date())
    }

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
    private static func createPaginatedPDFFromString(_ text: String, signatureImage: NSImage? = nil) -> Data {
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
        let signatureSpacing: CGFloat = 0.0 // Remove paragraph spacing completely between contact lines
        let contactLineSpacing: CGFloat = baseLineSpacing - 4.0 // Much tighter line spacing for contact info

        // Get the indices of the contact info lines to apply custom styling
        var addressLineRange: NSRange?
        var emailLineRange: NSRange?

        // First identify the contact lines
        let textNSString = attributedString.string as NSString
        textNSString.enumerateSubstrings(in: fullRange, options: .byParagraphs) { substring, substringRange, _, _ in
            guard let substring = substring else { return }
            let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.contains("|") {
                if trimmed.contains("@") || trimmed.contains(".com") {
                    emailLineRange = substringRange
                } else {
                    addressLineRange = substringRange
                }
            }
        }

        // Apply ultra-tight spacing between address and email lines
        if let addressRange = addressLineRange {
            let addressPS = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            addressPS.paragraphSpacing = signatureSpacing // Remove paragraph spacing after address line
            attributedString.addAttribute(.paragraphStyle, value: addressPS, range: addressRange)
        }

        // Apply tight line spacing to the email/website line
        if let emailRange = emailLineRange {
            let emailPS = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            emailPS.lineSpacing = contactLineSpacing // Much tighter line spacing
            attributedString.addAttribute(.paragraphStyle, value: emailPS, range: emailRange)
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

            // Draw signature image if available and this is the first/only page
            if currentLocation == 0, let signatureImage = signatureImage {
                // Look for signature markers in the source text (with and without commas)
                let regardsMarkers = [
                    "Best Regards,", "Best regards,", "Best Regards", "Best regards",
                    "Sincerely,", "Sincerely", "Sincerely yours,", "Sincerely Yours",
                    "Thank you,", "Thank you",
                    "Regards,", "Regards",
                    "Warm Regards,", "Warm regards,", "Warm Regards", "Warm regards",
                    "Yours truly,", "Yours Truly,", "Yours truly", "Yours Truly",
                    "Respectfully,", "Respectfully",
                ]
                let nameMarker = "Christopher Culbreath"

                // Get all lines from the frame for proper positioning
                let frameLines = CTFrameGetLines(frame) as? [CTLine] ?? []
                var origins = Array(repeating: CGPoint.zero, count: frameLines.count)
                CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

                // Find the lines containing signature elements
                var regardsLineIndex: Int?
                var nameLineIndex: Int?
                var contactInfoLineIndex: Int? // For phone/address line
                var emailLineIndex: Int? // For email line
                var emptyLineAfterRegards: Int?

                for (idx, line) in frameLines.enumerated() {
                    let lineRange = CTLineGetStringRange(line)
                    if lineRange.length > 0 {
                        let lineStart = lineRange.location
                        let nsString = attributedString.string as NSString
                        let lineContent = nsString.substring(with: NSRange(location: lineStart, length: lineRange.length))
                        let trimmedContent = lineContent.trimmingCharacters(in: .whitespacesAndNewlines)

                        // Look for closing markers
                        for marker in regardsMarkers {
                            if trimmedContent.contains(marker) {
                                regardsLineIndex = idx

                                // Check for empty line after regards
                                if idx + 1 < frameLines.count {
                                    let nextLineRange = CTLineGetStringRange(frameLines[idx + 1])
                                    if nextLineRange.length > 0 {
                                        let nextContent = nsString.substring(with: NSRange(location: nextLineRange.location, length: nextLineRange.length))
                                        if nextContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            emptyLineAfterRegards = idx + 1
                                        }
                                    }
                                }
                                break
                            }
                        }

                        // Look for name
                        if trimmedContent.contains(nameMarker) {
                            nameLineIndex = idx
                        }

                        // Detect contact info lines (phone/address) using robust patterns
                        if trimmedContent.contains("(") || trimmedContent.contains(")") || // Capture phone number patterns
                            trimmedContent.contains("-") || // Capture phone or address patterns
                            trimmedContent.contains("Shadywood") ||
                            trimmedContent.contains("Austin") || trimmedContent.contains("Texas") ||
                            trimmedContent.contains("Drive") || trimmedContent.contains("Dr")
                        {
                            contactInfoLineIndex = idx
                        }

                        // Detect email line with robust patterns
                        if trimmedContent.contains("@") || // Universal email indicator
                            trimmedContent.contains(".net") || trimmedContent.contains(".com") || // Domain extensions
                            trimmedContent.contains("physics") || trimmedContent.contains("cloud") ||
                            trimmedContent.contains("culbreath")
                        { // Parts of common domains
                            emailLineIndex = idx
                        }
                    }
                }

                // Default positioning (fallback)
                var signatureY = textRect.origin.y + 100
                var idealPosition = false

                // Dynamically position based on what we found
                if let nameIdx = nameLineIndex, nameIdx < origins.count {
                    if let regardsIdx = regardsLineIndex, regardsIdx < origins.count {
                        // Position between "Best Regards" and name - ideal case
                        if nameIdx > regardsIdx + 1 {
                            // Get the midpoint between regards and name
                            let regardsY = origins[regardsIdx].y
                            let nameY = origins[nameIdx].y
                            // Position signature between regards and name with proper spacing
                            signatureY = (regardsY + nameY) / 2
                            idealPosition = true
                        } else {
                            // Regards and name are adjacent - position closely above name
                            signatureY = origins[nameIdx].y + 20
                        }
                    } else {
                        // Only name found - position above name
                        signatureY = origins[nameIdx].y + 20
                    }
                } else if let regardsIdx = regardsLineIndex, regardsIdx < origins.count {
                    // Only "Best Regards" found - position after it
                    signatureY = origins[regardsIdx].y - 35
                }

                // Use a single fixed height for the signature, regardless of other parameters
                // This provides consistent sizing across all documents
                let signatureHeight: CGFloat = 28.0 // Fixed signature height for consistency
                let imageAspectRatio = signatureImage.size.width / signatureImage.size.height
                let signatureWidth = signatureHeight * imageAspectRatio

                // Determine the right position based on the content
                var signatureX = textRect.origin.x + 2 // Default indent from margin

                // Position signature intelligently based on all detected signature elements

                // Determine where there's space to place the signature
                let hasContactLines = contactInfoLineIndex != nil || emailLineIndex != nil
                let betweenRegardsAndName = regardsLineIndex != nil && nameLineIndex != nil &&
                    (nameLineIndex ?? 0) > (regardsLineIndex ?? 0) &&
                    abs((nameLineIndex ?? 0) - (regardsLineIndex ?? 0)) > 1

                // First, calculate optimal signature position
                var adjustedSignatureY: CGFloat

                // Check if we have both regards and name lines for optimal positioning
                if let regardsIdx = regardsLineIndex, let nameIdx = nameLineIndex,
                   regardsIdx < origins.count, nameIdx < origins.count
                {
                    // We have both regards and name - position precisely between them
                    let regardsY = origins[regardsIdx].y
                    let nameY = origins[nameIdx].y

                    // Position EXTREMELY high right at the regards line
                    // The signature needs to appear almost at the same line as the closing text
                    if nameIdx == regardsIdx + 1 {
                        // Name immediately follows regards - place directly on the regards line
                        adjustedSignatureY = regardsY + 5 // Right on the regards line
                        print("regards + 5a")
                    } else if nameIdx == regardsIdx + 2 {
                        // One line gap - still place directly on the regards line
                        adjustedSignatureY = regardsY + 2
                        print("regards + 3b")
                    } else {
                        // Multiple lines - still position right at regards line
                        adjustedSignatureY = regardsY + 2
                        print("regards + 2")
                    }
                } else if let regardsIdx = regardsLineIndex, regardsIdx < origins.count {
                    // Only have regards line - position right ON the regards line
                    adjustedSignatureY = origins[regardsIdx].y + 5 // Right on the regards line
                    print("origins[regardsIdx].y + 5")
                } else if let nameIdx = nameLineIndex, nameIdx < origins.count {
                    // Only have name - position much higher than before
                    adjustedSignatureY = origins[nameIdx].y + 45 // Far above name
                    print("origns[nameIdx].y + 45")
                } else {
                    // No clear positioning guidance, use safe default
                    adjustedSignatureY = textRect.origin.y + 100
                    print("wtf sig")
                }

                // Now check for overlaps with contact info
                if hasContactLines {
                    // Make sure we're not overlapping contact lines
                    if let contactIdx = contactInfoLineIndex, contactIdx < origins.count {
                        let contactY = origins[contactIdx].y

                        // If signature would overlap with contact info, adjust position
                        if abs(adjustedSignatureY - contactY) < signatureHeight {
                            // Move signature up significantly to avoid contact info
                            if let nameIdx = nameLineIndex, nameIdx < origins.count {
                                adjustedSignatureY = origins[nameIdx].y + 26 // Well above name line
                                print("contacts orgins + 26")
                            } else if let regardsIdx = regardsLineIndex, regardsIdx < origins.count {
                                adjustedSignatureY = origins[regardsIdx].y - 26 // Well below regards
                                print("regards origins - 26")
                            }
                        }
                    }
                }

                // Create the final signature rectangle
                // Create signature rectangle with fixed height and proportional width
                let signatureRect = CGRect(
                    x: signatureX,
                    y: adjustedSignatureY, // Position directly at calculated Y without offset
                    width: signatureWidth, // Use natural width based on aspect ratio
                    height: signatureHeight // Fixed height for consistency
                )

                // Draw the signature
                if let cgImage = signatureImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    // Apply slight scaling based on available space
                    pdfContext.saveGState()

                    // Draw with slight transparency to ensure it doesn't overwhelm the document
                    pdfContext.setAlpha(0.95)
                    pdfContext.draw(cgImage, in: signatureRect)
                    pdfContext.restoreGState()

                    // Detailed debug info about signature placement
                    print("Signature image drawn: size=\(signatureWidth)x\(signatureHeight), position=(\(signatureRect.origin.x),\(signatureRect.origin.y))")
                    print("Placement info: regardsLine=\(regardsLineIndex ?? -1), nameLine=\(nameLineIndex ?? -1), contactLine=\(contactInfoLineIndex ?? -1), emailLine=\(emailLineIndex ?? -1)")
                }
            }

            pdfContext.restoreGState()
            pdfContext.endPage()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentLocation += visibleRange.length
        }

        pdfContext.closePDF()
        return data as Data
    }
}
