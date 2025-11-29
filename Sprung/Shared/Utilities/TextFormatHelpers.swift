import Foundation
struct TextFormatHelpers {
    static func wrapper(_ text: String, width: Int = 80, leftMargin: Int = 0, rightMargin: Int = 0, centered: Bool = false, rightFill: Bool = false) -> String {
        let effectiveWidth = width - leftMargin - rightMargin
        let lines = wrapText(text, maxWidth: effectiveWidth)
        let formattedLines = lines.map { line in
            var formattedLine = String(repeating: " ", count: leftMargin) + line
            if centered {
                let totalPadding = width - line.count
                let leftPadding = totalPadding / 2
                let rightPadding = totalPadding - leftPadding
                formattedLine = String(repeating: " ", count: leftPadding) + line + String(repeating: " ", count: rightPadding)
            } else {
                if rightFill {
                    formattedLine = formattedLine.padding(toLength: width, withPad: " ", startingAt: 0)
                }
            }
            return formattedLine
        }
        return formattedLines.joined(separator: "\n")
    }
    static func joiner(_ array: [String], separator: String) -> String {
        return array.joined(separator: separator)
    }
    static func sectionLine(_ title: String, width: Int = 80) -> String {
        let cleanTitle = stripTags(title)
        let titleLength = cleanTitle.count
        let totalDashes = width - titleLength - 4 // 4 accounts for the '*' and spaces around the title
        let leftDashes = totalDashes / 2
        let rightDashes = totalDashes - leftDashes
        return "*\(String(repeating: "-", count: leftDashes)) \(cleanTitle.uppercased()) \(String(repeating: "-", count: rightDashes))*"
    }
    static func bulletText(_ text: String, marginLeft: Int = 0, width: Int = 80, bullet: String = "*") -> String {
        let bulletSpace = bullet.count + 1
        let textWidth = width - marginLeft - bulletSpace
        let lines = wrapText(text, maxWidth: textWidth)
        let formattedLines = lines.enumerated().map { index, line in
            if index == 0 {
                return "\(String(repeating: " ", count: marginLeft))\(bullet) \(line)"
            } else {
                return "\(String(repeating: " ", count: marginLeft + bulletSpace))\(line)"
            }
        }
        return formattedLines.joined(separator: "\n")
    }
    // MARK: - Helper Functions
    private static func wrapText(_ text: String, maxWidth: Int) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        var lines: [String] = []
        var currentLine = ""
        for word in words {
            let separator = currentLine.isEmpty ? "" : " "
            if (currentLine + separator + word).count <= maxWidth {
                currentLine += separator + word
            } else {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                }
                currentLine = word
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines
    }
    private static func stripTags(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html.uppercased() }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil)
        let cleaned = attributed?.string ?? html
        return cleaned.replacingOccurrences(of: "↪︎", with: "").uppercased()
    }
}
