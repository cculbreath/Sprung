//
//  ResumeExportService.swift
//  Sprung
//
//
import Foundation
import AppKit
import UniformTypeIdentifiers
@MainActor
@Observable
class ResumeExportService {
    private let nativeGenerator: NativePDFGenerator
    private let textGenerator: TextResumeGenerator
    private let templateStore: TemplateStore
    init(templateStore: TemplateStore, applicantProfileStore: ApplicantProfileStore) {
        self.templateStore = templateStore
        self.nativeGenerator = NativePDFGenerator(
            templateStore: templateStore,
            profileProvider: applicantProfileStore
        )
        self.textGenerator = TextResumeGenerator(templateStore: templateStore, profileProvider: applicantProfileStore)
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
        resume.textResume = textContent
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
        throw ResumeExportError.noTemplatesConfigured
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
        return generateBasicTextTemplate()
    }
    private func defaultTemplate() -> Template? {
        return templateStore.defaultTemplate()
    }
    private func generateBasicTextTemplate() -> String {
        return """
{{#hasContent(basics.name)}}
{{{ center(basics.name, 80) }}}
{{/hasContent(basics.name)}}
{{#hasContent(custom.jobTitles)}}
{{{ center(join(custom.jobTitles), 80) }}}
{{/hasContent(custom.jobTitles)}}
{{#hasContent(basics.contactLinePieces)}}
{{{ center(join(basics.contactLinePieces), 80) }}}
{{/hasContent(basics.contactLinePieces)}}
{{#hasContent(custom.objective)}}
{{{ wrap(custom.objective, 80, 0, 0) }}}
{{/hasContent(custom.objective)}}
{{#hasContent(skills)}}
{{{ sectionLine(template.sectionLabels.skills, 80) }}}
{{#skills}}
{{ name }}
{{#hasContent(keywords)}}
{{{ wrap(join(keywords), 80, 0, 0) }}}
{{/hasContent(keywords)}}
{{/skills}}
{{/hasContent(skills)}}
{{#hasContent(work)}}
{{{ sectionLine(template.sectionLabels.work, 80) }}}
{{#work}}
{{ name }}{{#hasContent(location)}} | {{ location }}{{/hasContent(location)}}
{{#hasContent(position)}}
{{ position }}
{{/hasContent(position)}}
{{#hasContent(startDate)}}
{{ formatDate(startDate) }}{{#hasContent(endDate)}} – {{ formatDate(endDate) }}{{/hasContent(endDate)}}
{{/hasContent(startDate)}}
{{#hasContent(highlights)}}
{{{ bulletList(highlights, 80, 2, "•") }}}
{{/hasContent(highlights)}}
{{/work}}
{{/hasContent(work)}}
{{#hasContent(custom.moreInfo)}}
{{{ sectionLine(template.sectionLabels.moreInfo, 80) }}}
{{{ wrap(htmlStrip(custom.moreInfo), 80, 0, 0) }}}
{{/hasContent(custom.moreInfo)}}
"""
    }
}
enum ResumeExportError: Error, LocalizedError {
    case userCancelled
    case templateSelectionFailed
    case noTemplatesConfigured
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Export cancelled by user"
        case .templateSelectionFailed:
            return "Failed to select or load template files"
        case .noTemplatesConfigured:
            return "No resume templates are configured. Add a template in the Template Editor before exporting."
        }
    }
}
