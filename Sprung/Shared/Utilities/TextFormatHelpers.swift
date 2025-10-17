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
    
    static func jobString(_ employer: String, location: String, start: String, end: String, width: Int = 80) -> String {
        let formatDate = { (dateStr: String) -> String in
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if dateStr.isEmpty || dateStr.trimmingCharacters(in: .whitespaces) == "undefined" {
                return "Present"
            }
            
            let parts = dateStr.split(separator: "-")
            if parts.count == 2, let month = Int(parts[1]), month >= 1 && month <= 12 {
                return "\(months[month - 1]) \(parts[0])"
            }
            return dateStr
        }
        
        var strA = "\(employer) | \(location)"
        var strB = "\(formatDate(start)) – \(formatDate(end))"
        var spaceBetween = width - strA.count - strB.count
        
        if spaceBetween < 0 {
            let totalLength = strA.count + strB.count
            let excess = totalLength - width
            
            if strA.count > strB.count {
                strA = String(strA.prefix(max(strA.count - excess, 0))) + "…"
            } else {
                strB = String(strB.prefix(max(strB.count - excess, 0))) + "…"
            }
            
            spaceBetween = max(width - strA.count - strB.count, 0)
        }
        
        return "\(strA)\(String(repeating: " ", count: spaceBetween))\(strB)"
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
    
    static func formatSkillsWithIndent(_ skills: [[String: Any]], width: Int = 80, indent: Int = 3) -> String {
        var output = ""
        
        for (index, skill) in skills.enumerated() {
            guard let title = skill["title"] as? String,
                  let description = skill["description"] as? String else { continue }
            
            // Add title on its own line
            output += title + "\n"
            
            // Wrap description with hanging indent
            let wrappedLines = wrapText(description, maxWidth: width - indent)
            for line in wrappedLines {
                output += String(repeating: " ", count: indent) + line + "\n"
            }
            
            // Add blank line between skills (except after the last one)
            if index < skills.count - 1 {
                output += "\n"
            }
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func wrapBlurb(_ projects: [[String: Any]]) -> String {
        var output = ""
        
        for project in projects {
            if let title = project["title"] as? String,
               let examples = project["examples"] as? [[String: Any]] {
                // Old format: "projects-and-hobbies"
                output += "[\(title)] "
                
                for example in examples {
                    if let name = example["name"] as? String,
                       let description = example["description"] as? String {
                        output += "*\(name)* \(description) "
                    }
                }
            } else if let name = project["name"] as? String,
                      let description = project["description"] as? String {
                // New format: "projects-highlights"
                output += bulletText("\(name): \(description)", marginLeft: 0, width: 80) + "\n"
            }
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func formatFooter(_ text: String, width: Int = 80) -> String {
        // Strip HTML tags for proper length calculation
        let cleanText = stripTags(text)
        
        // If clean text fits in one line (max 74 chars to leave room for *-- and --*)
        if cleanText.count <= 74 {
            let totalDashes = width - cleanText.count - 4 // 4 for "* " and " *"
            let leftDashes = max(0, totalDashes / 2)
            let rightDashes = max(0, totalDashes - leftDashes)
            
            return "*\(String(repeating: "-", count: leftDashes)) \(cleanText) \(String(repeating: "-", count: rightDashes))*"
        } else {
            // Split into two lines at word boundary as close to half as possible
            let words = cleanText.split(separator: " ").map(String.init)
            let targetLength = cleanText.count / 2
            
            var firstLineWords: [String] = []
            var currentLength = 0
            var bestSplit = 0
            var bestDifference = Int.max
            
            for (index, word) in words.enumerated() {
                let newLength = currentLength + (firstLineWords.isEmpty ? 0 : 1) + word.count
                let difference = abs(newLength - targetLength)
                
                if difference < bestDifference {
                    bestDifference = difference
                    bestSplit = index + 1
                }
                
                firstLineWords.append(word)
                currentLength = newLength
            }
            
            let firstLine = Array(words[0..<bestSplit]).joined(separator: " ")
            let secondLine = Array(words[bestSplit...]).joined(separator: " ")
            
            // Format first line with dashes - ensure non-negative counts
            let totalDashes = max(0, width - firstLine.count - 4)
            let leftDashes = max(0, totalDashes / 2)
            let rightDashes = max(0, totalDashes - leftDashes)
            let formattedFirstLine = "*\(String(repeating: "-", count: leftDashes)) \(firstLine) \(String(repeating: "-", count: rightDashes))*"
            
            // Center second line without dashes
            let centeredSecondLine = wrapper(secondLine, width: width, centered: true)
            
            return formattedFirstLine + "\n" + centeredSecondLine
        }
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
