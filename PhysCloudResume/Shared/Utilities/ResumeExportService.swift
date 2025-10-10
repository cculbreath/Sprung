//
//  ResumeExportService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/16/25.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

//  ResumeExportService.swift
//  Extracted network export logic out of the Resume model so that the core
//  data objects are no longer coupled to URLSession.


@MainActor
class ResumeExportService: ObservableObject {
    private let nativeGenerator: NativePDFGenerator
    private let textGenerator: TextResumeGenerator
    private let templateStore: TemplateStore
    
    init(templateStore: TemplateStore) {
        self.templateStore = templateStore
        self.nativeGenerator = NativePDFGenerator(templateStore: templateStore)
        self.textGenerator = TextResumeGenerator(templateStore: templateStore)
    }
    
    func export(jsonURL: URL, for resume: Resume) async throws {
        try await exportNatively(jsonURL: jsonURL, for: resume)
    }
    
    private func exportNatively(jsonURL: URL, for resume: Resume) async throws {
        var template = try await ensureTemplate(for: resume)
        var slug = template.slug

        // Generate PDF from HTML template
        let pdfData: Data
        do {
            pdfData = try await nativeGenerator.generatePDF(for: resume, template: slug, format: "html")
        } catch PDFGeneratorError.templateNotFound {
            template = try await promptForCustomTemplate(for: resume)
            slug = template.slug
            pdfData = try await nativeGenerator.generatePDF(for: resume, template: slug, format: "html")
        }
        resume.pdfData = pdfData

        // Generate text version using the template's text content (or fallback)
        let textContent = try textGenerator.generateTextResume(for: resume, template: slug)
        resume.textRes = textContent
    }
    
    @MainActor
    private func ensureTemplate(for resume: Resume) async throws -> Template {
        if let template = resume.template,
           templateStore.template(slug: template.slug) != nil {
            return template
        }

        do {
            return try await promptForCustomTemplate(for: resume)
        } catch let error as ExportTemplateSelectionError {
            switch error {
            case .userCancelled:
                throw ResumeExportError.userCancelled
            case .failedToReadFile:
                throw ResumeExportError.templateSelectionFailed
            }
        } catch {
            throw ResumeExportError.templateSelectionFailed
        }
    }
    
    @MainActor
    private func promptForCustomTemplate(for resume: Resume) async throws -> Template {
        let selection = try ExportTemplateSelection.requestTemplateHTMLAndOptionalCSS()

        let slug = "custom-\(Int(Date().timeIntervalSince1970))"
        let name = "Custom Template - \(Date().formatted(date: .numeric, time: .standard))"
        let textFallback = defaultTextTemplate(for: resume)

        let template = templateStore.upsertTemplate(
            slug: slug,
            name: name,
            htmlContent: selection.html,
            textContent: textFallback,
            cssContent: selection.css,
            isCustom: true
        )
        resume.template = template
        return template
    }

    private func defaultTextTemplate(for resume: Resume?) -> String {
        if let existingSlug = resume?.template?.slug,
           let existingText = templateStore.textTemplateContent(slug: existingSlug) {
            return existingText
        }
        if let existingSlug = resume?.template?.slug,
           let bundled = BundledTemplates.getTemplate(name: existingSlug, format: "txt") {
            return bundled
        }
        return generateBasicTextTemplate()
    }

    private func generateBasicTextTemplate() -> String {
        return """
{{{centeredName}}}
{{{centeredJobTitles}}}
{{{centeredContact}}}

{{{sectionLine_summary}}}
{{{wrappedSummary}}}

{{{sectionLine_employment}}}
{{#employment}}
{{{employmentFormatted}}}
{{#highlights}}
{{#.}}
* {{.}}
{{/.}}
{{/highlights}}

{{/employment}}

{{{footerTextFormatted}}}
"""
    }
}

enum ResumeExportError: Error, LocalizedError {
    case userCancelled
    case templateSelectionFailed
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Export cancelled by user"
        case .templateSelectionFailed:
            return "Failed to select or load template files"
        }
    }
}
