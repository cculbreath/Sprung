import Foundation

struct TitleTemplateRenderer {
    func placeholders(in template: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\{\\{\\s*([^}]+)\\s*\\}}") else {
            return []
        }

        let matches = regex.matches(
            in: template,
            range: NSRange(template.startIndex..., in: template)
        )

        return matches.compactMap { match in
            guard match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: template) else {
                return nil
            }
            let raw = template[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.contains(".") == false else { return nil }
            return raw
        }
    }

    func render(_ template: String, context: [String: Any]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\{\\{\\s*([^}]+)\\s*\\}}") else {
            return nil
        }
        var result = template
        let matches = regex.matches(
            in: template,
            range: NSRange(template.startIndex..., in: template)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: template) else { continue }
            let keyPath = template[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let replacement = lookupValue(forKeyPath: keyPath, context: context),
                  replacement.isEmpty == false else {
                return nil
            }
            if let fullRange = Range(match.range, in: result) {
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        return result
    }

    private func lookupValue(
        forKeyPath keyPath: String,
        context: [String: Any]
    ) -> String? {
        let components = keyPath.split(separator: ".").map(String.init)
        var current: Any? = context
        for component in components {
            if let dict = current as? [String: Any] {
                current = dict[component]
            } else {
                current = nil
            }
        }
        if let string = current as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = current as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}
