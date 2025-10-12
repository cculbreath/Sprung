import Foundation
import PDFKit
import SwiftyJSON

enum ResumeRawExtractor {
    static func extract(from data: Data, filename: String?) -> JSON {
        var text = extractPlainText(from: data)

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let string = String(data: data, encoding: .utf8) {
            text = string
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var extraction: [String: Any] = [:]

        if let nameLine = findCandidateName(in: lines) {
            extraction["name"] = nameLine
        }

        if let email = match(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: text) {
            extraction["email"] = email
        }

        if let phone = match(pattern: #"\+?\d[\d\-().\s]{7,}\d"#, in: text) {
            extraction["phone"] = phone
        }

        if let website = match(pattern: #"(https?:\/\/)?([\w-]+\.)+[\w-]{2,}(\/\S*)?"#, in: text) {
            extraction["website"] = website
        }

        if let location = extractLocation(from: lines) {
            extraction["location"] = location
        }

        let education = extractSection(named: "education", from: lines)
        if !education.isEmpty {
            extraction["education"] = education
        }

        let experience = extractSection(named: "experience", from: lines)
        if !experience.isEmpty {
            extraction["experience"] = experience
        }

        let skills = extractSkills(from: text)
        if !skills.isEmpty {
            extraction["skills"] = skills
        }

        if let filename {
            extraction["source"] = filename
        }

        return JSON(extraction)
    }

    private static func extractPlainText(from data: Data) -> String {
        if let pdf = PDFDocument(data: data) {
            var text = ""
            for index in 0..<pdf.pageCount {
                guard let page = pdf.page(at: index),
                      let pageText = page.string else { continue }
                text.append(pageText)
                text.append("\n")
            }
            return text
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func findCandidateName(in lines: [String]) -> String? {
        guard let first = lines.first else { return nil }
        if first.split(separator: " ").count <= 6 {
            return first
        }
        return nil
    }

    private static func match(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        if let range = Range(match.range, in: text) {
            return String(text[range])
        }
        return nil
    }

    private static func extractLocation(from lines: [String]) -> String? {
        for line in lines.prefix(5) {
            if line.contains(",") && line.split(separator: ",").count == 2 {
                return line
            }
        }
        return nil
    }

    private static func extractSection(named sectionName: String, from lines: [String]) -> [String] {
        var collected: [String] = []
        var inSection = false

        for line in lines {
            let lower = line.lowercased()
            if lower.contains(sectionName) {
                inSection = true
                continue
            }

            if inSection {
                if lower.contains("skills") || lower.contains("summary") || lower.contains("projects") {
                    break
                }
                collected.append(line)
            }
        }

        return collected
    }

    private static func extractSkills(from text: String) -> [String] {
        let lower = text.lowercased()
        guard let range = lower.range(of: "skills") else { return [] }
        let substring = text[range.upperBound...]
        let components = substring.split(whereSeparator: { $0 == "\n" || $0 == ";" })
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.count > 256 { continue }
            let tokens = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if tokens.count >= 2 {
                return tokens.filter { !$0.isEmpty }
            }
        }
        return []
    }
}
