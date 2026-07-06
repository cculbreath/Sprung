//
//  ScoutKeywordsParser.swift
//  Sprung
//
//  Pure text ↔ keyword-list conversion for the Job Scout run modal. The
//  modal pre-fills its keywords field from SearchPreferences.targetSectors
//  and parses the (user-edited) comma-separated text back into the run
//  config's keyword array.
//

import Foundation

enum ScoutKeywordsParser {
    /// Splits comma- or newline-separated keyword text into trimmed keywords.
    /// Empty pieces are dropped; duplicates are removed case-insensitively
    /// with the first spelling winning; original order is preserved.
    static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var keywords: [String] = []
        for piece in text.split(whereSeparator: { $0 == "," || $0.isNewline }) {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed.lowercased()).inserted {
                keywords.append(trimmed)
            }
        }
        return keywords
    }

    /// Renders a keyword list back into the field's comma-separated form.
    static func join(_ keywords: [String]) -> String {
        keywords.joined(separator: ", ")
    }
}
