//
//  TemplateEditorView+Persistence.swift
//  Sprung
//
//  Handles template CRUD operations and asset loading (HTML/text content).
//

import Foundation
import SwiftUI

extension TemplateEditorView {
    
    // MARK: - Template Asset Loading
    
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
    
    // MARK: - Template Management
    
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
        
        appEnvironment.templateStore.upsertTemplate(
            slug: slug,
            name: trimmedName,
            htmlContent: template.htmlContent,
            textContent: template.textContent,
            cssContent: template.cssContent,
            isCustom: template.isCustom
        )
        
        loadAvailableTemplates()
    }
}
