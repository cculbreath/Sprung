//
//  TemplateEditorView+Persistence.swift
//  Sprung
//

import Foundation
import SwiftUI
import OrderedCollections

extension TemplateEditorView {
    func loadTemplateAssets() {
        guard selectedTemplate.isEmpty == false else {
            htmlContent = ""
            textContent = ""
            htmlDraft = nil
            textDraft = nil
            htmlHasChanges = false
            textHasChanges = false
            return
        }

        let slug = selectedTemplate.lowercased()
        htmlContent = loadTemplateContent(slug: slug, format: "html")
        textContent = loadTemplateContent(slug: slug, format: "txt")
        htmlDraft = htmlContent
        textDraft = textContent
        htmlHasChanges = false
        textHasChanges = false
    }

    private func loadTemplateContent(slug: String, format: String) -> String {
        guard let template = appEnvironment.templateStore.template(slug: slug) else {
            return ""
        }
        if format == "html" {
            return template.htmlContent ?? ""
        }
        if format == "txt" {
            return template.textContent ?? ""
        }
        return ""
    }

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

    @discardableResult
    func saveTemplateAssets() -> Bool {
        guard selectedTemplate.isEmpty == false else { return true }

        let slug = selectedTemplate.lowercased()
        let htmlToSave = htmlHasChanges ? htmlContent : nil
        let textToSave = textHasChanges ? textContent : nil

        guard htmlToSave != nil || textToSave != nil else { return true }

        let existingTemplate = appEnvironment.templateStore.template(slug: slug)
        let resolvedName = existingTemplate?.name ?? selectedTemplate.capitalized
        let resolvedIsCustom = existingTemplate?.isCustom ?? true

        appEnvironment.templateStore.upsertTemplate(
            slug: slug,
            name: resolvedName,
            htmlContent: htmlToSave,
            textContent: textToSave,
            isCustom: resolvedIsCustom
        )

        if htmlToSave != nil {
            htmlHasChanges = false
            htmlDraft = htmlContent
        }

        if textToSave != nil {
            textHasChanges = false
            textDraft = textContent
        }

        return true
    }

    func loadAvailableTemplates() {
        let templates = appEnvironment.templateStore.templates()
        availableTemplates = templates.map { $0.slug }.sorted()
        appEnvironment.requiresTemplateSetup = availableTemplates.isEmpty

        if availableTemplates.isEmpty {
            defaultTemplateSlug = nil
            selectedTemplate = ""
        } else {
            defaultTemplateSlug = appEnvironment.templateStore.defaultTemplate()?.slug
            if selectedTemplate.isEmpty || !availableTemplates.contains(selectedTemplate) {
                if let defaultTemplateSlug,
                   availableTemplates.contains(defaultTemplateSlug) {
                    selectedTemplate = defaultTemplateSlug
                } else {
                    selectedTemplate = availableTemplates.first ?? ""
                }
            }
        }
    }

    func addNewTemplate() {
        let trimmedName = newTemplateName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedName.isEmpty, !availableTemplates.contains(trimmedName) else {
            newTemplateName = ""
            return
        }

        let initialHTML = createEmptyTemplate(format: "html")
        let initialText = createEmptyTemplate(format: "txt")
        let shouldBeDefault = availableTemplates.isEmpty
        appEnvironment.templateStore.upsertTemplate(
            slug: trimmedName,
            name: trimmedName.capitalized,
            htmlContent: initialHTML,
            textContent: initialText,
            isCustom: true,
            markAsDefault: shouldBeDefault
        )

        loadAvailableTemplates()
        selectedTemplate = trimmedName
        if shouldBeDefault {
            defaultTemplateSlug = trimmedName
        }
        appEnvironment.requiresTemplateSetup = availableTemplates.isEmpty
        newTemplateName = ""
        loadTemplateAssets()
        loadManifest()
        loadSeed()
    }

