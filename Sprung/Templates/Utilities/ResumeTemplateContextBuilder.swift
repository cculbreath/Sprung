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
        let sanitizedFallback = removeContactSection(from: fallback)
        let sanitizedSeed = removeContactSection(from: seed)

        var context = manifest?.makeDefaultContext() ?? [:]
        merge(into: &context, with: sanitizedFallback)
        merge(into: &context, with: sanitizedSeed)
        merge(into: &context, with: profileContext(from: applicantProfile))

        addMissingKeys(from: sanitizedFallback, to: &context)
        addMissingKeys(from: sanitizedSeed, to: &context)

        if let manifest {
            context = SeedContextNormalizer(manifest: manifest).normalize(context)
#if DEBUG
            if let skills = context["skills-and-expertise"] {
                Logger.debug("Template seed normalization – skills-and-expertise: \(describeValue(skills))")
            }
            if let employment = context["employment"] {
                Logger.debug("Template seed normalization – employment keys: \(describeValue(employment))")
            }
            if let projects = context["projects-highlights"] {
                Logger.debug("Template seed normalization – projects-highlights: \(describeValue(projects))")
            }
#endif
        }

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

    private func removeContactSection(from dictionary: [String: Any]) -> [String: Any] {
        var sanitized = dictionary
        sanitized.removeValue(forKey: "contact")
        return sanitized
    }

#if DEBUG
    private func describeValue(_ value: Any) -> String {
        if let array = value as? [Any] {
            let preview = array.first.map { String(describing: $0) } ?? "nil"
            return "array(count: \(array.count), first: \(preview))"
        }
        if let dict = value as? [String: Any] {
            let keys = dict.keys.sorted()
            let sampleKey = keys.first
            let sampleValue = sampleKey.flatMap { dict[$0] }.map { String(describing: $0) } ?? "nil"
            let keyLabel = sampleKey ?? "nil"
            return "dict(keys: \(keys), sample[\(keyLabel)]: \(sampleValue))"
        }
        return "\(value)"
    }
#endif
}

// MARK: - Seed normalization

private struct SeedContextNormalizer {
    let manifest: TemplateManifest

    func normalize(_ context: [String: Any]) -> [String: Any] {
        var normalized = context

        for key in manifest.sectionOrder {
            guard let section = manifest.section(for: key),
                  let rawValue = normalized[key] else { continue }
            normalized[key] = normalizeValue(rawValue, for: section, sectionKey: key)
        }

        // Include any sections not listed in sectionOrder
        for (key, value) in context where normalized[key] == nil {
            if let section = manifest.section(for: key) {
                normalized[key] = normalizeValue(value, for: section, sectionKey: key)
            } else {
                normalized[key] = value
            }
        }

        return normalized
    }

    private func normalizeValue(
        _ value: Any,
        for section: TemplateManifest.Section,
        sectionKey: String
    ) -> Any {
        switch section.type {
        case .array:
            return normalizeArraySection(value, section: section)
        case .arrayOfObjects:
            let descriptor = section.fields.first(where: { $0.key == "*" })
            return normalizeArrayOfObjectsSection(value, descriptor: descriptor)
        case .objectOfObjects:
            let descriptor = section.fields.first(where: { $0.key == "*" })
            return normalizeObjectOfObjectsSection(value, descriptor: descriptor)
        case .mapOfStrings:
            return normalizeMapOfStringsSection(value)
        case .string:
            return normalizeStringSection(value)
        default:
            return value
        }
    }

    // MARK: - Section handlers

    private func normalizeArraySection(_ value: Any, section: TemplateManifest.Section) -> Any {
        if let array = value as? [Any] {
            return array
        }
        if let ordered = value as? OrderedDictionary<String, Any> {
            return ordered.values.map { $0 }
        }
        if let dictionary = value as? [String: Any] {
            // Preserve deterministic order by sorting keys
            return dictionary.keys.sorted().compactMap { dictionary[$0] }
        }
        if let string = value as? String {
            return string.isEmpty ? [] : [string]
        }
        return value
    }

