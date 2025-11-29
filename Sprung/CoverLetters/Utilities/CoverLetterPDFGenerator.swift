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
    // MARK: - PDF Layout Configuration
    private struct PDFLayoutConfig {
        let pageRect: CGRect
        let topMargin: CGFloat
        let bottomMargin: CGFloat
        let defaultLeftMargin: CGFloat
        let defaultRightMargin: CGFloat
        let minMargin: CGFloat
        let marginStep: CGFloat
        let initialFontSize: CGFloat
        let minFontSize: CGFloat
        let fontStep: CGFloat
        let baseLineSpacing: CGFloat
        static let standard = PDFLayoutConfig(
            pageRect: CGRect(x: 0, y: 0, width: 8.5 * 72, height: 11 * 72),
            topMargin: 0.75 * 72,
            bottomMargin: 0.5 * 72,
            defaultLeftMargin: 1.3 * 72,
            defaultRightMargin: 2.5 * 72,
            minMargin: 0.75 * 72,
            marginStep: 0.1 * 72,
            initialFontSize: 9.8,
            minFontSize: 8.5,
            fontStep: 0.1,
            baseLineSpacing: 11.5 - 9.8
        )
    }
    private struct ChosenLayout {
        let fontSize: CGFloat
        let leftMargin: CGFloat
        let rightMargin: CGFloat
    }
    // MARK: - Font Registration
    private static func registerFuturaFont() {
        let specificFuturaPath = "/Library/Fonts/Futura Light.otf"
        if FileManager.default.fileExists(atPath: specificFuturaPath) {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: specificFuturaPath) as CFURL, .process, &error)
        } else {
            let futuraPaths = [
                "/Library/Fonts/futuralight.ttf",
                "/System/Library/Fonts/Supplemental/Futura.ttc"
            ]
            for path in futuraPaths where FileManager.default.fileExists(atPath: path) {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, &error)
                break
            }
        }
    }
    // MARK: - Layout Calculation
    private static func calculatePageCount(
        text: String,
        fontSize: CGFloat,
        leftMargin: CGFloat,
        rightMargin: CGFloat,
        config: PDFLayoutConfig
    ) -> Int {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = config.baseLineSpacing
        paragraphStyle.paragraphSpacing = 7.0
        paragraphStyle.alignment = .natural
        let testFont = NSFont(name: "Futura Light", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let testAttributes: [NSAttributedString.Key: Any] = [
            .font: testFont,
            .paragraphStyle: paragraphStyle
        ]
        let testString = NSMutableAttributedString(string: text, attributes: testAttributes)
        let framesetter = CTFramesetterCreateWithAttributedString(testString as CFAttributedString)
        var count = 0
        var currentLoc = 0
        let frameRect = CGRect(
            x: leftMargin,
            y: config.bottomMargin,
            width: config.pageRect.width - leftMargin - rightMargin,
            height: config.pageRect.height - config.topMargin - config.bottomMargin
        )
        let framePath = CGPath(rect: frameRect, transform: nil)
        while currentLoc < testString.length {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: currentLoc, length: 0), framePath, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            currentLoc += visible.length
            count += 1
            if count > 1 { break }
        }
        return count
    }
    private static func determineOptimalLayout(for text: String, config: PDFLayoutConfig) -> ChosenLayout {
        // Try reducing margins first
        var testLeft = config.defaultLeftMargin
        var testRight = config.defaultRightMargin
        while testLeft > config.minMargin || testRight > config.minMargin {
            testLeft = max(testLeft - config.marginStep, config.minMargin)
            testRight = max(testRight - config.marginStep, config.minMargin)
            if calculatePageCount(text: text, fontSize: config.initialFontSize,
                                  leftMargin: testLeft, rightMargin: testRight, config: config) <= 1 {
                return ChosenLayout(fontSize: config.initialFontSize, leftMargin: testLeft, rightMargin: testRight)
            }
        }
        // Try reducing font size
        testLeft = config.minMargin
        testRight = config.minMargin
        var testFontSize = config.initialFontSize
        while testFontSize > config.minFontSize {
            testFontSize = max(testFontSize - config.fontStep, config.minFontSize)
            if calculatePageCount(text: text, fontSize: testFontSize,
                                  leftMargin: testLeft, rightMargin: testRight, config: config) <= 1 {
                return ChosenLayout(fontSize: testFontSize, leftMargin: testLeft, rightMargin: testRight)
            }
            if testFontSize == config.minFontSize { break }
        }
        // Return defaults if nothing fits on one page
        return ChosenLayout(fontSize: config.initialFontSize,
                            leftMargin: config.defaultLeftMargin,
                            rightMargin: config.defaultRightMargin)
    }
    // MARK: - Attributed String Building
    private static func buildAttributedString(
        text: String,
        fontSize: CGFloat,
        baseLineSpacing: CGFloat
    ) -> NSMutableAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = baseLineSpacing
        paragraphStyle.paragraphSpacing = 7.0
        paragraphStyle.alignment = .natural
        let font = NSFont(name: "Futura Light", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]
        let attributedString = NSMutableAttributedString(string: text, attributes: attributes)
        applyLinkStyling(to: attributedString, font: font)
        applyContactLineSpacing(to: attributedString, paragraphStyle: paragraphStyle, baseLineSpacing: baseLineSpacing)
        return attributedString
    }
    private static func applyLinkStyling(to attributedString: NSMutableAttributedString, font: NSFont) {
        let urlAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.black
        ]
        let fullRange = NSRange(location: 0, length: attributedString.length)
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
    }
    private static func applyContactLineSpacing(
        to attributedString: NSMutableAttributedString,
        paragraphStyle: NSMutableParagraphStyle,
        baseLineSpacing: CGFloat
    ) {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        var addressLineRange: NSRange?
        var emailLineRange: NSRange?
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
        if let addressRange = addressLineRange {
            let addressPS = (paragraphStyle.copy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            addressPS.paragraphSpacing = 0.0
            attributedString.addAttribute(.paragraphStyle, value: addressPS, range: addressRange)
        }
        if let emailRange = emailLineRange {
            let emailPS = (paragraphStyle.copy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            emailPS.lineSpacing = baseLineSpacing - 4.0
            attributedString.addAttribute(.paragraphStyle, value: emailPS, range: emailRange)
        }
    }
    // MARK: - Signature Positioning
    private struct SignatureLineIndices {
        var regardsLineIndex: Int?
        var nameLineIndex: Int?
        var contactInfoLineIndex: Int?
        var emailLineIndex: Int?
    }
    private static func findSignatureLineIndices(
        in frameLines: [CTLine],
        attributedString: NSMutableAttributedString,
        applicantName: String
    ) -> SignatureLineIndices {
        let regardsMarkers = [
            "Best Regards,", "Best regards,", "Best Regards", "Best regards",
            "Sincerely,", "Sincerely", "Sincerely yours,", "Sincerely Yours",
            "Thank you,", "Thank you", "Regards,", "Regards",
            "Warm Regards,", "Warm regards,", "Warm Regards", "Warm regards",
            "Yours truly,", "Yours Truly,", "Yours truly", "Yours Truly",
            "Respectfully,", "Respectfully"
        ]
        var indices = SignatureLineIndices()
        for (idx, line) in frameLines.enumerated() {
            let lineRange = CTLineGetStringRange(line)
            guard lineRange.length > 0 else { continue }
            let nsString = attributedString.string as NSString
            let lineContent = nsString.substring(with: NSRange(location: lineRange.location, length: lineRange.length))
            let trimmedContent = lineContent.trimmingCharacters(in: .whitespacesAndNewlines)
            for marker in regardsMarkers where trimmedContent.contains(marker) {
                indices.regardsLineIndex = idx
                break
            }
            if trimmedContent.contains(applicantName) {
                indices.nameLineIndex = idx
            }
            if containsLikelyPhoneNumber(trimmedContent) || containsAddressKeyword(trimmedContent) {
                indices.contactInfoLineIndex = idx
            }
            if containsEmailAddress(trimmedContent) {
                indices.emailLineIndex = idx
            }
        }
        return indices
    }
    private static func calculateSignatureY(
        indices: SignatureLineIndices,
        origins: [CGPoint],
        textRect: CGRect,
        signatureHeight: CGFloat
    ) -> CGFloat {
        var signatureY: CGFloat = textRect.origin.y + 100
        // Initial calculation based on regards/name positioning
        if let nameIdx = indices.nameLineIndex, nameIdx < origins.count {
            if let regardsIdx = indices.regardsLineIndex, regardsIdx < origins.count {
                if nameIdx > regardsIdx + 1 {
                    signatureY = (origins[regardsIdx].y + origins[nameIdx].y) / 2
                } else {
                    signatureY = origins[nameIdx].y + 20
                }
            } else {
                signatureY = origins[nameIdx].y + 20
            }
        } else if let regardsIdx = indices.regardsLineIndex, regardsIdx < origins.count {
            signatureY = origins[regardsIdx].y - 35
        }
        // Refine positioning based on line relationships
        if let regardsIdx = indices.regardsLineIndex, let nameIdx = indices.nameLineIndex,
           regardsIdx < origins.count, nameIdx < origins.count {
            let regardsY = origins[regardsIdx].y
            signatureY = regardsY + (nameIdx == regardsIdx + 1 ? 5 : 2)
        } else if let regardsIdx = indices.regardsLineIndex, regardsIdx < origins.count {
            signatureY = origins[regardsIdx].y + 5
        } else if let nameIdx = indices.nameLineIndex, nameIdx < origins.count {
            signatureY = origins[nameIdx].y + 45
        }
        // Adjust for contact info overlap
        let hasContactLines = indices.contactInfoLineIndex != nil || indices.emailLineIndex != nil
        if hasContactLines, let contactIdx = indices.contactInfoLineIndex, contactIdx < origins.count {
            let contactY = origins[contactIdx].y
            if abs(signatureY - contactY) < signatureHeight {
                if let nameIdx = indices.nameLineIndex, nameIdx < origins.count {
                    signatureY = origins[nameIdx].y + 26
                } else if let regardsIdx = indices.regardsLineIndex, regardsIdx < origins.count {
                    signatureY = origins[regardsIdx].y - 26
                }
            }
        }
        return signatureY
    }
    private static func drawSignature(
        _ signatureImage: NSImage,
        in context: CGContext,
        frame: CTFrame,
        attributedString: NSMutableAttributedString,
        applicantName: String,
        textRect: CGRect
    ) {
        let frameLines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var origins = Array(repeating: CGPoint.zero, count: frameLines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let indices = findSignatureLineIndices(in: frameLines, attributedString: attributedString, applicantName: applicantName)
        let signatureHeight: CGFloat = 28.0
        let imageAspectRatio = signatureImage.size.width / signatureImage.size.height
        let signatureWidth = signatureHeight * imageAspectRatio
        let signatureX = textRect.origin.x + 2
        let signatureY = calculateSignatureY(indices: indices, origins: origins, textRect: textRect, signatureHeight: signatureHeight)
        let signatureRect = CGRect(x: signatureX, y: signatureY, width: signatureWidth, height: signatureHeight)
        if let cgImage = signatureImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.saveGState()
            context.setAlpha(0.95)
            context.draw(cgImage, in: signatureRect)
            context.restoreGState()
        }
    }
    // MARK: - PDF Generation
    /// Paginated vector PDF generation using CoreText framesetter
    private static func createPaginatedPDFFromString(
        _ text: String,
        applicantName: String,
        signatureImage: NSImage? = nil
    ) -> Data {
        registerFuturaFont()
        let config = PDFLayoutConfig.standard
        let layout = determineOptimalLayout(for: text, config: config)
        let attributedString = buildAttributedString(text: text, fontSize: layout.fontSize, baseLineSpacing: config.baseLineSpacing)
        // Setup PDF context
        let data = NSMutableData()
        let pdfMetaData = [
            kCGPDFContextCreator: "Sprung" as CFString,
            kCGPDFContextTitle: "Cover Letter" as CFString
        ] as CFDictionary
        var mediaBox = config.pageRect
        guard let pdfContext = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!,
                                         mediaBox: &mediaBox, pdfMetaData) else {
            return Data()
        }
        let textRect = CGRect(
            x: layout.leftMargin,
            y: config.bottomMargin,
            width: config.pageRect.width - layout.leftMargin - layout.rightMargin,
            height: config.pageRect.height - config.topMargin - config.bottomMargin
        )
        // Paginate using CoreText
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        var currentLocation = 0
        let totalLength = attributedString.length
        while currentLocation < totalLength {
            pdfContext.beginPage(mediaBox: &mediaBox)
            pdfContext.setFillColor(NSColor.white.cgColor)
            pdfContext.fill(mediaBox)
            pdfContext.saveGState()
            let framePath = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: currentLocation, length: 0), framePath, nil)
            CTFrameDraw(frame, pdfContext)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            let isLastPage = (currentLocation + visibleRange.length >= totalLength)
            if isLastPage, let signatureImage = signatureImage {
                drawSignature(signatureImage, in: pdfContext, frame: frame,
                              attributedString: attributedString, applicantName: applicantName, textRect: textRect)
            }
            pdfContext.restoreGState()
            pdfContext.endPage()
            currentLocation += visibleRange.length
        }
        pdfContext.closePDF()
        return data as Data
    }
}
