//
//  JobDescriptionMarkdownParser.swift
//  Sprung
//
//  Pure markdown→structure parse for job descriptions, extracted from RichTextView
//  so the regex-heavy paragraph and bold splitting is unit-testable. The View keeps
//  the SwiftUI rendering, highlight animation, and AttributedString assembly.
//
//  NOTE: the paragraph `startIndex` offsets are approximate (the original View
//  computed them with `+ index * 10`-style heuristics); they drive highlight-span
//  overlap, not exact selection. The tests pin the structural parse, not byte offsets.
//

import Foundation

enum JobDescriptionMarkdownParser {

    struct Paragraph: Identifiable {
        let id = UUID()
        let content: String
        let type: ParagraphType
        let startIndex: Int // Character offset in original text
    }

    enum ParagraphType {
        case normal
        case bold
        case list
        case listItem(String)
    }

    struct TextSegment {
        let text: String
        let isBold: Bool
        let offset: Int
    }

    /// Split `text` into paragraphs (normal / bold-title / bullet-list), preserving
    /// each paragraph's approximate character offset in the original text.
    static func paragraphs(from text: String) -> [Paragraph] {
        var result: [Paragraph] = []
        var preprocessedText = text
        var currentOffset = 0

        let problemPattern1 = #"\*\*([^*\n]+)[\s\n]+\*\*"#
        if let regex = try? NSRegularExpression(pattern: problemPattern1, options: []) {
            let nsString = preprocessedText as NSString
            let range = NSRange(location: 0, length: nsString.length)
            let matches = regex.matches(in: preprocessedText, options: [], range: range)
            for match in matches.reversed() where match.numberOfRanges > 1 {
                let contentRange = match.range(at: 1)
                let content = nsString.substring(with: contentRange)
                let replacement = "**\(content)**"
                preprocessedText = (preprocessedText as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }

        preprocessedText = preprocessedText.replacingOccurrences(
            of: "\\*\\*([^*]+?)\\*\\*\\s*\\n\\s*\\n",
            with: "**$1**\n\n",
            options: .regularExpression
        )

        let sections = preprocessedText.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for section in sections {
            if section.contains("\n* ") || section.contains("\n• ") || section.hasPrefix("* ") || section.hasPrefix("• ") {
                result.append(Paragraph(content: section, type: .list, startIndex: currentOffset))
                currentOffset += section.count + 2
                continue
            }

            let boldTitlePattern = #"^\*\*(.+?)\*\*[\s\n]*"#
            do {
                let regex = try NSRegularExpression(pattern: boldTitlePattern, options: [.dotMatchesLineSeparators])
                let nsSection = section as NSString
                let matches = regex.matches(in: section, options: [], range: NSRange(location: 0, length: nsSection.length))
                if !matches.isEmpty, let match = matches.first {
                    if match.numberOfRanges > 1 {
                        let titleRange = match.range(at: 1)
                        let boldTitle = nsSection.substring(with: titleRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        result.append(Paragraph(content: boldTitle, type: .bold, startIndex: currentOffset))
                        if match.range.upperBound < nsSection.length {
                            let remainingText = nsSection.substring(from: match.range.upperBound).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !remainingText.isEmpty {
                                result.append(Paragraph(content: remainingText, type: .normal, startIndex: currentOffset + match.range.upperBound))
                            }
                        }
                    } else {
                        result.append(Paragraph(content: section, type: .normal, startIndex: currentOffset))
                    }
                } else {
                    let clearedText = cleanAsterisks(section)
                    result.append(Paragraph(content: clearedText, type: .normal, startIndex: currentOffset))
                }
            } catch {
                result.append(Paragraph(content: section, type: .normal, startIndex: currentOffset))
            }
            currentOffset += section.count + 2
        }
        return result
    }

    /// Split inline content into bold / non-bold segments (for `**bold**` runs),
    /// carrying each segment's character offset. Empty when the content has no bold runs.
    static func boldSegments(in content: String, startIndex: Int) -> [TextSegment] {
        guard content.contains("**") else { return [] }
        var segments: [TextSegment] = []
        let pattern = #"\*\*(.+?)\*\*|([^*]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsText.length))
        var currentOffset = 0
        for match in matches {
            if match.numberOfRanges > 2 {
                if match.range(at: 1).location != NSNotFound {
                    let boldText = nsText.substring(with: match.range(at: 1))
                    segments.append(TextSegment(text: boldText, isBold: true, offset: startIndex + currentOffset))
                    currentOffset += match.range.length
                } else if match.range(at: 2).location != NSNotFound {
                    let regularText = nsText.substring(with: match.range(at: 2))
                    segments.append(TextSegment(text: regularText, isBold: false, offset: startIndex + currentOffset))
                    currentOffset += match.range.length
                }
            } else {
                let wholeMatch = nsText.substring(with: match.range)
                segments.append(TextSegment(text: wholeMatch, isBold: false, offset: startIndex + currentOffset))
                currentOffset += match.range.length
            }
        }
        return segments
    }

    /// Strip `**bold**` markers, leaving the inner text (used when a section has no
    /// leading bold title but still contains inline emphasis markers).
    private static func cleanAsterisks(_ text: String) -> String {
        var result = text
        let pattern = #"\*\*(.+?)\*\*"#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() where match.numberOfRanges > 1 {
                let contentRange = match.range(at: 1)
                let content = nsText.substring(with: contentRange)
                let range = match.range
                result = (result as NSString).replacingCharacters(in: range, with: content)
            }
        } catch {
            Logger.debug("Failed to normalize markdown markers: \(error.localizedDescription)")
        }
        return result
    }
}
