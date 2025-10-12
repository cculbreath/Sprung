//
//  ResumeExportService.swift
//  Sprung
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
    
    init(templateStore: TemplateStore, applicantProfileStore: ApplicantProfileStore) {
        self.templateStore = templateStore
        self.nativeGenerator = NativePDFGenerator(
            templateStore: templateStore,
            profileProvider: applicantProfileStore
        )
        self.textGenerator = TextResumeGenerator(templateStore: templateStore)
    }
    
    func export(for resume: Resume) async throws {
        try await exportNatively(for: resume)
    }
    
    private func exportNatively(for resume: Resume) async throws {
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

        if let fallback = defaultTemplate() {
            resume.template = fallback
            return fallback
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

    private func defaultTemplate() -> Template? {
        if let archer = templateStore.template(slug: "archer") {
            return archer
        }
        if let typewriter = templateStore.template(slug: "typewriter") {
            return typewriter
        }
        return templateStore.templates().first
    }

    private func generateBasicTextTemplate() -> String {
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
