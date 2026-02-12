// Sprung/Shared/Extensions/String+Extensions.swift
import Foundation
import SwiftUI
extension String {
    /// Decodes common HTML entities without altering existing whitespace.
    func decodingHTMLEntities() -> String {
        var result = self
        // Named entities (order matters: decode &amp; last to avoid double-decoding)
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        // Non-breaking space unicode
        result = result.replacingOccurrences(of: "\u{00A0}", with: " ")
        return result
    }
    /// Returns the string trimmed of surrounding whitespace and newlines.
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Collapses runs of three or more newlines into a single blank line while
    /// preserving intentional single blank lines between sections.
    func collapsingConsecutiveBlankLines() -> String {
        var resultLines: [String] = []
        var previousWasBlank = false
        for line in self.split(separator: "\n", omittingEmptySubsequences: false) {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if previousWasBlank {
                    continue
                }
                previousWasBlank = true
            } else {
                previousWasBlank = false
            }
            resultLines.append(String(line))
        }
        while let first = resultLines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            resultLines.removeFirst()
        }
        while let last = resultLines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            resultLines.removeLast()
        }
        return resultLines.joined(separator: "\n")
    }
}
