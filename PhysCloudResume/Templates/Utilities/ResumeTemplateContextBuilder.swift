import Foundation
import OrderedCollections

struct ResumeTemplateContextBuilder {
    private let templateSeedStore: TemplateSeedStore

    init(templateSeedStore: TemplateSeedStore) {
        self.templateSeedStore = templateSeedStore
    }
    @MainActor
    func buildContext(
        for template: Template,
        fallbackJSON: String?,
        applicantProfile: ApplicantProfile
    ) -> [String: Any]? {
        let manifest = TemplateManifestLoader.manifest(for: template)
        let fallback = fallbackJSON.flatMap { Self.parseJSON(from: $0) } ?? [:]
        let seedJSON = templateSeedStore.seed(for: template)?.jsonString ?? ""
        let seed = Self.parseJSON(from: seedJSON)

        var context = manifest?.makeDefaultContext() ?? [:]
        merge(into: &context, with: fallback)
        merge(into: &context, with: seed)
        merge(into: &context, with: profileContext(from: applicantProfile))

        addMissingKeys(from: fallback, to: &context)
        addMissingKeys(from: seed, to: &context)

        return context
    }

    // MARK: - Private helpers

    private func profileContext(from profile: ApplicantProfile) -> [String: Any] {
        var location: [String: Any] = [:]
        if !profile.address.isEmpty { location["address"] = profile.address }
        if !profile.city.isEmpty { location["city"] = profile.city }
        if !profile.state.isEmpty { location["state"] = profile.state }
        if !profile.zip.isEmpty { location["code"] = profile.zip }

        var contact: [String: Any] = [:]
        if !profile.name.isEmpty { contact["name"] = profile.name }
        if !profile.phone.isEmpty { contact["phone"] = profile.phone }
        if !profile.email.isEmpty { contact["email"] = profile.email }
        if !profile.websites.isEmpty { contact["website"] = profile.websites }
        if !location.isEmpty { contact["location"] = location }

        return contact.isEmpty ? [:] : ["contact": contact]
    }

    private static func parseJSON(from string: String) -> [String: Any] {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return [:]
        }

        return (normalize(dict) as? [String: Any]) ?? [:]
    }

    private static func normalize(_ value: Any) -> Any {
        switch value {
        case is NSNull:
            return NSNull()
        case let ordered as OrderedDictionary<String, Any>:
            var dict: [String: Any] = [:]
            for (key, inner) in ordered {
                dict[key] = normalize(inner)
            }
            return dict
        case let dict as [String: Any]:
            var normalized: [String: Any] = [:]
            for (key, inner) in dict {
                normalized[key] = normalize(inner)
            }
            return normalized
        case let array as [Any]:
            return array.map { normalize($0) }
        default:
            return value
        }
    }

    private func merge(into base: inout [String: Any], with overlay: [String: Any]) {
        for (key, value) in overlay {
            let normalized = ResumeTemplateContextBuilder.normalize(value)
            base[key] = mergeValue(base[key], with: normalized)
        }
    }

    private func mergeValue(_ base: Any?, with overlay: Any) -> Any {
        if overlay is NSNull {
            return base ?? NSNull()
        }

        switch (base, overlay) {
        case let (baseDict as [String: Any], overlayDict as [String: Any]):
            var merged = baseDict
            merge(into: &merged, with: overlayDict)
            return merged
        case (_, let overlayArray as [Any]):
            return overlayArray.isEmpty ? (base ?? overlayArray) : overlayArray
        case (_, let overlayString as String):
            return overlayString.isEmpty ? (base ?? overlayString) : overlayString
        default:
            return overlay
        }
    }

    private func addMissingKeys(from source: [String: Any], to context: inout [String: Any]) {
        for (key, value) in source where context[key] == nil {
            context[key] = value
        }
    }
}
