//
//  TemplateEditorView+Persistence.swift
//  Sprung
//

import Foundation
import SwiftUI

extension TemplateEditorView {
    func loadTemplate() {
        let resourceName = "\(selectedTemplate)-template"
        let fileExtension = currentFormat == "pdf" ? "html" : currentFormat

        // Prefer SwiftData-stored templates when available
        let storedSlug = selectedTemplate.lowercased()
        if fileExtension == "html", let stored = appEnvironment.templateStore.htmlTemplateContent(slug: storedSlug) {
            templateContent = stored
            assetHasChanges = false
            return
        }
        if fileExtension == "txt", let stored = appEnvironment.templateStore.textTemplateContent(slug: storedSlug) {
            templateContent = stored
            assetHasChanges = false
            return
        }

        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let templatePath = documentsPath
                .appendingPathComponent("Sprung")
                .appendingPathComponent("Templates")
                .appendingPathComponent(selectedTemplate)
                .appendingPathComponent("\(resourceName).\(fileExtension)")
            if let content = try? String(contentsOf: templatePath, encoding: .utf8) {
                templateContent = content
                assetHasChanges = false
                return
            }
        }

        // Debug: List bundle contents
        if let bundlePath = Bundle.main.resourcePath {
            let fileManager = FileManager.default
            if let contents = try? fileManager.contentsOfDirectory(atPath: bundlePath) {
                Logger.debug("🗂️ Bundle contents: \(contents)")

                // Look for Templates directory
                let templatesPath = bundlePath + "/Templates"
                if fileManager.fileExists(atPath: templatesPath) {
                    if let templateContents = try? fileManager.contentsOfDirectory(atPath: templatesPath) {
                        Logger.debug("📁 Templates directory contents: \(templateContents)")
                    }
                } else {
                    Logger.debug("❓ Templates directory not found in bundle")
                }
            }
        }

        // Try multiple bundle lookup strategies
        var bundlePath: String?

        // Strategy 1: Resources/Templates subdirectory
        bundlePath = Bundle.main.path(forResource: resourceName, ofType: fileExtension, inDirectory: "Resources/Templates/\(selectedTemplate)")
        if bundlePath != nil {
            Logger.debug("✅ Found via Resources/Templates/\(selectedTemplate)")
        }

        // Strategy 2: Templates subdirectory
        if bundlePath == nil {
            bundlePath = Bundle.main.path(forResource: resourceName, ofType: fileExtension, inDirectory: "Templates/\(selectedTemplate)")
            if bundlePath != nil {
                Logger.debug("✅ Found via Templates/\(selectedTemplate)")
            }
        }

        // Strategy 3: Direct lookup
        if bundlePath == nil {
            bundlePath = Bundle.main.path(forResource: resourceName, ofType: fileExtension)
            if bundlePath != nil {
                Logger.debug("✅ Found via direct lookup")
            }
        }