    private func normalizeStringSection(_ value: Any) -> Any {
        if let string = value as? String {
            return string
        }
        if let array = value as? [String] {
            return array.first ?? ""
        }
        if let array = value as? [Any] {
            return array.first as? String ?? ""
        }
        if let dict = value as? [String: Any], let string = dict["value"] as? String {
            return string
        }
        return value
    }

    private func normalizeArrayOfObjectsSection(
        _ value: Any,
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) -> Any {
        let entries = arrayEntries(from: value, descriptor: descriptor)
        return entries.isEmpty ? value : entries
    }

    private func normalizeObjectOfObjectsSection(
        _ value: Any,
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) -> Any {
        if var ordered = value as? OrderedDictionary<String, Any> {
            for key in ordered.keys {
                ordered[key] = normalizeDictionaryEntry(
                    ordered[key],
                    key: key,
                    descriptor: descriptor
                )
            }
            return ordered.mapValues { $0 }
        }

        if var dictionary = value as? [String: Any] {
            for key in dictionary.keys {
                dictionary[key] = normalizeDictionaryEntry(
                    dictionary[key],
                    key: key,
                    descriptor: descriptor
                )
            }
            return dictionary
        }

        if let array = value as? [[String: Any]] {
            var result: [String: Any] = [:]
            for entry in array {
                guard let key = entry["__key"] as? String else { continue }
                var cleaned = entry
                cleaned.removeValue(forKey: "__key")
                result[key] = cleaned
            }
            return result.isEmpty ? value : result
        }

        return value
    }

    private func normalizeMapOfStringsSection(_ value: Any) -> Any {
        if let ordered = value as? OrderedDictionary<String, Any> {
            return ordered
                .compactMapValues { $0 as? String }
        }
        if let dictionary = value as? [String: Any] {
            var result: [String: String] = [:]
            for (key, inner) in dictionary {
                if let string = inner as? String {
                    result[key] = string
                }
            }
            return result
        }
        return value
    }

    // MARK: - Entry helpers

    private func arrayEntries(
        from raw: Any,
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) -> [[String: Any]] {
        var entries: [[String: Any]] = []

        func appendEntry(sourceKey: String?, payload: [String: Any]) {
            var entry = payload
            if let sourceKey, entry["__key"] == nil {
                entry["__key"] = sourceKey
            }
            if let descriptor {
                ensureDescriptorDefaults(for: &entry, descriptor: descriptor, fallbackKey: sourceKey)
            } else if let sourceKey, entry["title"] == nil {
                entry["title"] = sourceKey
            }
            entries.append(entry)
        }

        if let ordered = raw as? OrderedDictionary<String, Any> {
            for key in ordered.keys {
                let value = ordered[key]
                if let dict = value as? OrderedDictionary<String, Any> {
                    appendEntry(sourceKey: key, payload: dict.asDictionary())
                } else if let dict = value as? [String: Any] {
                    appendEntry(sourceKey: key, payload: dict)
                } else if let string = value as? String {
                    appendEntry(
                        sourceKey: key,
                        payload: dictionaryFromPrimitive(
                            string,
                            descriptor: descriptor,
                            fallbackKey: key
                        )
                    )
                } else if let array = value as? [Any] {
                    appendEntry(sourceKey: key, payload: ["items": array])
                }
            }
            return entries
        }

        if let dictionary = raw as? [String: Any] {
            for key in dictionary.keys.sorted() {
                guard let value = dictionary[key] else { continue }
                if let dict = value as? [String: Any] {
                    appendEntry(sourceKey: key, payload: dict)
                } else if let string = value as? String {
                    appendEntry(
                        sourceKey: key,
                        payload: dictionaryFromPrimitive(
                            string,
                            descriptor: descriptor,
                            fallbackKey: key
                        )
                    )
                } else if let array = value as? [Any] {
                    appendEntry(sourceKey: key, payload: ["items": array])
                }
            }
            return entries
        }

        if let array = raw as? [Any] {
            for element in array {
                if let dict = element as? [String: Any] {
                    appendEntry(
                        sourceKey: dict["__key"] as? String,
                        payload: dict
                    )
                } else if let ordered = element as? OrderedDictionary<String, Any> {
                    appendEntry(
                        sourceKey: ordered["__key"] as? String,
                        payload: ordered.asDictionary()
                    )
                } else if let string = element as? String {
                    appendEntry(
                        sourceKey: nil,
                        payload: dictionaryFromPrimitive(
                            string,
                            descriptor: descriptor,
                            fallbackKey: nil
                        )
                    )
                }
            }
            return entries
        }

        return entries
    }

