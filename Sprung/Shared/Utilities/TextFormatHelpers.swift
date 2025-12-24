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
        let cleanTitle = HTMLUtility.stripTags(title).uppercased()
        let titleLength = cleanTitle.count
        let totalDashes = width - titleLength - 4 // 4 accounts for the '*' and spaces around the title
        let leftDashes = totalDashes / 2
        let rightDashes = totalDashes - leftDashes
        return "*\(String(repeating: "-", count: leftDashes)) \(cleanTitle) \(String(repeating: "-", count: rightDashes))*"
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
}
