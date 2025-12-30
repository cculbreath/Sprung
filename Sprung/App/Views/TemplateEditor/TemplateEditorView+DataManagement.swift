//
//  TemplateEditorView+DataManagement.swift
//  Sprung
//
//  Handles manifest JSON management.
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
    static func emptyManifest(slug _: String = "") -> String {
        let overrides = TemplateManifestOverrides(
            sectionOrder: Array(StandardSection.allCases),
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
    func decodeManifestOverrides(from data: Data, slug _: String) -> TemplateManifestOverrides? {
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
}