        if let path = bundlePath,
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            templateContent = content
            assetHasChanges = false
        } else if let embeddedContent = BundledTemplates.getTemplate(name: selectedTemplate, format: fileExtension) {
            templateContent = embeddedContent
            assetHasChanges = false
        } else {
            templateContent = "// Template not found: \(resourceName).\(fileExtension)\n// Bundle path: \(Bundle.main.bundlePath)\n// Resource path: \(Bundle.main.resourcePath ?? "nil")"
            assetHasChanges = false
        }
    }

    func loadManifest() {
        manifestValidationMessage = nil
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

        if let bundleContent = manifestStringFromBundle(slug: slug) {
            manifestContent = bundleContent
            manifestHasChanges = false
            return
        }

        manifestContent = """
{
  \"slug\": \"\(slug)\",
  \"sectionOrder\": [],
  \"sections\": {}
}
"""
        manifestHasChanges = false
    }

    @discardableResult
    func saveManifest() -> Bool {
        manifestValidationMessage = nil
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
        let slug = selectedTemplate.lowercased()

        if let template = appEnvironment.templateStore.template(slug: slug),
           let seed = appEnvironment.templateSeedStore.seed(for: template),
           let formatted = prettyJSONString(from: seed.seedData) {
            seedContent = formatted
            seedHasChanges = false
            return
        }

        seedContent = "{}"
        seedHasChanges = false
    }

    @discardableResult
    func saveSeed() -> Bool {
        seedValidationMessage = nil
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
            guard let formatted = prettyJSONString(from: jsonObject) else {
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
            return true
        } catch {
            seedValidationMessage = "Seed validation failed: \(error.localizedDescription)"
            return false
        }
    }

    func promoteCurrentResumeToSeed() {
        seedValidationMessage = nil
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

    func manifestStringFromBundle(slug: String) -> String? {
        let resourceName = "\(slug)-manifest"
        let candidates: [URL?] = [
            Bundle.main.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: "Resources/Templates/\(slug)"
            ),
            Bundle.main.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: "Templates/\(slug)"
            ),
            Bundle.main.url(forResource: resourceName, withExtension: "json")
        ]

        for candidate in candidates {
            if let url = candidate, let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        return nil
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
    func saveTemplate() -> Bool {
        let resourceName = "\(selectedTemplate)-template"
        let fileExtension = currentFormat == "pdf" ? "html" : currentFormat

        // Save to Documents directory
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            saveError = "Unable to locate Documents directory."
            return false
        }
        let templateDir = documentsPath
            .appendingPathComponent("Sprung")
            .appendingPathComponent("Templates")
            .appendingPathComponent(selectedTemplate)

        do {
            // Create directory if needed
            try FileManager.default.createDirectory(at: templateDir, withIntermediateDirectories: true)

            // Write file
            let templatePath = templateDir.appendingPathComponent("\(resourceName).\(fileExtension)")
            try templateContent.write(to: templatePath, atomically: true, encoding: .utf8)

            let slug = selectedTemplate.lowercased()
            if fileExtension == "html" {
                appEnvironment.templateStore.upsertTemplate(
                    slug: slug,
                    name: selectedTemplate.capitalized,
                    htmlContent: templateContent,
                    textContent: nil,
                    isCustom: true
                )
            } else if fileExtension == "txt" {
                appEnvironment.templateStore.upsertTemplate(
                    slug: slug,
                    name: selectedTemplate.capitalized,
                    htmlContent: nil,
                    textContent: templateContent,
                    isCustom: true
                )
            }

            assetHasChanges = false
            return true
        } catch {
            saveError = "Failed to save template: \(error.localizedDescription)"
            return false
        }
    }

    @MainActor
    func previewPDF() {
        guard selectedTab == .pdfTemplate else { return }
        isGeneratingPreview = true
        Task { @MainActor in
            await generateLivePreview()
            isGeneratingPreview = false
        }
    }

    func loadAvailableTemplates() {
        let templates = appEnvironment.templateStore.templates()
        if templates.isEmpty {
            availableTemplates = ["archer", "typewriter"]
        } else {
            availableTemplates = templates.map { $0.slug }.sorted()
        }

        if !availableTemplates.contains(selectedTemplate) {
            selectedTemplate = availableTemplates.first ?? "archer"
        }
    }

    func addNewTemplate() {
        let trimmedName = newTemplateName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedName.isEmpty, !availableTemplates.contains(trimmedName) else {
            newTemplateName = ""
            return
        }

        let fileExtension = currentFormat == "pdf" ? "html" : currentFormat
        let initialContent = createEmptyTemplate(name: trimmedName, format: fileExtension)
        appEnvironment.templateStore.upsertTemplate(
            slug: trimmedName,
            name: trimmedName.capitalized,
            htmlContent: fileExtension == "html" ? initialContent : nil,
            textContent: fileExtension == "txt" ? initialContent : nil,
            isCustom: true
        )

        loadAvailableTemplates()
        selectedTemplate = trimmedName
        newTemplateName = ""

        templateContent = initialContent
        assetHasChanges = true
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
        loadTemplate()
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

        availableTemplates.removeAll { $0 == slug }
        appEnvironment.templateStore.deleteTemplate(slug: slug.lowercased())
        appEnvironment.templateSeedStore.deleteSeed(forSlug: slug.lowercased())

        if selectedTemplate == slug {
            selectedTemplate = availableTemplates.first ?? "archer"
            loadTemplate()
            loadManifest()
            loadSeed()
        }

        templatePendingDeletion = nil
        loadAvailableTemplates()
    }

    func performRefresh() {
        _ = savePendingChanges()
        if selectedTab == .pdfTemplate {
            previewPDF()
        }
    }

    func performClose() {
        guard savePendingChanges() else { return }
        closeEditor()
    }

    func createEmptyTemplate(name: String, format: String) -> String {
        switch format {
        case "html":
            return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>{{{contact.name}}}</title>
    <style>
        /* Add your CSS here */
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { text-align: center; margin-bottom: 20px; }
        .name { font-size: 24px; font-weight: bold; }
        .job-titles { font-size: 16px; color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <div class="name">{{{contact.name}}}</div>
        <div class="job-titles">{{{jobTitlesJoined}}}</div>
    </div>

    <div class="contact">
        <p>{{contact.email}} | {{contact.phone}} | {{contact.location.city}}, {{contact.location.state}}</p>
    </div>

    <div class="summary">
        <h2>Summary</h2>
        <p>{{{summary}}}</p>
    </div>

    <!-- Add more sections as needed -->
</body>
</html>
"""
        case "txt":
            return """
{{{ center(contact.name, 80) }}}

{{{ center(join(job-titles), 80) }}}

{{#contactLine}}
{{{ center(contactLine, 80) }}}
{{/contactLine}}

{{{ wrap(summary, 80, 6, 6) }}}

{{#section-labels.employment}}
{{{ sectionLine(section-labels.employment, 80) }}}
{{/section-labels.employment}}
{{#employment}}
{{ employer }}{{#location}} | {{{.}}}{{/location}}
{{#position}}
{{ position }}
{{/position}}
{{ formatDate(start) }} – {{ formatDate(end) }}
{{{ bulletList(highlights, 80, 2, "•") }}}

{{/employment}}

{{#more-info}}
{{{ wrap(uppercase(more-info), 80, 0, 0) }}}
{{/more-info}}
"""
        default:
            return "// New \(name) template in \(format) format"
        }
    }
}