    private func dictionaryFromPrimitive(
        _ value: String,
        descriptor: TemplateManifest.Section.FieldDescriptor?,
        fallbackKey: String?
    ) -> [String: Any] {
        guard let descriptor, let children = descriptor.children, !children.isEmpty else {
            return ["value": value]
        }

        var entry: [String: Any] = [:]
        if let titleDescriptor = children.first(where: { $0.key == "title" }),
           let fallbackKey {
            entry[titleDescriptor.key] = fallbackKey
        }
        if let primaryDescriptor = children.first(where: { $0.key != "title" }) {
            entry[primaryDescriptor.key] = value
        } else {
            entry["value"] = value
        }
        return entry
    }

    private func normalizeDictionaryEntry(
        _ raw: Any?,
        key: String,
        descriptor: TemplateManifest.Section.FieldDescriptor?
    ) -> Any {
        guard let raw else { return [:] }

        if var dict = raw as? [String: Any] {
            if dict["__key"] == nil {
                dict["__key"] = key
            }
            if let descriptor {
                ensureDescriptorDefaults(for: &dict, descriptor: descriptor, fallbackKey: key)
            }
            return dict
        }

        if let ordered = raw as? OrderedDictionary<String, Any> {
            var dict = ordered.asDictionary()
            if dict["__key"] == nil {
                dict["__key"] = key
            }
            if let descriptor {
                ensureDescriptorDefaults(for: &dict, descriptor: descriptor, fallbackKey: key)
            }
            return dict
        }

        if let string = raw as? String {
            var dict = dictionaryFromPrimitive(
                string,
                descriptor: descriptor,
                fallbackKey: key
            )
            dict["__key"] = key
            if let descriptor {
                ensureDescriptorDefaults(for: &dict, descriptor: descriptor, fallbackKey: key)
            }
            return dict
        }

        if let array = raw as? [Any] {
            if let firstDict = array.first as? [String: Any] {
                var normalized = firstDict
                if normalized["__key"] == nil {
                    normalized["__key"] = key
                }
                if let descriptor {
                    ensureDescriptorDefaults(for: &normalized, descriptor: descriptor, fallbackKey: key)
                }
                return normalized
            }
            if let firstString = array.first as? String {
                var normalized = dictionaryFromPrimitive(firstString, descriptor: descriptor, fallbackKey: key)
                normalized["__key"] = key
                if let descriptor {
                    ensureDescriptorDefaults(for: &normalized, descriptor: descriptor, fallbackKey: key)
                }
                return normalized
            }
        }

        return raw
    }

    private func ensureDescriptorDefaults(
        for entry: inout [String: Any],
        descriptor: TemplateManifest.Section.FieldDescriptor,
        fallbackKey: String?
    ) {
        guard let children = descriptor.children, !children.isEmpty else { return }
        if let fallbackKey,
           let titleDescriptor = children.first(where: { $0.key == "title" }),
           entry[titleDescriptor.key] == nil {
            entry[titleDescriptor.key] = fallbackKey
        }

        if let fallbackKey,
           descriptor.repeatable,
           entry["__key"] == nil {
            entry["__key"] = fallbackKey
        }

        if let value = entry["value"],
           let primaryDescriptor = children.first(where: { $0.key != "title" }) {
            if entry[primaryDescriptor.key] == nil {
                entry[primaryDescriptor.key] = value
            }
        }

        if entry["title"] == nil,
           children.first(where: { $0.key == "title" }) == nil,
           let fallbackKey {
            entry["title"] = fallbackKey
        }
    }
}

private extension OrderedDictionary where Key == String, Value == Any {
    func asDictionary() -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in self {
            result[key] = value
        }
        return result
    }
}
