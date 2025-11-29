import Foundation
import OrderedCollections
struct ResumeTemplateContextBuilder {
    private let templateSeedStore: TemplateSeedStore
    private let experienceDefaultsStore: ExperienceDefaultsStore
    init(
        templateSeedStore: TemplateSeedStore,
        experienceDefaultsStore: ExperienceDefaultsStore
    ) {
        self.templateSeedStore = templateSeedStore
        self.experienceDefaultsStore = experienceDefaultsStore
    }
    @MainActor
    func buildContext(
        for template: Template,
        applicantProfile: ApplicantProfile
    ) -> [String: Any]? {
        let manifest = TemplateManifestLoader.manifest(for: template)
        let seedJSON = templateSeedStore.seed(for: template)?.jsonString ?? ""
        let seed = Self.parseJSON(from: seedJSON)
        let sanitizedSeed = removeContactSection(from: seed, manifest: manifest)
        let experienceDefaults = experienceDefaultsStore.currentDefaults()
        let experienceSeed = ExperienceDefaultsEncoder.makeSeedDictionary(from: experienceDefaults)
        let sanitizedExperience = removeContactSection(from: experienceSeed, manifest: manifest)
        var context = manifest?.makeDefaultContext() ?? [:]
        merge(into: &context, with: sanitizedExperience)
        merge(into: &context, with: sanitizedSeed)
        merge(into: &context, with: profileContext(from: applicantProfile, manifest: manifest))
        addMissingKeys(from: sanitizedExperience, to: &context)
        addMissingKeys(from: sanitizedSeed, to: &context)
        if let manifest {
            context = SeedContextNormalizer(manifest: manifest).normalize(context)
        }
        if Logger.isVerboseEnabled {
            if let basics = context["basics"] as? [String: Any] {
                Logger.verbose("ResumeTemplateContextBuilder: basics keys = \(Array(basics.keys))", category: .general)
                if let summary = basics["summary"] {
                    Logger.verbose("ResumeTemplateContextBuilder: basics.summary = \(summary)", category: .general)
                } else {
                    Logger.verbose("ResumeTemplateContextBuilder: basics.summary missing", category: .general)
                }
            } else {
                Logger.verbose("ResumeTemplateContextBuilder: basics section missing", category: .general)
            }
        }
        return context
    }
    // MARK: - Private helpers
    private func profileContext(from profile: ApplicantProfile, manifest: TemplateManifest?) -> [String: Any] {
        let fallbackContext = modernProfileContext(from: profile)
        guard let manifest else {
            return fallbackContext
        }
        let payload = buildProfilePayload(using: manifest, profile: profile)
        guard payload.isEmpty == false else {
            return fallbackContext
        }
        return mergeProfilePayload(payload, fallback: fallbackContext)
    }
    private func modernProfileContext(from profile: ApplicantProfile) -> [String: Any] {
        var location: [String: Any] = [:]
        if let value = sanitizedString(profile.address) { location["address"] = value }
        if let value = sanitizedString(profile.city) { location["city"] = value }
        if let value = sanitizedString(profile.state) {
            location["state"] = value
            location["region"] = value
        }
        if let value = sanitizedString(profile.zip) { location["postalCode"] = value }
        if let value = sanitizedString(profile.countryCode) { location["countryCode"] = value }
        var basics: [String: Any] = [:]
        if let value = sanitizedString(profile.name) { basics["name"] = value }
        if let value = sanitizedString(profile.label) { basics["label"] = value }
        if let value = sanitizedString(profile.summary) { basics["summary"] = value }
        if let value = sanitizedString(profile.email) { basics["email"] = value }
        if let value = sanitizedString(profile.phone) { basics["phone"] = value }
        if let value = sanitizedString(profile.websites) { basics["website"] = value }
        if let picture = profile.pictureDataURL() {
            basics["picture"] = picture
        }
        if !location.isEmpty { basics["location"] = location }
        let profiles = makeProfilesPayload(from: profile)
        if profiles.isEmpty == false {
            basics["profiles"] = profiles
        }
        var context: [String: Any] = [:]
        if !basics.isEmpty {
            context["basics"] = basics
        }
        return context
    }
    private func buildProfilePayload(using manifest: TemplateManifest, profile: ApplicantProfile) -> [String: Any] {
        var payload: [String: Any] = [:]
        let bindings = manifest.applicantProfileBindings()
        for binding in bindings {
            guard let value = applicantProfileValue(for: binding.binding, profile: profile),
                  isEmptyProfileContribution(value) == false else { continue }
            let updatedSection = settingProfileValue(
                value,
                for: binding.path,
                existing: payload[binding.section]
            )
            payload[binding.section] = updatedSection
        }
        return payload
    }
    private func mergeProfilePayload(_ payload: [String: Any], fallback: [String: Any]) -> [String: Any] {
        var merged = payload
        for (key, fallbackValue) in fallback {
            guard let existing = merged[key] else {
                merged[key] = fallbackValue
                continue
            }
            if let existingDict = existing as? [String: Any],
               let fallbackDict = fallbackValue as? [String: Any] {
                merged[key] = mergeDictionaries(existingDict, fallback: fallbackDict)
                continue
            }
            if let existingArray = existing as? [Any],
               existingArray.isEmpty,
               let fallbackArray = fallbackValue as? [Any] {
                merged[key] = fallbackArray
            }
        }
        return merged
    }
    private func mergeDictionaries(_ existing: [String: Any], fallback: [String: Any]) -> [String: Any] {
        var merged = existing
        for (key, fallbackValue) in fallback where merged[key] == nil {
            merged[key] = fallbackValue
        }
        return merged
    }
    private func applicantProfileValue(
        for binding: TemplateManifest.Section.FieldDescriptor.Binding,
        profile: ApplicantProfile
    ) -> Any? {
        guard binding.source == .applicantProfile else { return nil }
        return profileValue(for: binding.path, profile: profile)
    }
    private func sanitizedString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private func makeProfilesPayload(from profile: ApplicantProfile) -> [[String: String]] {
        profile.profiles.compactMap { social -> [String: String]? in
            var entry: [String: String] = [:]
            if let value = sanitizedString(social.network) { entry["network"] = value }
            if let value = sanitizedString(social.username) { entry["username"] = value }
            if let value = sanitizedString(social.url) { entry["url"] = value }
            return entry.isEmpty ? nil : entry
        }
    }
    private func profileValue(for path: [String], profile: ApplicantProfile) -> Any? {
        guard let first = path.first else { return nil }
        switch first {
        case "name":
            return profile.name
        case "label":
            return sanitizedString(profile.label)
        case "summary":
            return sanitizedString(profile.summary)
        case "email":
            return profile.email
        case "phone":
            return profile.phone
        case "url", "website":
            return profile.websites
        case "picture", "image":
            return profile.pictureDataURL()
        case "address":
            return profile.address
        case "city":
            return profile.city
        case "region", "state":
            return profile.state
        case "postalCode", "zip", "code":
            return profile.zip
        case "countryCode":
            return profile.countryCode
        case "profiles":
            let payload = makeProfilesPayload(from: profile)
            guard payload.isEmpty == false else { return nil }
            let remainder = Array(path.dropFirst())
            guard let next = remainder.first else { return payload }
            if next == "*" {
                let finalKey = remainder.dropFirst().first
                guard let key = finalKey else { return payload }
                return payload.compactMap { $0[key] }
            }
            return payload.compactMap { $0[next] }
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
    private func settingProfileValue(
        _ value: Any,
        for path: [String],
        existing: Any?
    ) -> Any {
        guard let first = path.first else { return value }
        var dictionary = dictionaryValue(from: existing as Any) ?? [:]
        let remainder = Array(path.dropFirst())
        if remainder.isEmpty {
            dictionary[first] = value
        } else {
            let current = dictionary[first]
            dictionary[first] = settingProfileValue(value, for: remainder, existing: current)
        }
        return dictionary
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
            if shouldReplaceDictionary(base: baseDict, with: overlayDict) {
                return overlayDict
            }
            var merged = baseDict
            merge(into: &merged, with: overlayDict)
            return merged
        case let (baseArray as [Any], overlayArray as [Any]):
            guard overlayArray.isEmpty == false else { return baseArray }
            if let merged = mergeCustomOverlay(baseArray: baseArray, overlayArray: overlayArray) {
                return merged
            }
            return overlayArray
        case (nil, let overlayArray as [Any]):
            return overlayArray
        case (_, let overlayArray as [Any]):
            return overlayArray.isEmpty ? (base ?? overlayArray) : overlayArray
        case (_, let overlayString as String):
            return overlayString.isEmpty ? (base ?? overlayString) : overlayString
        default:
            return overlay
        }
    }
    private func mergeCustomOverlay(baseArray: [Any], overlayArray: [Any]) -> [Any]? {
        var result = baseArray
        var didMerge = false
        for (position, element) in overlayArray.enumerated() {
            guard let overlayDict = element as? [String: Any] else { return nil }
            guard overlayDict.keys.allSatisfy({ $0 == "custom" || $0 == "__key" }) else { return nil }
            guard let overlayCustom = overlayDict["custom"] else { continue }
            let targetIndex: Int?
            if let identifier = overlayDict["__key"] as? String {
                targetIndex = baseArray.enumerated().first(where: { entry in
                    guard let baseDict = dictionaryValue(from: entry.element) else { return false }
                    if let key = baseDict["__key"] as? String, key == identifier { return true }
                    if let title = baseDict["title"] as? String, title == identifier { return true }
                    return false
                })?.offset
            } else {
                targetIndex = position < result.count ? position : nil
            }
            if let index = targetIndex,
               index < result.count,
               var baseDict = dictionaryValue(from: result[index]) {
                baseDict["custom"] = mergeValue(baseDict["custom"], with: overlayCustom)
                result[index] = baseDict
                didMerge = true
            } else {
                var newEntry: [String: Any] = ["custom": overlayCustom]
                if let identifier = overlayDict["__key"] as? String {
                    newEntry["__key"] = identifier
                }
                result.append(newEntry)
                didMerge = true
            }
        }
        return didMerge ? result : nil
    }
    private func shouldReplaceDictionary(base: [String: Any], with overlay: [String: Any]) -> Bool {
        guard overlay.isEmpty == false else { return true }
        if overlay.values.allSatisfy(isScalarValue) && base.values.allSatisfy(isScalarValue) {
            return true
        }
        return false
    }
    private func isScalarValue(_ value: Any) -> Bool {
        switch value {
        case is String, is NSString, is NSNumber, is NSNull:
            return true
        default:
            return false
        }
    }
    private func addMissingKeys(from source: [String: Any], to context: inout [String: Any]) {
        for (key, value) in source where context[key] == nil {
            context[key] = value
        }
    }
    private func removeContactSection(from dictionary: [String: Any], manifest: TemplateManifest?) -> [String: Any] {
        var sanitized = dictionary
        var processedKeys: Set<String> = []
        if let manifest {
            let targets = manifest.applicantProfileBindings()
            for target in targets {
                sanitized = removeProfileValue(
                    at: target.path,
                    inSection: target.section,
                    from: sanitized
                )
                processedKeys.insert(makeBindingKey(section: target.section, path: target.path))
            }
        }
        sanitized = removeDefaultContactFields(from: sanitized, skipping: processedKeys)
        sanitized.removeValue(forKey: "contact")
        return sanitized
    }
    private func removeProfileValue(
        at path: [String],
        inSection section: String,
        from dictionary: [String: Any]
    ) -> [String: Any] {
        guard let sectionValue = dictionary[section] else { return dictionary }
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
    private func removeDefaultContactFields(
        from dictionary: [String: Any],
        skipping processed: Set<String>
    ) -> [String: Any] {
        TemplateManifest.defaultApplicantProfilePaths.reduce(dictionary) { partial, path in
            let key = makeBindingKey(section: path.section, path: path.path)
            guard processed.contains(key) == false else { return partial }
            return removeProfileValue(at: path.path, inSection: path.section, from: partial)
        }
    }
    private func makeBindingKey(section: String, path: [String]) -> String {
        ([section] + path).joined(separator: ".")
    }
}
// MARK: - Seed normalization
private struct SeedContextNormalizer {
    let manifest: TemplateManifest
    func normalize(_ context: [String: Any]) -> [String: Any] {
        var normalized = context
        for key in manifest.sectionOrder {
            guard let section = manifest.section(for: key),
                  let rawValue = normalized[key] else { continue }
            normalized[key] = normalizeValue(rawValue, for: section)
        }
        // Include any sections not listed in sectionOrder
        for (key, value) in context where normalized[key] == nil {
            if let section = manifest.section(for: key) {
                normalized[key] = normalizeValue(value, for: section)
            } else {
                normalized[key] = value
            }
        }
        return normalized
    }
    private func normalizeValue(
        _ value: Any,
        for section: TemplateManifest.Section
    ) -> Any {
        switch section.type {
        case .array:
            return normalizeArraySection(value)
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
    private func normalizeArraySection(_ value: Any) -> Any {
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
           !children.contains(where: { $0.key == "title" }),
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
