//
//  TemplateEditorView+Preview.swift
//  Sprung
//

import AppKit
import Foundation
import Mustache
import PDFKit
import SwiftData
import SwiftUI

typealias TemplatePreviewResult = (pdfData: Data, text: String)

extension TemplateEditorView {
    func closeEditor() {
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Template Editor" }) {
            window.close()
        }
    }

    func refreshTemplatePreview(force: Bool = false) {
        guard !isPreviewRefreshing else { return }
        isPreviewRefreshing = true
        isGeneratingPreview = true
        isGeneratingLivePreview = true

        Task { @MainActor in
            defer {
                isPreviewRefreshing = false
                isGeneratingPreview = false
                isGeneratingLivePreview = false
            }

            do {
                let result = try await generateTemplatePreview()
                previewPDFData = result.pdfData
                previewTextContent = result.text
            } catch {
                Logger.error("Template preview generation failed: \(error)")
                previewPDFData = nil
                previewTextContent = nil
                saveError = "Failed to generate template preview: \(error.localizedDescription)"
            }
        }
    }

    private func generateTemplatePreview() async throws -> TemplatePreviewResult {
        let slug = selectedTemplate.lowercased()
        let templateRecord = appEnvironment.templateStore.template(slug: slug)
        let templateName = templateRecord?.name ?? templateDisplayName(selectedTemplate)

        guard let htmlTemplate = resolveHTMLTemplate(slug: slug) else {
            throw TemplatePreviewGeneratorError.templateUnavailable
        }
        guard let textTemplate = resolveTextTemplate(slug: slug) else {
            throw TemplatePreviewGeneratorError.templateUnavailable
        }

        let template = Template(
            name: templateName,
            slug: slug,
            htmlContent: htmlTemplate,
            textContent: textTemplate,
            cssContent: templateRecord?.cssContent,
            manifestData: templateRecord?.manifestData,
            isCustom: templateRecord?.isCustom ?? false,
            createdAt: templateRecord?.createdAt ?? Date(),
            updatedAt: templateRecord?.updatedAt ?? Date()
        )

        let contextBuilder = ResumeTemplateContextBuilder(templateSeedStore: appEnvironment.templateSeedStore)
        let applicantProfile = appEnvironment.applicantProfileStore.currentProfile()

        guard let context = contextBuilder.buildContext(
            for: template,
            fallbackJSON: nil,
            applicantProfile: applicantProfile
        ) else {
            throw TemplatePreviewGeneratorError.contextGenerationFailed
        }

        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [], template: template)
        resume.needToTree = true
        resume.importedEditorKeys = []

        let manifest = TemplateManifestLoader.manifest(for: template)
        guard let rootNode = JsonToTree(resume: resume, context: context, manifest: manifest).buildTree() else {
            throw TemplatePreviewGeneratorError.treeGenerationFailed
        }
        resume.rootNode = rootNode

        let renderingContext = try ResumeTemplateProcessor.createTemplateContext(from: resume)

        // Render text
        let textOutput = try renderMustache(template: textTemplate, context: renderingContext)

        // Render PDF via WKWebView using the HTML template
        let pdfGenerator = NativePDFGenerator(
            templateStore: appEnvironment.templateStore,
            profileProvider: appEnvironment.applicantProfileStore
        )
        let pdfData = try await pdfGenerator.generatePDFFromCustomTemplate(for: resume, customHTML: htmlTemplate)

        return (pdfData: pdfData, text: textOutput)
    }

    private func resolveHTMLTemplate(slug: String) -> String? {
        if let draft = htmlDraft, !draft.isEmpty {
            return draft
        }
        if let stored = appEnvironment.templateStore.template(slug: slug)?.htmlContent {
            return stored
        }
        if let bundled = BundledTemplates.getTemplate(name: slug, format: "html") {
            return bundled
        }
        return nil
    }

    private func resolveTextTemplate(slug: String) -> String? {
        if let draft = textDraft, !draft.isEmpty {
            return draft
        }
        if let stored = appEnvironment.templateStore.template(slug: slug)?.textContent {
            return stored
        }
        if let bundled = BundledTemplates.getTemplate(name: slug, format: "txt") {
            return bundled
        }
        return nil
    }

    private func renderMustache(template: String, context: [String: Any]) throws -> String {
        let mustache = try Mustache.Template(string: template)
        TemplateFilters.register(on: mustache)
        return try mustache.render(context)
    }

    func prepareOverlayOptions() {
        overlayColorSelection = overlayColor
        overlayPageSelection = overlayPageIndex
        pendingOverlayDocument = overlayPDFDocument
        overlayPageCount = overlayPDFDocument?.pageCount ?? 0
        showOverlayOptionsSheet = true
    }

    func applyOverlaySelection() {
        if let pending = pendingOverlayDocument {
            overlayPDFDocument = pending
            let maxIndex = max(pending.pageCount - 1, 0)
            let clampedIndex = min(max(overlayPageSelection, 0), maxIndex)
            overlayPageIndex = clampedIndex
            overlayPageCount = pending.pageCount
            overlayFilename = pending.documentURL?.lastPathComponent ?? overlayFilename
            showOverlay = true
        } else if overlayPDFDocument != nil {
            let maxIndex = max((overlayPDFDocument?.pageCount ?? 1) - 1, 0)
            overlayPageIndex = min(max(overlayPageSelection, 0), maxIndex)
        }

        overlayColor = overlayColorSelection
        showOverlayOptionsSheet = false
    }

    func clearOverlaySelection() {
        overlayPDFDocument = nil
        pendingOverlayDocument = nil
        overlayPageCount = 0
        overlayFilename = nil
        overlayPageSelection = 0
        overlayPageIndex = 0
        showOverlay = false
    }

    func loadOverlayPDF(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            saveError = "Failed to access overlay PDF"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let document = PDFDocument(url: url) else {
            saveError = "Failed to read overlay PDF"
            return
        }

        pendingOverlayDocument = document
        overlayPageCount = document.pageCount
        overlayPageSelection = min(overlayPageSelection, max(document.pageCount - 1, 0))
        overlayFilename = url.lastPathComponent
    }
}

enum TemplatePreviewGeneratorError: Error {
    case templateUnavailable
    case contextGenerationFailed
    case treeGenerationFailed
}
