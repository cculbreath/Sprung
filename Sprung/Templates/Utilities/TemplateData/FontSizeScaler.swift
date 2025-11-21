import Foundation
struct FontSizeScaler {
    private static let scaleFactor = Decimal(3) / Decimal(4)
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter
    }()
    func buildFontSizes(from nodes: [FontSizeNode]) -> [String: String]? {
        guard nodes.isEmpty == false else { return nil }
        var result: [String: String] = [:]
        for node in nodes.sorted(by: { $0.index < $1.index }) {
            result[node.key] = node.fontString
        }
        return result
    }
    func scaleFontSizes(_ fontSizes: [String: String]) -> [String: String] {
        var scaled: [String: String] = [:]
        for (key, value) in fontSizes {
            scaled[key] = scaledFontSizeString(from: value)
        }
        return scaled
    }
    private func scaledFontSizeString(from value: String) -> String {
        guard let decimal = parseFontSizeValue(from: value) else {
            return value
        }
        let scaledDecimal = decimal * Self.scaleFactor
        let formatted = formatFontDecimal(scaledDecimal)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasSuffix("pt") {
            return "\(formatted)pt"
        }
        if trimmed.hasSuffix("px") {
            return "\(formatted)px"
        }
        return formatted
    }
    private func parseFontSizeValue(from string: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let lowercased = trimmed.lowercased()
        if lowercased == "inherit" || lowercased == "auto" {
            return nil
        }
        var sanitized = trimmed
        if lowercased.hasSuffix("pt") || lowercased.hasSuffix("px") {
            sanitized = String(sanitized.dropLast(2))
        }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: sanitized)
    }
    private func formatFontDecimal(_ decimal: Decimal) -> String {
        let number = NSDecimalNumber(decimal: decimal)
        if let formatted = Self.formatter.string(from: number) {
            return formatted
        }
        return number.stringValue
    }
}
