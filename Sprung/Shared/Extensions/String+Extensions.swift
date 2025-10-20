// Sprung/Shared/Extensions/String+Extensions.swift

import Foundation
import SwiftUI

extension String {
    /// Decodes common HTML entities without altering existing whitespace.
    func decodingHTMLEntities() -> String {
        if let decoded = CFXMLCreateStringByUnescapingEntities(nil, self as CFString, nil) {
            let result = decoded as String
            return result.replacingOccurrences(of: "\u{00A0}", with: " ")
        }
        return self
    }

    /// Returns the string trimmed of surrounding whitespace and newlines.
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
