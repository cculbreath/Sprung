//
//  HTMLUtility.swift
//  Sprung
//
//  Centralized HTML manipulation utilities.
//

import Foundation

enum HTMLUtility {
    /// Remove HTML tags from a string, returning plain text
    static func stripTags(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil)
        let cleaned = attributed?.string ?? html
        return cleaned.replacingOccurrences(of: "↪︎", with: "")
    }

    /// Remove font-face declarations that reference local file:// URLs
    /// Used by NativePDFGenerator to prevent broken font references
    static func fixFontReferences(_ template: String) -> String {
        var fixedTemplate = template

        // Remove file:// URLs for fonts since we're using system-installed fonts
        // This regex matches font-face src declarations with local file URLs
        fixedTemplate = fixedTemplate.replacingOccurrences(
            of: #"src: url\("file://[^"]+"\) format\("[^"]+"\);"#,
            with: "/* Font file removed - using system fonts */",
            options: .regularExpression
        )

        // Also remove any remaining font-face declarations that reference files
        fixedTemplate = fixedTemplate.replacingOccurrences(
            of: #"@font-face \{[^}]*url\("file://[^}]*\}"#,
            with: "/* Font-face removed - using system fonts */",
            options: .regularExpression
        )

        return fixedTemplate
    }
}
