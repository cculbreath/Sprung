//
//  CoverLetterPDFGenerator.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/20/25.
//
import AppKit
import CoreText
import Foundation
import PDFKit
// Removed SwiftUI import; not needed in PDF generator
enum CoverLetterPDFGenerator {
    static func generatePDF(from coverLetter: CoverLetter, applicant: Applicant) -> Data {
        let text = buildLetterText(from: coverLetter, applicant: applicant)
        // Get signature image from the applicant profile
        let signatureImage = getSignatureImage(from: applicant)
        // Use a better PDF generation approach that guarantees vector text
        let pdfData = createPaginatedPDFFromString(
            text,
            applicantName: applicant.name,
            signatureImage: signatureImage
        )
        return pdfData
    }
    /// Retrieves the signature image from the applicant profile
    private static func getSignatureImage(from applicant: Applicant) -> NSImage? {
        guard let signatureData = applicant.profile.signatureData else {
            return nil
        }
        guard let image = NSImage(data: signatureData) else {
            return nil
        }
        return image
    }
    // MARK: - Private Helpers
    private static func buildLetterText(from cover: CoverLetter, applicant: Applicant) -> String {
        // Extract just the body of the letter
        let letterContent = extractLetterBody(from: cover.content, applicantName: applicant.name)
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
    static func extractLetterBody(from content: String, applicantName: String) -> String {
        // First check if we have "best regards" or similar closing text
        let commonClosings = [
            "Best Regards", "Best regards", "Sincerely", "Thank you,",
            "Thank you for your consideration,", "Regards,", "Best,", "Yours,"
        ]
        let lines = content.components(separatedBy: .newlines)
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
    private static func containsLikelyPhoneNumber(_ text: String) -> Bool {
        let digitCount = text.filter { $0.isNumber }.count
        if digitCount >= 7 {
            return true
        }
        return text.range(
            of: #"(\+\d{1,3}\s)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
    private static func containsEmailAddress(_ text: String) -> Bool {
        text.range(
            of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
    private static func containsAddressKeyword(_ text: String) -> Bool {
        let keywords = [
            "street", "st.", "avenue", "ave", "road", "rd.", "boulevard", "blvd",
            "suite", "apt", "lane", "ln.", "drive", "dr.", "city", "state", "zip"
        ]
        let lowercased = text.lowercased()
        return keywords.contains(where: { lowercased.contains($0) })
    }
    /// Paginated vector PDF generation using CoreText framesetter
    private static func createPaginatedPDFFromString(
        _ text: String,
        applicantName: String,
        signatureImage: NSImage? = nil
    ) -> Data {
        // Register and log Futura Light font file usage
        let specificFuturaPath = "/Library/Fonts/Futura Light.otf"
        if FileManager.default.fileExists(atPath: specificFuturaPath) {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: specificFuturaPath) as CFURL, .process, &error)
        } else {
            let futuraPaths = [
                "/Library/Fonts/futuralight.ttf",
                "/System/Library/Fonts/Supplemental/Futura.ttc"
            ]
            for path in futuraPaths {
                if FileManager.default.fileExists(atPath: path) {
                    var error: Unmanaged<CFError>?
                    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, &error)
                    break
                }
            }
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
                .paragraphStyle: paragraphStyleTest
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
            .paragraphStyle: paragraphStyle
        ]
        let urlAttributes: [NSAttributedString.Key: Any] = [
            .font: finalFont,
            .foregroundColor: NSColor.black,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.black
        ]
        let attributedString = NSMutableAttributedString(string: text, attributes: attributes)
        let fullRange = NSRange(location: 0, length: attributedString.length)
        // Email & URL regex
        let emailPattern = #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#
        let urlPattern = #"(https?://)?(www\.)?[A-Za-z0-9.-]+\.(com|org|net|edu|io|dev)"#
        if let emailRegex = try? NSRegularExpression(pattern: emailPattern),
           let urlRegex = try? NSRegularExpression(pattern: urlPattern) {
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
            let addressPS = (paragraphStyle.copy() as? NSMutableParagraphStyle) ?? {
                let s = NSMutableParagraphStyle()
                s.setParagraphStyle(paragraphStyle)
                return s
            }()
            addressPS.paragraphSpacing = signatureSpacing // Remove paragraph spacing after address line
            attributedString.addAttribute(.paragraphStyle, value: addressPS, range: addressRange)
        }
        // Apply tight line spacing to the email/website line
        if let emailRange = emailLineRange {
            let emailPS = (paragraphStyle.copy() as? NSMutableParagraphStyle) ?? {
                let s = NSMutableParagraphStyle()
                s.setParagraphStyle(paragraphStyle)
                return s
            }()
            emailPS.lineSpacing = contactLineSpacing // Much tighter line spacing
            attributedString.addAttribute(.paragraphStyle, value: emailPS, range: emailRange)
        }
        // Setup PDF context
        let data = NSMutableData()
        let pdfMetaData = [
            kCGPDFContextCreator: "Sprung" as CFString,
            kCGPDFContextTitle: "Cover Letter" as CFString
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
            // Determine if this is the last page
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            let isLastPage = (currentLocation + visibleRange.length >= totalLength)
            // Draw signature image if available and this is the last page
            if isLastPage, let signatureImage = signatureImage {
                // Look for signature markers in the source text (with and without commas)
                let regardsMarkers = [
                    "Best Regards,", "Best regards,", "Best Regards", "Best regards",
                    "Sincerely,", "Sincerely", "Sincerely yours,", "Sincerely Yours",
                    "Thank you,", "Thank you",
                    "Regards,", "Regards",
                    "Warm Regards,", "Warm regards,", "Warm Regards", "Warm regards",
                    "Yours truly,", "Yours Truly,", "Yours truly", "Yours Truly",
                    "Respectfully,", "Respectfully"
                ]
                let nameMarker = applicantName
                // Get all lines from the frame for proper positioning
                let frameLines = CTFrameGetLines(frame) as? [CTLine] ?? []
                var origins = Array(repeating: CGPoint.zero, count: frameLines.count)
                CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
                // Find the lines containing signature elements
                var regardsLineIndex: Int?
                var nameLineIndex: Int?
                var contactInfoLineIndex: Int? // For phone/address line
                var emailLineIndex: Int? // For email line
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
                                        // Check for empty lines, but no need to track them
                                        _ = nextContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                        if containsLikelyPhoneNumber(trimmedContent) || containsAddressKeyword(trimmedContent) {
                            contactInfoLineIndex = idx
                        }
                        // Detect email line with robust patterns
                        if containsEmailAddress(trimmedContent) {
                            emailLineIndex = idx
                        }
                    }
                }
                // Default positioning (fallback)
                // Position will be calculated dynamically later
                // Dynamically position based on what we found
                var adjustedSignatureY: CGFloat = textRect.origin.y + 100 // Default fallback position
                if let nameIdx = nameLineIndex, nameIdx < origins.count {
                    if let regardsIdx = regardsLineIndex, regardsIdx < origins.count {
                        // Position between "Best Regards" and name - ideal case
                        if nameIdx > regardsIdx + 1 {
                            let regardsY = origins[regardsIdx].y
                            let nameY = origins[nameIdx].y
                            adjustedSignatureY = (regardsY + nameY) / 2
                        } else {
                            // Regards and name are adjacent - position closely above name
                            adjustedSignatureY = origins[nameIdx].y + 20
                        }
                    } else {
                        // Only name found - position above name
                        adjustedSignatureY = origins[nameIdx].y + 20
                    }
                } else if let regardsIdx = regardsLineIndex, regardsIdx < origins.count {
                    // Only "Best Regards" found - position after it
                    adjustedSignatureY = origins[regardsIdx].y - 35
                }
                // Use a single fixed height for the signature, regardless of other parameters
                // This provides consistent sizing across all documents
                let signatureHeight: CGFloat = 28.0 // Fixed signature height for consistency
                let imageAspectRatio = signatureImage.size.width / signatureImage.size.height
                let signatureWidth = signatureHeight * imageAspectRatio
                // Determine the right position based on the content
                let signatureX = textRect.origin.x + 2 // Default indent from margin
                // Determine where there's space to place the signature
                let hasContactLines = contactInfoLineIndex != nil || emailLineIndex != nil
                // Refine positioning if we have both regards and name lines
                if let regardsIdx = regardsLineIndex, let nameIdx = nameLineIndex,
                   regardsIdx < origins.count, nameIdx < origins.count {
                    let regardsY = origins[regardsIdx].y
                    if nameIdx == regardsIdx + 1 {
                        adjustedSignatureY = regardsY + 5
                    } else if nameIdx == regardsIdx + 2 {
                        adjustedSignatureY = regardsY + 2
                    } else {
                        adjustedSignatureY = regardsY + 2
                    }
                } else if let regardsIdx = regardsLineIndex, regardsIdx < origins.count {
                    adjustedSignatureY = origins[regardsIdx].y + 5
                } else if let nameIdx = nameLineIndex, nameIdx < origins.count {
                    adjustedSignatureY = origins[nameIdx].y + 45
                } else {
                    adjustedSignatureY = textRect.origin.y + 100
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
                            } else if let regardsIdx = regardsLineIndex, regardsIdx < origins.count {
                                adjustedSignatureY = origins[regardsIdx].y - 26 // Well below regards
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
                }
            }
            pdfContext.restoreGState()
            pdfContext.endPage()
            // Update current location using the visible range calculated earlier
            currentLocation += visibleRange.length
        }
        pdfContext.closePDF()
        return data as Data
    }
}
