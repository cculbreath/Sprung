import Foundation
import OrderedCollections
struct SectionValueNormalizer {

    let manifest: TemplateManifest?
    let fontScaler: FontSizeScaler
    func normalize(
        _ value: Any,
        for behavior: TemplateManifest.Section.FieldDescriptor.Behavior?
    ) -> Any {
        guard let behavior else { return value }
        switch behavior {
        case .includeFonts:
            if let string = value as? String {
                return string
            }
            if let boolValue = value as? Bool {
                return boolValue ? "true" : "false"
            }
            if let number = value as? NSNumber {
                return number.boolValue ? "true" : "false"
            }
            return "\(value)"
        case .fontSizes:
            if let dict = value as? [String: String] {
                return fontScaler.scaleFontSizes(dict)
            }
            if let dict = value as? [String: Any] {
                var normalized: [String: String] = [:]
                for (key, anyValue) in dict {
                    if let stringValue = anyValue as? String {
                        normalized[key] = stringValue
                    } else if let number = anyValue as? NSNumber {
                        normalized[key] = "\(number)pt"
                    }
                }
                return fontScaler.scaleFontSizes(normalized)
            }
            return value
        case .editorKeys:
            if let strings = value as? [String] {
                return strings
            }
            if let array = value as? [Any] {
                return array.compactMap { element in
                    if let string = element as? String, string.isEmpty == false {
                        return string
                    }
                    return nil
                }
            }
            if let single = value as? String, single.isEmpty == false {
                return [single]
            }
            return value
        case .sectionLabels:
            if let dict = value as? [String: String] {
                return dict
            }
            if let dict = value as? [String: Any] {
                var normalized: [String: String] = [:]
                for (key, anyValue) in dict {
                    if let stringValue = anyValue as? String {
                        normalized[key] = stringValue
                    }
                }
                return normalized
            }
            return value
        case .applicantProfile:
            return value
        }
    }
    func isEmpty(_ value: Any) -> Bool {
        switch value {
        case let string as String:
            return string.isEmpty
        case let strings as [String]:
            return strings.isEmpty
        case let array as [Any]:
            return array.isEmpty
        case let dict as [String: Any]:
            return dict.isEmpty
        case let dict as [String: String]:
            return dict.isEmpty
        default:
            return false
        }
    }
    func defaultFontSizes() -> [String: String]? {
        guard let defaults = manifestDefaultDictionary(for: "styling"),
              let fontSizes = defaults["fontSizes"] else {
            Logger.debug("ResumeTemplateDataBuilder: no fontSizes default found in manifest")
            return nil
        }
        let normalized = normalizeStringMap(fontSizes)
        Logger.debug("ResumeTemplateDataBuilder: manifest fontSizes default => \(normalized ?? [:])")
        return normalized
    }
    func defaultPageMargins() -> [String: String]? {
        guard let defaults = manifestDefaultDictionary(for: "styling"),
              let margins = defaults["pageMargins"] else {
            Logger.debug("ResumeTemplateDataBuilder: no pageMargins default found in manifest")
            return nil
        }
        let normalized = normalizeStringMap(margins)
        Logger.debug("ResumeTemplateDataBuilder: manifest pageMargins default => \(normalized ?? [:])")
        return normalized
    }
    func defaultIncludeFonts() -> Bool? {
        guard let defaults = manifestDefaultDictionary(for: "styling"),
              let include = defaults["includeFonts"] else { return nil }
        if let boolValue = include as? Bool { return boolValue }
        if let stringValue = include as? String {
            return stringValue == "true"
        }
        return nil
    }
    private func manifestDefaultDictionary(for section: String) -> [String: Any]? {
        guard let value = manifest?.section(for: section)?.defaultValue?.value else { return nil }
        if let dict = value as? [String: Any] {
            return dict
        }
        if let ordered = value as? OrderedDictionary<String, Any> {
            return Dictionary(uniqueKeysWithValues: ordered.map { ($0.key, $0.value) })
        }
        return nil
    }
    private func normalizeStringMap(_ value: Any) -> [String: String]? {
        if let dict = value as? [String: Any] {
            var result: [String: String] = [:]
            for (key, entry) in dict {
                if let stringValue = entry as? String {
                    result[key] = stringValue
                }
            }
            return result.isEmpty ? nil : result
        }
        if let ordered = value as? OrderedDictionary<String, Any> {
            return normalizeStringMap(
                Dictionary(uniqueKeysWithValues: ordered.map { ($0.key, $0.value) })
            )
        }
        return nil
    }
}
