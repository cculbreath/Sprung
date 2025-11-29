//
//  TemplateFilters.swift
//  Sprung
//
//  Provides Mustache filters for plain-text template formatting.
//
import Foundation
import Mustache
enum TemplateFilters {
    static func register(on template: Mustache.Template) {
        template.register(centerFilter, forKey: "center")
        template.register(wrapFilter, forKey: "wrap")
        template.register(sectionLineFilter, forKey: "sectionLine")
        template.register(joinFilter, forKey: "join")
        template.register(concatPairFilter, forKey: "concatPair")
        template.register(htmlStripFilter, forKey: "htmlStrip")
        template.register(htmlDecodeFilter, forKey: "htmlDecode")
        template.register(bulletListFilter, forKey: "bulletList")
        template.register(formatDateFilter, forKey: "formatDate")
        template.register(uppercaseFilter, forKey: "uppercase")
        template.register(hasContentFilter, forKey: "hasContent")
    }
    // MARK: - Individual Filters
    private static let centerFilter = VariadicFilter { boxes -> Any? in
        guard let text = string(from: boxes.first) else { return nil }
        let width = intArgument(from: boxes, index: 1, defaultValue: 80)
        let decoded = text.decodingHTMLEntities()
        return TextFormatHelpers.wrapper(decoded, width: width, centered: true)
    }
    private static let wrapFilter = VariadicFilter { boxes -> Any? in
        guard let text = string(from: boxes.first) else { return nil }
        let width = intArgument(from: boxes, index: 1, defaultValue: 80)
        let left = intArgument(from: boxes, index: 2, defaultValue: 0)
        let right = intArgument(from: boxes, index: 3, defaultValue: 0)
        let decoded = text.decodingHTMLEntities()
        return TextFormatHelpers.wrapper(decoded, width: width, leftMargin: left, rightMargin: right)
    }
    private static let sectionLineFilter = VariadicFilter { boxes -> Any? in
        guard let label = string(from: boxes.first), !label.isEmpty else { return nil }
        let width = intArgument(from: boxes, index: 1, defaultValue: 80)
        return TextFormatHelpers.sectionLine(label.decodingHTMLEntities(), width: width)
    }
    private static let joinFilter = VariadicFilter { boxes -> Any? in
        guard let arrayBox = boxes.first else { return nil }
        guard let items = arrayOfStrings(from: arrayBox) else { return nil }
        let separator = string(from: boxes[safe: 1]) ?? " \u{00B7} "
        let decodedItems = items.map { $0.decodingHTMLEntities() }
        let joined = TextFormatHelpers.joiner(decodedItems, separator: separator)
        return joined.isEmpty ? nil : joined
    }
    private static let concatPairFilter = VariadicFilter { boxes -> Any? in
        guard boxes.count >= 2 else { return nil }
        let first = string(from: boxes[0])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let second = string(from: boxes[1])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let separator = string(from: boxes[safe: 2]) ?? " "
        if first.isEmpty && second.isEmpty { return nil }
        if second.isEmpty { return first.decodingHTMLEntities() }
        if first.isEmpty { return second.decodingHTMLEntities() }
        let combined = first + separator + second
        return combined.decodingHTMLEntities()
    }
    private static let htmlStripFilter = Filter { (value: String?) -> Any? in
        guard let value, !value.isEmpty else { return nil }
        return value.decodingHTMLEntities().removingHTMLTags()
    }
    private static let htmlDecodeFilter = Filter { (value: String?) -> Any? in
        guard let value, !value.isEmpty else { return nil }
        return value.decodingHTMLEntities()
    }
    private static let bulletListFilter = VariadicFilter { boxes -> Any? in
        guard let source = boxes.first else { return nil }
        let width = intArgument(from: boxes, index: 1, defaultValue: 80)
        let indent = intArgument(from: boxes, index: 2, defaultValue: 2)
        let bullet = string(from: boxes[safe: 3]) ?? "•"
        let key = string(from: boxes[safe: 4]) ?? "description"
        let items: [String]
        if let strings = arrayOfStrings(from: source) {
            items = strings.map { $0.decodingHTMLEntities() }
        } else if let dicts = arrayOfDictionaries(from: source) {
            items = dicts.compactMap {
                ($0[key] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .decodingHTMLEntities()
            }
        } else {
            return nil
        }
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned
            .map { TextFormatHelpers.bulletText($0, marginLeft: indent, width: width, bullet: bullet) }
            .joined(separator: "\n")
    }
    private static let formatDateFilter = VariadicFilter { boxes -> Any? in
        guard let raw = string(from: boxes.first)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.lowercased() == "present" {
            return "Present"
        }
        let outputPattern = string(from: boxes[safe: 1]) ?? "MMM yyyy"
        let preferredInput = string(from: boxes[safe: 2])
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = outputPattern
        var inputPatterns: [String] = []
        if let preferredInput {
            inputPatterns.append(preferredInput)
        }
        inputPatterns.append(contentsOf: ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy-MM", "yyyy"])
        for pattern in inputPatterns {
            parser.dateFormat = pattern
            if let date = parser.date(from: raw) {
                return formatter.string(from: date)
            }
        }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: raw) {
            return formatter.string(from: date)
        }
        return raw
    }
    private static let uppercaseFilter = Filter { (value: String?) -> Any? in
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.uppercased()
    }
    private static func hasDisplayableContent(_ box: MustacheBox) -> Bool {
        if let arrayBoxes = box.arrayValue, !arrayBoxes.isEmpty {
            if arrayBoxes.contains(where: { hasDisplayableContent($0) }) {
                return true
            }
        }
        if let dictionaryBoxes = box.dictionaryValue, !dictionaryBoxes.isEmpty {
            if dictionaryBoxes.contains(where: { key, value in
                guard key != "custom" else { return false }
                return hasDisplayableContent(value)
            }) {
                return true
            }
        }
        if let value = box.value {
            return hasMeaningfulContent(value)
        }
        return false
    }
    private static func hasMeaningfulContent(_ value: Any?) -> Bool {
        guard let value else { return false }
        if value is NSNull { return false }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if value is NSNumber {
            return true
        }
        if let stringValue = value as? String {
            return !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let arrayValue = value as? [Any] {
            return arrayValue.contains { hasMeaningfulContent($0) }
        }
        if let dictionaryValue = value as? [String: Any] {
            return dictionaryValue.contains { key, entry in
                guard key != "custom" else { return false }
                return hasMeaningfulContent(entry)
            }
        }
        if let convertible = value as? CustomStringConvertible {
            return !convertible.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private static let hasContentFilter = VariadicFilter { boxes -> Any? in
        guard !boxes.isEmpty else { return nil }
        for box in boxes where hasDisplayableContent(box) {
            return true
        }
        return nil
    }
    // MARK: - Helpers
    private static func string(from box: MustacheBox?) -> String? {
        guard let box else { return nil }
        if let string = box.value as? String {
            return string
        }
        if let number = box.value as? NSNumber {
            return number.stringValue
        }
        return nil
    }
    private static func intArgument(from boxes: [MustacheBox], index: Int, defaultValue: Int) -> Int {
        guard let box = boxes[safe: index] else { return defaultValue }
        if let number = box.value as? NSNumber {
            return number.intValue
        }
        if let string = string(from: box), let value = Int(string) {
            return value
        }
        return defaultValue
    }
    private static func arrayOfStrings(from box: MustacheBox) -> [String]? {
        if let strings = box.value as? [String] {
            return strings
        }
        if let boxes = box.arrayValue {
            return boxes.compactMap { string(from: $0) }
        }
        return nil
    }
    private static func arrayOfDictionaries(from box: MustacheBox) -> [[String: Any]]? {
        if let array = box.value as? [[String: Any]] {
            return array
        }
        if let boxes = box.arrayValue {
            return boxes.compactMap { dictionary(from: $0) }
        }
        return nil
    }
    private static func dictionary(from box: MustacheBox?) -> [String: Any]? {
        guard let box else { return nil }
        if let dict = box.value as? [String: Any] {
            return dict
        }
        if let dict = box.value as? NSDictionary {
            return dict.reduce(into: [String: Any]()) { result, element in
                guard let key = element.key as? String else { return }
                result[key] = element.value
            }
        }
        if let boxes = box.dictionaryValue {
            return boxes.reduce(into: [String: Any]()) { result, element in
                let (key, valueBox) = element
                result[key] = valueBox.value ?? string(from: valueBox)
            }
        }
        return nil
    }
}
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
private extension String {
    func removingHTMLTags() -> String {
        guard let data = data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil)
        return attributed?.string ?? self
    }
}
