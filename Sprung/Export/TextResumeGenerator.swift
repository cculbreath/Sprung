//
//  TextResumeGenerator.swift
//  Sprung
//
import Foundation
import Mustache
/// Handles generation of plain text resumes from Resume data
@MainActor
class TextResumeGenerator {
    private let templateStore: TemplateStore
    private let profileProvider: ApplicantProfileProviding
    init(templateStore: TemplateStore, profileProvider: ApplicantProfileProviding) {
        self.templateStore = templateStore
        self.profileProvider = profileProvider
    }
    // MARK: - Public Methods
    /// Generate a text resume using the specified template
    func generateTextResume(for resume: Resume, template: String) throws -> String {
        let rendered = try renderTemplate(for: resume, template: template)
        return sanitizeRenderedText(rendered)
    }
    // MARK: - Private Methods
    private func renderTemplate(for resume: Resume, template: String) throws -> String {
        // Load template
        let templateContent = try loadTextTemplate(named: template)
        // Build unified context using ResumeContextBuilder
        let profile = profileProvider.currentProfile()
        let context = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        let translation = HandlebarsTranslator.translate(templateContent)
        logTranslationWarnings(translation.warnings, template: template)
        // Render with Mustache
        let mustacheTemplate = try Mustache.Template(string: translation.template)
        TemplateFilters.register(on: mustacheTemplate)
        return try mustacheTemplate.render(context)
    }
    private func loadTextTemplate(named template: String) throws -> String {
        var templateContent: String?
        if let stored = templateStore.textTemplateContent(slug: template.lowercased()) {
            templateContent = stored
        }
        guard let content = templateContent else {
            throw NSError(domain: "TextResumeGenerator", code: 404,
                         userInfo: [NSLocalizedDescriptionKey: "Template not found: \(template)"])
        }
        return content
    }
    /// Decode HTML entities that may appear in rendered plain-text output
    private func sanitizeRenderedText(_ text: String) -> String {
        return text
            .decodingHTMLEntities()
            .collapsingConsecutiveBlankLines()
    }
    private func logTranslationWarnings(_ warnings: [String], template: String) {
        guard warnings.isEmpty == false else { return }
        for warning in warnings {
            Logger.warning("Handlebars compatibility (\(template)): \(warning)")
        }
    }
}
