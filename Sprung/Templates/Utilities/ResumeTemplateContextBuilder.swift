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
        let sanitizedFallback = removeContactSection(from: fallback, manifest: manifest)
        let sanitizedSeed = removeContactSection(from: seed, manifest: manifest)

        var context = manifest?.makeDefaultContext() ?? [:]
        merge(into: &context, with: sanitizedFallback)
        merge(into: &context, with: sanitizedSeed)
        merge(into: &context, with: profileContext(from: applicantProfile, manifest: manifest))

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

    private func profileContext(from profile: ApplicantProfile, manifest: TemplateManifest?) -> [String: Any] {
        if let manifest {
            let payload = buildProfilePayload(using: manifest, profile: profile)
            if payload.isEmpty == false {
                return payload
            }
        }
        return legacyProfileContext(from: profile)
    }

    private func legacyProfileContext(from profile: ApplicantProfile) -> [String: Any] {
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

    private func buildProfilePayload(using manifest: TemplateManifest, profile: ApplicantProfile) -> [String: Any] {
        var payload: [String: Any] = [:]
        for (sectionKey, section) in manifest.sections {
            let contribution = profileContribution(for: section, profile: profile)
            if let contribution,
               isEmptyProfileContribution(contribution) == false {
                payload[sectionKey] = contribution
            }
        }
        return payload
    }

    private func profileContribution(
        for section: TemplateManifest.Section,
        profile: ApplicantProfile
    ) -> Any? {
        let contributions = contributionMap(for: section.fields, profile: profile)
        guard contributions.isEmpty == false else { return nil }

        switch section.type {
        case .string:
            return contributions.values.first
        case .array:
            if let array = contributions.values.first as? [Any] {
                return array
            }
            return contributions.values.first
        default:
            return contributions
        }
    }

    private func contributionMap(
        for descriptors: [TemplateManifest.Section.FieldDescriptor],
        profile: ApplicantProfile
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for descriptor in descriptors where descriptor.key != "*" {
            guard descriptor.repeatable == false else { continue }
            if let value = contributionValue(for: descriptor, profile: profile) {
                result[descriptor.key] = value
            }
        }
        return result
    }

    private func contributionValue(
        for descriptor: TemplateManifest.Section.FieldDescriptor,
        profile: ApplicantProfile
    ) -> Any? {
        var value: Any?
        if let binding = descriptor.binding,
           let bound = applicantProfileValue(for: binding, profile: profile) {
            value = bound
        }

        if let children = descriptor.children, children.isEmpty == false {
            var childResult: [String: Any] = [:]
            for child in children where child.key != "*" {
                guard child.repeatable == false else { continue }
                if let childValue = contributionValue(for: child, profile: profile) {
                    childResult[child.key] = childValue
                }
            }
            if childResult.isEmpty == false {
                if var existing = value as? [String: Any] {
                    existing.merge(childResult) { _, new in new }
                    value = existing
                } else if value == nil {
                    value = childResult
                } else {
                    value = childResult
                }
            }
        }

        return value
    }

    private func applicantProfileValue(
        for binding: TemplateManifest.Section.FieldDescriptor.Binding,
        profile: ApplicantProfile
    ) -> Any? {
        guard binding.source == .applicantProfile else { return nil }
        return profileValue(for: binding.path, profile: profile)
    }

    private func profileValue(for path: [String], profile: ApplicantProfile) -> Any? {
        guard let first = path.first else { return nil }
        switch first {
        case "name":
            return profile.name
        case "email":
            return profile.email
        case "phone":
            return profile.phone
        case "url", "website":
            return profile.websites
        case "address":
            return profile.address
        case "city":
            return profile.city
        case "region", "state":
            return profile.state
        case "postalCode", "zip", "code":
            return profile.zip
        case "location":
            let remainder = Array(path.dropFirst())
            if remainder.isEmpty { return nil }
            return profileValue(for: remainder, profile: profile)
        default:
            return nil
        }
    }

    private func isEmptyProfileContribution(_ value: Any) -> Bool {
        if let dict = value as? [String: Any] {
            return dict.isEmpty
        }
        if let dict = value as? [String: String] {
            return dict.isEmpty
        }
        if let array = value as? [Any] {
            return array.isEmpty
        }
        if let string = value as? String {
            return string.isEmpty
        }
        return false
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

    private func removeContactSection(from dictionary: [String: Any], manifest: TemplateManifest?) -> [String: Any] {
        guard let manifest else {
            var sanitized = dictionary
            sanitized.removeValue(forKey: "contact")
            return sanitized
        }

        let targets = collectProfileBindingTargets(in: manifest)
        guard targets.isEmpty == false else {
            var sanitized = dictionary
            sanitized.removeValue(forKey: "contact")
            return sanitized
        }

        var sanitized = dictionary
        for target in targets {
            sanitized = removeProfileValue(
                at: target.path,
                inSection: target.section,
                from: sanitized
            )
        }
        return sanitized
    }

    private func removeProfileValue(
        at path: [String],
        inSection section: String,
        from dictionary: [String: Any]
    ) -> [String: Any] {
        guard var sectionValue = dictionary[section] else { return dictionary }
        let updatedSection = removeValue(at: path, from: sectionValue)

        var sanitized = dictionary
        if let updatedSection {
            sanitized[section] = updatedSection
        } else {
            sanitized.removeValue(forKey: section)
        }
        return sanitized
    }

    private func removeValue(at path: [String], from value: Any) -> Any? {
        guard let first = path.first else { return value }
        if path.count == 1 {
            if var dict = dictionaryValue(from: value) {
                dict.removeValue(forKey: first)
                return dict.isEmpty ? nil : dict
            }
            return nil
        }

        guard var dict = dictionaryValue(from: value) else { return value }
        let remainder = Array(path.dropFirst())
        if let child = dict[first], let updated = removeValue(at: remainder, from: child) {
            dict[first] = updated
        } else {
            dict.removeValue(forKey: first)
        }
        return dict.isEmpty ? nil : dict
    }

    private func dictionaryValue(from value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            return dict
        }
        if let ordered = value as? OrderedDictionary<String, Any> {
            return Dictionary(uniqueKeysWithValues: ordered.map { ($0.key, $0.value) })
        }
        return nil
    }

    private struct ProfileBindingTarget {
        let section: String
        let path: [String]
    }

    private func collectProfileBindingTargets(in manifest: TemplateManifest) -> [ProfileBindingTarget] {
        var targets: [ProfileBindingTarget] = []
        for (sectionKey, section) in manifest.sections {
            collectProfileBindingTargets(
                in: section.fields,
                sectionKey: sectionKey,
                currentPath: [],
                targets: &targets
            )
        }
        return targets
    }

    private func collectProfileBindingTargets(
        in descriptors: [TemplateManifest.Section.FieldDescriptor],
        sectionKey: String,
        currentPath: [String],
        targets: inout [ProfileBindingTarget]
    ) {
        for descriptor in descriptors where descriptor.key != "*" {
            let nextPath = currentPath + [descriptor.key]
            if descriptor.repeatable { continue }
            if let binding = descriptor.binding,
               binding.source == .applicantProfile {
                targets.append(ProfileBindingTarget(section: sectionKey, path: nextPath))
            }
            if let children = descriptor.children, children.isEmpty == false {
                collectProfileBindingTargets(
                    in: children,
                    sectionKey: sectionKey,
                    currentPath: nextPath,
                    targets: &targets
                )
            }
        }
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
