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
        guard selectedTemplate.isEmpty == false else {
            previewPDFData = nil
            previewTextContent = nil
            previewErrorMessage = nil
            return
        }
        guard force || !isPreviewRefreshing else { return }
        isPreviewRefreshing = true
        isGeneratingPreview = true
        isGeneratingLivePreview = true
        previewErrorMessage = nil

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
                previewErrorMessage = nil
            } catch {
                Logger.error("Template preview generation failed: \(error)")
                previewPDFData = nil
                previewTextContent = nil
                previewErrorMessage = previewErrorDescription(from: error)
            }
        }
    }

    private func generateTemplatePreview() async throws -> TemplatePreviewResult {
        guard selectedTemplate.isEmpty == false else {
            throw TemplatePreviewGeneratorError.templateUnavailable
        }
        let slug = selectedTemplate.lowercased()
        let templateRecord = appEnvironment.templateStore.template(slug: slug)
        let templateName = templateRecord?.name ?? templateDisplayName(selectedTemplate)

        guard let htmlTemplate = resolveHTMLTemplate(slug: slug) else {
            throw TemplatePreviewGeneratorError.templateUnavailable
        }
        guard let textTemplate = resolveTextTemplate(slug: slug) else {
            throw TemplatePreviewGeneratorError.templateUnavailable
        }

#if DEBUG
        Logger.debug("TemplatePreview[\(slug)]: HTML template length = \(htmlTemplate.count)")
        Logger.debug("TemplatePreview[\(slug)]: text template length = \(textTemplate.count)")
#endif

        let manifestData = templateRecord?.manifestData
#if DEBUG
        if manifestData == nil {
            Logger.warning("TemplateEditor: No manifest data available for slug \(slug)")
        }
#endif

        let template = Template(
            name: templateName,
            slug: slug,
            htmlContent: htmlTemplate,
            textContent: textTemplate,
            cssContent: templateRecord?.cssContent,
            manifestData: manifestData,
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

#if DEBUG
        Logger.debug("TemplatePreview[\(slug)]: context keys => \(debugContextSummary(context))")
#endif

        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [], template: template)
        resume.needToTree = true
        resume.importedEditorKeys = []

        let manifest = TemplateManifestLoader.manifest(for: template)
#if DEBUG
        if let manifest {
            Logger.debug("TemplatePreview[\(slug)]: manifest sections => \(manifest.sectionOrder)")
        } else {
            Logger.debug("TemplatePreview[\(slug)]: manifest not found; relying on context order")
        }
#endif
        guard let rootNode = JsonToTree(resume: resume, context: context, manifest: manifest).buildTree() else {
            throw TemplatePreviewGeneratorError.treeGenerationFailed
        }
        resume.rootNode = rootNode

#if DEBUG
        Logger.debug("TemplatePreview[\(slug)]: tree sections => \(debugTreeSummary(rootNode))")
#endif

        let pdfGenerator = NativePDFGenerator(
            templateStore: appEnvironment.templateStore,
            profileProvider: appEnvironment.applicantProfileStore
        )
        let renderingContext = try pdfGenerator.renderingContext(for: resume)

#if DEBUG
        Logger.debug("TemplatePreview[\(slug)]: rendering context keys => \(debugContextSummary(renderingContext))")
#endif

        // Render text
        let textOutput = try renderMustache(template: textTemplate, context: renderingContext, isPlainText: true)

        // Render PDF via WKWebView using the HTML template
        let pdfData = try await pdfGenerator.generatePDFFromCustomTemplate(
            for: resume,
            customHTML: htmlTemplate,
            processedContext: renderingContext
        )

        return (pdfData: pdfData, text: textOutput)
    }

    private func resolveHTMLTemplate(slug: String) -> String? {
        if let draft = htmlDraft, !draft.isEmpty {
            return draft
        }
        if let stored = appEnvironment.templateStore.template(slug: slug)?.htmlContent {
            return stored
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
        return nil
    }

    private func renderMustache(template: String, context: [String: Any], isPlainText: Bool = false) throws -> String {
        let translation = HandlebarsTranslator.translate(template)
        logHandlebarsWarnings(translation.warnings)

        let mustache = try Mustache.Template(string: translation.template)
        TemplateFilters.register(on: mustache)
        let rendered = try mustache.render(context)
        guard isPlainText else { return rendered }
        return rendered
            .decodingHTMLEntities()
            .removingAnchorTags()
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
            Logger.error("TemplateEditor: Failed to access overlay PDF at \(url.path)")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let document = PDFDocument(url: url) else {
            Logger.error("TemplateEditor: Failed to read overlay PDF at \(url.path)")
            return
        }

        pendingOverlayDocument = document
        overlayPageCount = document.pageCount
        overlayPageSelection = min(overlayPageSelection, max(document.pageCount - 1, 0))
        overlayFilename = url.lastPathComponent
    }

#if DEBUG
    private func debugContextSummary(_ context: [String: Any]) -> String {
        context.keys.sorted().map { key in
            guard let value = context[key] else { return "\(key): nil" }
            return "\(key): \(debugValueSummary(value))"
        }.joined(separator: ", ")
    }

    private func debugTreeSummary(_ root: TreeNode) -> String {
        root.orderedChildren.map { child in
            let name = child.name.isEmpty ? "(anonymous)" : child.name
            let childCount = child.orderedChildren.count
            let valuePreview = child.value.isEmpty ? "" : " value=\(child.value.prefix(40))"
            return "\(name)[children:\(childCount)]\(valuePreview)"
        }.joined(separator: ", ")
    }

    private func debugValueSummary(_ value: Any) -> String {
        if let array = value as? [Any] {
            return "array(\(array.count))"
        }
        if let dict = value as? [String: Any] {
            return "object(\(dict.keys.count))"
        }
        if let string = value as? String {
            let clipped = string.count > 40 ? String(string.prefix(37)) + "…" : string
            return "string(\(string.count)): \(clipped)"
        }
        if value is NSNull {
            return "null"
        }
        return String(describing: type(of: value))
    }
#endif

    private func logHandlebarsWarnings(_ warnings: [String]) {
        guard warnings.isEmpty == false else { return }
        for warning in warnings {
            Logger.warning("Template preview Handlebars compatibility: \(warning)")
        }
    }

    private func previewErrorDescription(from error: Error) -> String {
        let nsError = error as NSError
        let baseMessage = nsError.localizedDescription
        if nsError.domain.contains("GRMustache") {
            return "Template rendering failed: \(baseMessage)"
        }
        return baseMessage.isEmpty ? String(describing: error) : baseMessage
    }
}

private extension String {
    func removingAnchorTags() -> String {
        var output = self
        let anchorPattern = "<a [^>]*>(.*?)</a>"
        if let regex = try? NSRegularExpression(pattern: anchorPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: (output as NSString).length)
            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "$1")
        }
        return output.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }
}
enum TemplatePreviewGeneratorError: Error {
    case templateUnavailable
    case contextGenerationFailed
    case treeGenerationFailed
}
