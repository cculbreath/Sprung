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
}
