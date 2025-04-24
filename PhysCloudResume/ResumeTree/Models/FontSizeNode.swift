//
//  FontSizeNode.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import Foundation
import SwiftData

@Model class FontSizeNode: Identifiable {
    var id = UUID().uuidString
    var key: String = ""
    /// Local index within the font‑size array (provided by the builder).
    var index: Int
    var fontValue: Float
    var fontString: String {
        get {
            return "\(fontValue)pt"
        }
        set {
            fontValue = FontSizeNode.parseFontString(newValue)
        }
    }

    init(
        id: String = UUID().uuidString,
        key: String,
        index: Int,
        fontString: String

    ) {
        self.index = index
        self.id = id
        self.key = key
        fontValue = FontSizeNode.parseFontString(fontString)
    }

    /// Converts a "12pt" style string to a Float value
    private static func parseFontString(_ fontString: String) -> Float {
        let trimmed = fontString.trimmingCharacters(in: .whitespacesAndNewlines)
        return Float(trimmed.replacingOccurrences(of: "pt", with: "").trimmingCharacters(in: .whitespaces)) ?? 10
    }

    var keyToTitle: String {
        let lowercaseWords: Set<String> = ["and", "of", "or", "the", "a", "an", "in", "on", "at", "to", "for", "but", "nor", "so", "yet", "with", "by", "as", "from", "about", "into", "over", "after", "before", "between", "under", "without", "against", "during", "upon"]

        let words = key
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .enumerated()
            .map { index, word in
                let lowercaseWord = word.lowercased()
                return (index == 0 || !lowercaseWords.contains(lowercaseWord)) ? lowercaseWord.capitalized : lowercaseWord
            }

        return words.joined(separator: " ")
    }
}
