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
}