    func duplicateTemplate(slug: String) {
        guard let source = appEnvironment.templateStore.template(slug: slug) else { return }

        var candidateSlug = slug + "-copy"
        var index = 2
        while availableTemplates.contains(candidateSlug) {
            candidateSlug = slug + "-copy-\(index)"
            index += 1
        }

        let candidateName = source.name + " Copy" + (index > 2 ? " \(index - 1)" : "")

        appEnvironment.templateStore.upsertTemplate(
            slug: candidateSlug,
            name: candidateName,
            htmlContent: source.htmlContent,
            textContent: source.textContent,
            cssContent: source.cssContent,
            isCustom: true
        )

        if let manifest = source.manifestData {
            try? appEnvironment.templateStore.updateManifest(slug: candidateSlug, manifestData: manifest)
        }

        if let seed = appEnvironment.templateSeedStore.seed(forSlug: slug),
           let jsonString = String(data: seed.seedData, encoding: .utf8) {
            appEnvironment.templateSeedStore.upsertSeed(slug: candidateSlug, jsonString: jsonString)
        }

        loadAvailableTemplates()
        selectedTemplate = candidateSlug
        defaultTemplateSlug = appEnvironment.templateStore.defaultTemplate()?.slug
        loadTemplateAssets()
        loadManifest()
        loadSeed()
    }

    func deleteTemplate(slug: String) {
        guard availableTemplates.count > 1 else { return }

        appEnvironment.templateStore.deleteTemplate(slug: slug.lowercased())
        appEnvironment.templateSeedStore.deleteSeed(forSlug: slug.lowercased())

        loadAvailableTemplates()
        defaultTemplateSlug = appEnvironment.templateStore.defaultTemplate()?.slug

        if selectedTemplate == slug {
            if let defaultTemplateSlug,
               availableTemplates.contains(defaultTemplateSlug) {
                selectedTemplate = defaultTemplateSlug
            } else {
                selectedTemplate = availableTemplates.first ?? ""
            }
        }

        appEnvironment.requiresTemplateSetup = availableTemplates.isEmpty
        templatePendingDeletion = nil
        loadTemplateAssets()
        loadManifest()
        loadSeed()
    }
    
    func renameTemplate(slug: String, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let template = appEnvironment.templateStore.template(slug: slug) else { return }
        
        // Simple approach: Just update the template name using upsertTemplate
        // (Now that we fixed the bug in TemplateStore where name wasn't being updated)
        appEnvironment.templateStore.upsertTemplate(
            slug: slug,
            name: trimmedName,
            htmlContent: template.htmlContent,
            textContent: template.textContent,
            cssContent: template.cssContent,
            isCustom: template.isCustom
        )
        
        // Refresh the templates list  
        loadAvailableTemplates()
    }

    @discardableResult
    func saveAllChanges() -> Bool {
        var success = saveTemplateAssets()
        if manifestHasChanges {
            success = saveManifest() && success
        }
        if seedHasChanges {
            success = saveSeed() && success
        }
        return success
    }

    func performRefresh() {
        if saveAllChanges() {
            refreshTemplatePreview()
            refreshCustomFieldWarnings()
        }
    }

    func saveAndClose() {
        guard saveAllChanges() else { return }
        closeEditor()
    }

    func closeWithoutSaving() {
        revertAllChanges()
        closeEditor()
    }

    private func discardPendingChanges() {
        htmlHasChanges = false
        textHasChanges = false
        manifestHasChanges = false
        seedHasChanges = false
        manifestValidationMessage = nil
        seedValidationMessage = nil
    }

    func revertAllChanges() {
        discardPendingChanges()
        loadTemplateAssets()
        loadManifest()
       loadSeed()
       showOverlay = false
       overlayPDFDocument = nil
       overlayFilename = nil
       overlayPageCount = 0
       refreshTemplatePreview()
        refreshCustomFieldWarnings()
    }

    func handleTemplateSelectionChange(previousSlug: String) {
        guard selectedTemplate != previousSlug else { return }
        let previous = previousSlug
        if saveAllChanges() == false {
            selectedTemplate = previous
            return
        }
        loadTemplateAssets()
       loadManifest()
       loadSeed()
       refreshTemplatePreview()
        refreshCustomFieldWarnings()
    }

