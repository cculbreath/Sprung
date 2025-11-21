//
//  TemplateEditorView+DataManagement.swift
//  Sprung
//
//  Handles manifest and seed JSON management including profile binding logic.
//
import Foundation
import SwiftUI
import OrderedCollections
extension TemplateEditorView {

    // MARK: - Manifest Operations
    func loadManifest() {
        manifestValidationMessage = nil
        guard selectedTemplate.isEmpty == false else {
            manifestContent = TemplateEditorView.emptyManifest()
            manifestHasChanges = false
            return
        }
        let slug = selectedTemplate.lowercased()
        if let template = appEnvironment.templateStore.template(slug: slug),
           let data = template.manifestData,
           !data.isEmpty,
           let overrides = decodeManifestOverrides(from: data, slug: slug),
           let encoded = try? encodeManifestOverrides(overrides),
           let string = String(data: encoded, encoding: .utf8) {
            manifestContent = string
            manifestHasChanges = false
            return
        }
        manifestContent = TemplateEditorView.emptyManifest(slug: slug)
        manifestHasChanges = false
    }
    @discardableResult
    func saveManifest() -> Bool {
        manifestValidationMessage = nil
        guard selectedTemplate.isEmpty == false else {
            manifestValidationMessage = "Select a template first."
            return false
        }
        let slug = selectedTemplate.lowercased()
        guard let rawData = manifestContent.data(using: .utf8) else {
            manifestValidationMessage = "Unable to encode manifest text."
            return false
        }
        do {
            let overrides = try decodeManifestOrThrow(from: rawData, slug: slug)
            let encoded = try encodeManifestOverrides(overrides)
            try appEnvironment.templateStore.updateManifest(slug: slug, manifestData: encoded)
            manifestContent = String(data: encoded, encoding: .utf8) ?? manifestContent
            manifestHasChanges = false
            manifestValidationMessage = "Manifest saved."
            return true
        } catch {
            manifestValidationMessage = "Manifest validation failed: \(error.localizedDescription)"
            return false
        }
    }
    func validateManifest() {
        manifestValidationMessage = nil
        guard let data = manifestContent.data(using: .utf8) else {
            manifestValidationMessage = "Unable to encode manifest text."
            return
        }
        do {
            let overrides = try decodeManifestOrThrow(from: data, slug: selectedTemplate.lowercased())
            let encoded = try encodeManifestOverrides(overrides)
            manifestContent = String(data: encoded, encoding: .utf8) ?? manifestContent
            manifestValidationMessage = "Manifest is valid."
        } catch {
            manifestValidationMessage = "Validation failed: \(error.localizedDescription)"
        }
    }

