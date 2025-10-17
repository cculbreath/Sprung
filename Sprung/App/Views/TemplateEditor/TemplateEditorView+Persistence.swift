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
        let folderName = selectedTemplate
        htmlContent = loadTemplateContent(slug: slug, folder: folderName, format: "html")
        textContent = loadTemplateContent(slug: slug, folder: folderName, format: "txt")
        htmlDraft = htmlContent
        textDraft = textContent
        htmlHasChanges = false
        textHasChanges = false
    }

    private func loadTemplateContent(slug: String, folder: String, format: String) -> String {
        if let template = appEnvironment.templateStore.template(slug: slug) {
            if format == "html", let stored = template.htmlContent {
                return stored
            }
            if format == "txt", let stored = template.textContent {
                return stored
            }
        }

        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let templatePath = documentsPath
                .appendingPathComponent("Sprung")
                .appendingPathComponent("Templates")
                .appendingPathComponent(folder)
                .appendingPathComponent("\(folder)-template.\(format)")
            if let content = try? String(contentsOf: templatePath, encoding: .utf8) {
                return content
            }
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
           let formatted = prettyJSONString(from: data) {
            manifestContent = formatted
            manifestHasChanges = false
            return
        }

        if let documentsContent = manifestStringFromDocuments(slug: slug) {
            manifestContent = documentsContent
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
            let jsonObject = try JSONSerialization.jsonObject(with: rawData)
            guard let formatted = prettyJSONString(from: jsonObject),
                  let data = formatted.data(using: .utf8) else {
                manifestValidationMessage = "Manifest must be a valid JSON object."
                return false
            }

            // Decode to ensure it matches expected manifest structure
            _ = try JSONDecoder().decode(TemplateManifest.self, from: data)

            try appEnvironment.templateStore.updateManifest(slug: slug, manifestData: data)
            manifestContent = formatted
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
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard let formatted = prettyJSONString(from: jsonObject),
                  let normalized = formatted.data(using: .utf8) else {
                manifestValidationMessage = "Manifest must be a valid JSON object."
                return
            }
            _ = try JSONDecoder().decode(TemplateManifest.self, from: normalized)
            manifestContent = formatted
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
                        }

                        removalTargets.append((binding.section, binding.path))
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
        guard let first = path.first else { return nil }
        switch first {
        case "name":
            return ProfileField(label: "Name", keyPath: \ApplicantProfile.name)
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
        case "location":
            let remainder = Array(path.dropFirst())
            return profileField(for: remainder)
        default:
            return nil
        }
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

    func manifestStringFromDocuments(slug: String) -> String? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let manifestURL = documentsPath
            .appendingPathComponent("Sprung")
            .appendingPathComponent("Templates")
            .appendingPathComponent(slug)
            .appendingPathComponent("\(slug)-manifest.json")
        return try? String(contentsOf: manifestURL, encoding: .utf8)
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
        let folderName = selectedTemplate
        let resourceName = "\(folderName)-template"

        let htmlToSave = htmlHasChanges ? htmlContent : nil
        let textToSave = textHasChanges ? textContent : nil

        guard htmlToSave != nil || textToSave != nil else { return true }

        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Logger.error("TemplateEditor: Unable to locate Documents directory while saving template")
            return false
        }

        let templateDir = documentsPath
            .appendingPathComponent("Sprung")
            .appendingPathComponent("Templates")
            .appendingPathComponent(folderName)

        do {
            try FileManager.default.createDirectory(at: templateDir, withIntermediateDirectories: true)

            if let html = htmlToSave {
                let htmlPath = templateDir.appendingPathComponent("\(resourceName).html")
                try html.write(to: htmlPath, atomically: true, encoding: .utf8)
            }

            if let text = textToSave {
                let textPath = templateDir.appendingPathComponent("\(resourceName).txt")
                try text.write(to: textPath, atomically: true, encoding: .utf8)
            }

            appEnvironment.templateStore.upsertTemplate(
                slug: slug,
                name: folderName.capitalized,
                htmlContent: htmlToSave,
                textContent: textToSave,
                isCustom: true
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
        } catch {
            Logger.error("TemplateEditor: Failed to save template assets for \(folderName): \(error)")
            return false
        }
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

        // Remove user overrides from Documents directory if present
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let templateDir = documentsPath
                .appendingPathComponent("Sprung")
                .appendingPathComponent("Templates")
                .appendingPathComponent(slug)
            try? FileManager.default.removeItem(at: templateDir)
        }

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

    static func emptyManifest(slug _: String = "") -> String {
        return ""
    }

}
