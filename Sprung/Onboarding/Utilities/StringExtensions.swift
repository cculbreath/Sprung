import Foundation

extension String {
    /// Returns the string with whitespace trimmed, or nil if empty after trimming
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns true if the string is empty after trimming whitespace
    var isTrimmedEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
