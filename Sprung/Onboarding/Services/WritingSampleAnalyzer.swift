import Foundation
import PDFKit
import SwiftyJSON

enum WritingSampleAnalyzer {
    static func analyze(
        data: Data,
        filename: String,
        context: String?,
        sampleId: String
    ) -> JSON {
        let text = extractPlainText(from: data)
        let sentences = splitSentences(in: text)
        let words = tokenizeWords(in: text)

        let avgSentenceLength = averageSentenceLength(sentences: sentences)
        let activeVoiceRatio = estimateActiveVoiceRatio(for: sentences)
        let quantDensity = quantitativeDensity(words: words)
        let tone = inferTone(words: words)
        let notable = notablePhrases(in: sentences)

        var payload: [String: Any] = [
            "sample_id": sampleId,
            "title": filename,
            "word_count": words.count,
            "avg_sentence_len": avgSentenceLength,
            "active_voice_ratio": activeVoiceRatio,
            "quant_density_per_100w": quantDensity,
            "tone": tone,
            "notable_phrases": notable
        ]

        if let context, !context.isEmpty {
            payload["context"] = context
        }

        payload["summary"] = summarize(sentences: sentences)

        return JSON(payload)
    }

    static func extractPlainText(from data: Data) -> String {
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

    // MARK: - Metrics

    private static func splitSentences(in text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func tokenizeWords(in text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func averageSentenceLength(sentences: [String]) -> Double {
        guard !sentences.isEmpty else { return 0.0 }
        let wordTotals = sentences.map { tokenizeWords(in: $0).count }
        let sum = wordTotals.reduce(0, +)
        return Double(sum) / Double(sentences.count)
    }

    private static func estimateActiveVoiceRatio(for sentences: [String]) -> Double {
        guard !sentences.isEmpty else { return 0.0 }
        let passiveIndicators = ["was", "were", "been", "being", "be", "is", "are"]
        var passiveCount = 0

        for sentence in sentences {
            let lower = sentence.lowercased()
            if passiveIndicators.contains(where: { lower.contains("\($0) by ") }) {
                passiveCount += 1
            }
        }

        let activeCount = sentences.count - passiveCount
        return Double(activeCount) / Double(sentences.count)
    }

    private static func quantitativeDensity(words: [String]) -> Double {
        guard !words.isEmpty else { return 0.0 }
        let numericTokens = words.filter { token in
            token.range(of: #"\d"#, options: .regularExpression) != nil || token.contains("%") || token.contains("$")
        }

        let density = (Double(numericTokens.count) / Double(words.count)) * 100.0
        return (density * 100).rounded() / 100 // two decimal places
    }

    private static func inferTone(words: [String]) -> String {
        guard !words.isEmpty else { return "neutral" }

        let positiveSet: Set<String> = ["achieved", "delivered", "accelerated", "improved", "optimized", "launched", "led", "exceeded"]
        let negativeSet: Set<String> = ["struggled", "issue", "problem", "blocked", "delay", "risk"]

        let lowerTokens = words.map { $0.lowercased() }
        let positiveHits = lowerTokens.filter { positiveSet.contains($0) }.count
        let negativeHits = lowerTokens.filter { negativeSet.contains($0) }.count

        if positiveHits > negativeHits {
            return "confident"
        } else if negativeHits > positiveHits {
            return "cautious"
        }
        return "neutral"
    }

    private static func notablePhrases(in sentences: [String]) -> [String] {
        var results: [String] = []
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.range(of: #"\d"#, options: .regularExpression) != nil {
                results.append(trimmed)
            } else if trimmed.count > 80 {
                results.append(trimmed)
            }

            if results.count >= 5 {
                break
            }
        }
        return results
    }

    private static func summarize(sentences: [String]) -> String {
        let summary = sentences.prefix(2).joined(separator: ". ")
        return summary.isEmpty ? "Writing sample recorded for analysis." : summary
    }
}