    static func emptyManifest(slug: String = "") -> String {
        let overrides = TemplateManifestOverrides(
            sectionOrder: TemplateManifestDefaults.defaultSectionOrder,
            styling: TemplateManifestOverrides.Styling(
                fontSizes: TemplateManifestDefaults.recommendedFontSizes,
                pageMargins: TemplateManifestDefaults.recommendedPageMargins,
                includeFonts: false
            ),
            sectionVisibility: TemplateManifestDefaults.defaultSectionVisibilityDefaults,
            sectionVisibilityLabels: TemplateManifestDefaults.defaultSectionVisibilityLabels
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(overrides),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
    func decodeManifestOverrides(from data: Data, slug: String) -> TemplateManifestOverrides? {
        let decoder = JSONDecoder()
        if let overrides = try? decoder.decode(TemplateManifestOverrides.self, from: data) {
            return overrides
        }
        return nil
    }
    private func decodeManifestOrThrow(from data: Data, slug: String) throws -> TemplateManifestOverrides {
        guard let overrides = decodeManifestOverrides(from: data, slug: slug) else {
            throw ManifestError.invalidFormat
        }
        return overrides
    }
    private func encodeManifestOverrides(_ overrides: TemplateManifestOverrides) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(overrides)
    }
    private enum ManifestError: LocalizedError {
        case invalidFormat
        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Manifest must contain styling, UI, or custom field overrides."
            }
        }
    }

    // MARK: - Seed Operations
    func loadSeed() {
        seedValidationMessage = nil
        guard selectedTemplate.isEmpty == false else {
            seedContent = ""
            seedHasChanges = false
            return
        }
        let slug = selectedTemplate.lowercased()
        if let template = appEnvironment.templateStore.template(slug: slug),
           let seed = appEnvironment.templateSeedStore.seed(for: template),
           let formatted = prettyJSONString(from: seed.seedData) {
            seedContent = formatted
            seedHasChanges = false
            return
        }
        seedContent = ""
        seedHasChanges = false
    }
    @discardableResult
    func saveSeed() -> Bool {
        seedValidationMessage = nil
        guard selectedTemplate.isEmpty == false else {
            seedValidationMessage = "Select a template first."
            return false
        }
        let slug = selectedTemplate.lowercased()
        guard let template = appEnvironment.templateStore.template(slug: slug) else {
            seedValidationMessage = "Template not found."
            return false
        }
        guard let data = seedContent.data(using: .utf8) else {
            seedValidationMessage = "Unable to encode seed JSON."
            return false
        }
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard var seedDictionary = jsonObject as? [String: Any] else {
                seedValidationMessage = "Seed must be a JSON object."
                return false
            }
            let originalSeedDictionary = seedDictionary
            let manifest = TemplateManifestLoader.manifest(for: template)
            var profileChanges: [ProfileUpdateChange] = []
            let profile = appEnvironment.applicantProfileStore.currentProfile()
            var removalTargets: [(String, [String])] = []
            var processedPaths: Set<String> = []
            var updatedProfileKeyPaths: Set<String> = []
            if let manifest {
                let bindings = manifest.applicantProfileBindings()
                if bindings.isEmpty == false {
                    for binding in bindings {
                        let bindingKey = makeBindingKey(section: binding.section, path: binding.path)
                        processedPaths.insert(bindingKey)
                        guard let seedValue = extractStringValue(
                            section: binding.section,
                            path: binding.path,
                            from: seedDictionary
                        ), seedValue.isEmpty == false else { continue }
                    if let field = profileField(for: binding.binding.path) {
                        let trimmedSeed = seedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        let currentValue = profile[keyPath: field.keyPath]
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let profileKey = String(describing: field.keyPath)
                        if trimmedSeed != currentValue,
                           updatedProfileKeyPaths.insert(profileKey).inserted {
                            profileChanges.append(
                                ProfileUpdateChange(
                                    label: field.label,
                                    keyPath: field.keyPath,
                                    newValue: trimmedSeed,
                                    currentValue: currentValue
                                )
                            )
                        }
                        removalTargets.append((binding.section, binding.path))
                    }
                }
            }
            }
            for defaultPath in TemplateManifest.defaultApplicantProfilePaths {
                let bindingKey = makeBindingKey(section: defaultPath.section, path: defaultPath.path)
                guard processedPaths.contains(bindingKey) == false else { continue }
                guard let seedValue = extractStringValue(
                    section: defaultPath.section,
                    path: defaultPath.path,
                    from: seedDictionary
                ), seedValue.isEmpty == false else { continue }
                if let field = profileField(for: defaultPath.path) {
                    let trimmedSeed = seedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let currentValue = profile[keyPath: field.keyPath]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let profileKey = String(describing: field.keyPath)
                    if trimmedSeed != currentValue,
                       updatedProfileKeyPaths.insert(profileKey).inserted {
                        profileChanges.append(
                            ProfileUpdateChange(
                                label: field.label,
                                keyPath: field.keyPath,
                                newValue: trimmedSeed,
                                currentValue: currentValue
                            )
                        )
                    }
                }
                removalTargets.append((defaultPath.section, defaultPath.path))
                processedPaths.insert(bindingKey)
            }
            if removalTargets.isEmpty == false {
                seedDictionary = removeProfileValues(removing: removalTargets, from: seedDictionary)
            }
            seedDictionary.removeValue(forKey: "contact")
            let allowedRemovalPaths = removalTargets
                .map { pathDescription(for: [$0.0] + $0.1) }
                + ["contact"]
            let unexpectedRemovalPaths = unexpectedSeedRemovals(
                original: originalSeedDictionary,
                sanitized: seedDictionary,
                allowedPaths: allowedRemovalPaths
            )
            guard unexpectedRemovalPaths.isEmpty else {
                let joined = unexpectedRemovalPaths.joined(separator: ", ")
                seedValidationMessage = "Seed not saved. Remove or reconfigure unsupported key(s): \(joined)."
                return false
            }
            guard let formatted = prettyJSONString(from: seedDictionary) else {
                seedValidationMessage = "Seed must be valid JSON."
                return false
            }
            appEnvironment.templateSeedStore.upsertSeed(
                slug: slug,
                jsonString: formatted,
                attachTo: template
            )
            seedContent = formatted
            seedHasChanges = false
            seedValidationMessage = "Seed saved."
            if profileChanges.isEmpty == false {
                pendingProfileUpdate = ProfileUpdatePrompt(changes: profileChanges)
            }
            return true
        } catch {
            seedValidationMessage = "Seed validation failed: \(error.localizedDescription)"
            return false
        }
    }
    func promoteCurrentResumeToSeed() {
        seedValidationMessage = nil
        guard selectedTemplate.isEmpty == false else { return }
        guard let resume = selectedResume else { return }
        do {
            let context = try ResumeTemplateDataBuilder.buildContext(from: resume)
            guard let formatted = prettyJSONString(from: context) else {
                seedValidationMessage = "Unable to serialize resume context."
                return
            }
            seedContent = formatted
            seedHasChanges = true
            seedValidationMessage = "Seed staged from selected resume."
        } catch {
            seedValidationMessage = "Failed to build context: \(error.localizedDescription)"
        }
    }
    func validateSeedFormat() {
        seedValidationMessage = nil
        guard let data = seedContent.data(using: .utf8) else {
            seedValidationMessage = "Unable to encode seed JSON."
            return
        }
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard jsonObject is [String: Any] else {
                seedValidationMessage = "Seed must be a JSON object."
                return
            }
            seedValidationMessage = "Seed is valid."
        } catch {
            seedValidationMessage = "Seed validation failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Profile Field Mapping
    private func profileField(for path: [String]) -> ProfileField? {
        var remaining = ArraySlice(path)
        while let key = remaining.first {
            switch key {
            case "name":
                return ProfileField(label: "Name", keyPath: \ApplicantProfile.name)
            case "label":
                return ProfileField(label: "Professional Label", keyPath: \ApplicantProfile.label)
            case "summary":
                return ProfileField(label: "Summary", keyPath: \ApplicantProfile.summary)
            case "email":
                return ProfileField(label: "Email", keyPath: \ApplicantProfile.email)
            case "phone":
                return ProfileField(label: "Phone", keyPath: \ApplicantProfile.phone)
            case "url", "website":
                return ProfileField(label: "Website", keyPath: \ApplicantProfile.websites)
            case "address":
                return ProfileField(label: "Address", keyPath: \ApplicantProfile.address)
            case "city":
                return ProfileField(label: "City", keyPath: \ApplicantProfile.city)
            case "region", "state":
                return ProfileField(label: "State", keyPath: \ApplicantProfile.state)
            case "postalCode", "zip", "code":
                return ProfileField(label: "Postal Code", keyPath: \ApplicantProfile.zip)
            case "countryCode":
                return ProfileField(label: "Country Code", keyPath: \ApplicantProfile.countryCode)
            case "location":
                remaining = remaining.dropFirst()
                continue
            default:
                return nil
            }
        }
        return nil
    }
    private func extractStringValue(
        section: String,
        path: [String],
        from dictionary: [String: Any]
    ) -> String? {
        guard let sectionValue = dictionary[section] else { return nil }
        guard let raw = valueAtPath(path, in: sectionValue) else { return nil }
        if let string = raw as? String {
            return string
        }
        if let number = raw as? NSNumber {
            return number.stringValue
        }
        return nil
    }
    private func valueAtPath(_ path: [String], in value: Any) -> Any? {
        guard let first = path.first else { return value }
        if let dict = dictionaryValue(from: value) {
            let remainder = Array(path.dropFirst())
            guard let child = dict[first] else { return nil }
            return remainder.isEmpty ? child : valueAtPath(remainder, in: child)
        }
        return nil
    }
    private func removeProfileValues(
        removing targets: [(String, [String])],
        from dictionary: [String: Any]
    ) -> [String: Any] {
        targets.reduce(dictionary) { partial, target in
            removeProfileValue(at: target.1, inSection: target.0, from: partial)
        }
    }
    private func removeProfileValue(
        at path: [String],
        inSection section: String,
        from dictionary: [String: Any]
    ) -> [String: Any] {
        guard let sectionValue = dictionary[section] else { return dictionary }
        let updated = removeValue(at: path, from: sectionValue)
        var sanitized = dictionary
        if let updated {
            sanitized[section] = updated
        } else {
            sanitized.removeValue(forKey: section)
        }
        return sanitized
    }
    private func makeBindingKey(section: String, path: [String]) -> String {
        ([section] + path).joined(separator: ".")
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
    private func dictionaryValue(from value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let dict = value as? [String: Any] {
            return dict
        }
        if let ordered = value as? OrderedDictionary<String, Any> {
            return Dictionary(uniqueKeysWithValues: ordered.map { ($0.key, $0.value) })
        }
        return nil
    }
    private func unexpectedSeedRemovals(
        original: [String: Any],
        sanitized: [String: Any],
        allowedPaths: [String]
    ) -> [String] {
        let removals = removedKeyPaths(
            original: original,
            sanitized: sanitized,
            currentPath: []
        )
        guard removals.isEmpty == false else { return [] }
        return removals
            .map { pathDescription(for: $0) }
            .filter { path in
                if allowedPaths.contains(path) {
                    return false
                }
                if allowedPaths.contains(where: { $0.hasPrefix(path + ".") }) {
                    return false
                }
                return true
            }
    }
    private func removedKeyPaths(
        original: Any,
        sanitized: Any?,
        currentPath: [String]
    ) -> [[String]] {
        guard let originalDict = original as? [String: Any] else {
            return []
        }
        guard let sanitizedDict = sanitized as? [String: Any] else {
            return [currentPath].filter { $0.isEmpty == false }
        }
        var missing: [[String]] = []
        for (key, value) in originalDict {
            let nextPath = currentPath + [key]
            if sanitizedDict[key] == nil {
                missing.append(nextPath)
            } else {
                missing.append(contentsOf: removedKeyPaths(
                    original: value,
                    sanitized: sanitizedDict[key],
                    currentPath: nextPath
                ))
            }
        }
        return missing
    }
    private func pathDescription(for path: [String]) -> String {
        path.joined(separator: ".")
    }
    func applyProfileUpdate(_ prompt: ProfileUpdatePrompt) {
        var profile = appEnvironment.applicantProfileStore.currentProfile()
        for change in prompt.changes {
            profile[keyPath: change.keyPath] = change.newValue
        }
        appEnvironment.applicantProfileStore.save(profile)
        pendingProfileUpdate = nil
        seedValidationMessage = "Seed saved. Profile updated."
        refreshTemplatePreview(force: true)
    }

    // MARK: - JSON Utilities
    func prettyJSONString(from data: Data) -> String? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return prettyJSONString(from: jsonObject)
    }
    func prettyJSONString(from object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Supporting Types
    struct ProfileUpdateChange {
        let label: String
        let keyPath: WritableKeyPath<ApplicantProfile, String>
        let newValue: String
        let currentValue: String
    }
    struct ProfileUpdatePrompt {
        let changes: [ProfileUpdateChange]
        var message: String {
            changes.map { change in
                let previous = change.currentValue.isEmpty ? "(empty)" : change.currentValue
                return "• \(change.label): \(previous) → \(change.newValue)"
            }.joined(separator: "\n")
        }
    }
    private struct ProfileField {
        let label: String
        let keyPath: WritableKeyPath<ApplicantProfile, String>
    }
}