    func handleTabSelectionChange(newValue: TemplateEditorTab) {
        textEditorInsertion = nil
        switch newValue {
        case .pdfTemplate:
            if htmlDraft == nil {
                htmlDraft = htmlContent
            }
        case .txtTemplate:
            if textDraft == nil {
                textDraft = textContent
            }
        case .manifest:
            if manifestContent.isEmpty {
                loadManifest()
            }
        case .seed:
            if seedContent.isEmpty {
                loadSeed()
            }
        }
    }

    func createEmptyTemplate(format: String) -> String {
        switch format {
        case "html":
            return ""
        case "txt":
            return ""
        default:
            return ""
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

    private func decodeManifestOverrides(from data: Data, slug: String) -> TemplateManifestOverrides? {
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

    func refreshCustomFieldWarnings() {
        guard selectedTemplate.isEmpty == false else {
            customFieldWarningMessage = nil
            return
        }

        let slug = selectedTemplate.lowercased()
        let baseManifest = TemplateManifestDefaults.baseManifest(for: slug)

        let trimmedManifest = manifestContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedManifest: TemplateManifest

        if trimmedManifest.isEmpty {
            resolvedManifest = baseManifest
        } else if let data = manifestContent.data(using: .utf8),
                  let overrides = decodeManifestOverrides(from: data, slug: slug) {
            resolvedManifest = TemplateManifestDefaults.apply(
                overrides: overrides,
                to: baseManifest,
                slug: slug
            )
        } else {
            customFieldWarningMessage = "Fix manifest JSON to verify custom fields coverage."
            return
        }

        let manifestKeys = resolvedManifest.customFieldKeyPaths()

        let trimmedSeed = seedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let seedKeys: Set<String>
        if trimmedSeed.isEmpty {
            seedKeys = []
        } else if let data = seedContent.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            seedKeys = TemplateEditorView.collectCustomFieldKeys(from: jsonObject)
        } else {
            customFieldWarningMessage = "Fix default values JSON to verify custom fields coverage."
            return
        }

        let definedKeys = manifestKeys.union(seedKeys)
        guard definedKeys.isEmpty == false else {
            customFieldWarningMessage = nil
            return
        }

        let usedKeys = TemplateEditorView.extractCustomFieldReferences(from: textContent)
        let missing = definedKeys.subtracting(usedKeys)

        if missing.isEmpty {
            customFieldWarningMessage = nil
        } else {
            let list = missing.sorted().joined(separator: ", ")
            customFieldWarningMessage = "Text template omits custom fields: \(list). They will be missing from plain-text resumes and LLM outputs."
        }
    }

    private static let customFieldReferenceRegex: NSRegularExpression = {
        let pattern = #"custom(?:\.[A-Za-z0-9_\-]+)+"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    static func extractCustomFieldReferences(from template: String) -> Set<String> {
        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        let matches = customFieldReferenceRegex.matches(in: template, options: [], range: range)
        return Set(matches.compactMap { match in
            guard let matchRange = Range(match.range, in: template) else { return nil }
            return String(template[matchRange])
        })
    }

    static func collectCustomFieldKeys(from dictionary: [String: Any]) -> Set<String> {
        guard let customValue = dictionary["custom"] else { return [] }
        var results: Set<String> = []
        collectCustomFieldKeys(from: customValue, currentPath: ["custom"], accumulator: &results)
        return results
    }

    private static func collectCustomFieldKeys(
        from value: Any,
        currentPath: [String],
        accumulator: inout Set<String>
    ) {
        if let dict = value as? [String: Any] {
            for (key, entry) in dict {
                collectCustomFieldKeys(
                    from: entry,
                    currentPath: currentPath + [key],
                    accumulator: &accumulator
                )
            }
            return
        }

        if let array = value as? [Any] {
            accumulator.insert(currentPath.joined(separator: "."))
            return
        }

        accumulator.insert(currentPath.joined(separator: "."))
    }
}
