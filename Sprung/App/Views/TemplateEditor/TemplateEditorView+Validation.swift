//
//  TemplateEditorView+Validation.swift
//  Sprung
//
//  Handles custom field validation and save/refresh orchestration.
//
import Foundation
import SwiftUI
extension TemplateEditorView {
    
    // MARK: - Custom Field Validation
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
        if value is [Any] {
            accumulator.insert(currentPath.joined(separator: "."))
            return
        }
        accumulator.insert(currentPath.joined(separator: "."))
    }
    
    // MARK: - Save/Refresh Orchestration
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
    
    // MARK: - Change Handlers
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
}
