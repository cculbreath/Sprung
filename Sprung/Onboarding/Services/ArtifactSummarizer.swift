import Foundation
import NaturalLanguage
import PDFKit
import SwiftyJSON

enum ArtifactSummarizer {
    static func summarize(data: Data, filename: String?, context: String?) -> JSON {
        let text = plainText(from: data)
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let summary = sentences.prefix(3).joined(separator: ". ")
        let keywords = topKeywords(from: text, limit: 6)

        var card: [String: Any] = [
            "title": filename ?? "Uploaded Artifact",
            "summary": summary,
            "skills": keywords,
            "metrics": extractMetrics(from: text)
        ]

        if let context, !context.isEmpty {
            card["context"] = context
        }

        return JSON(card)
    }

    private static func plainText(from data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            return string
        }

        if let pdf = PDFDocument(data: data) {
            var text = ""
            for index in 0..<pdf.pageCount {
                guard let page = pdf.page(at: index), let pageText = page.string else { continue }
                text.append(pageText)
                text.append("\n")
            }
            return text
        }

        return ""
    }

    private static func topKeywords(from text: String, limit: Int) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var counts: [String: Int] = [:]

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            guard word.count > 2, word.rangeOfCharacter(from: CharacterSet.letters) != nil else {
                return true
            }
            counts[word, default: 0] += 1
            return true
        }

        return counts.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key.capitalized }
    }

    private static func extractMetrics(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            return trimmed.contains("%") || trimmed.contains("$") || trimmed.range(of: #"\d{2,}"#, options: .regularExpression) != nil
        }
        .prefix(3)
        .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
