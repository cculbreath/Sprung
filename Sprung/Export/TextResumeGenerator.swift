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
        var context = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        // Apply text-specific transformations
        applyTextTransformations(to: &context, resume: resume)
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
    /// Apply text-specific transformations to the context.
    /// These are formatting changes needed for plain text output.
    private func applyTextTransformations(to context: inout [String: Any], resume: Resume) {
        // Normalize contact values and build contactItems
        var contactItems: [String] = []
        if var contact = context["contact"] as? [String: Any],
           let name = contact["name"] as? String {
            contact["name"] = name.decodingHTMLEntities()
            context["contact"] = contact
        }
        if let contact = context["contact"] as? [String: Any] {
            if let location = contact["location"] as? [String: Any] {
                let city = (location["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let state = (location["state"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !city.isEmpty || !state.isEmpty {
                    contactItems.append(state.isEmpty ? city : "\(city), \(state)")
                }
            }
            appendIfPresent(contact["phone"], to: &contactItems)
            appendIfPresent(contact["email"], to: &contactItems)
            appendIfPresent(contact["website"], to: &contactItems)
        }
        if !contactItems.isEmpty {
            context["contactItems"] = contactItems
            context["contactLine"] = contactItems.joined(separator: " • ")
        }
        // Convert employment data to array preserving order
        if let employment = context["employment"] as? [String: Any] {
            let employmentArray = convertEmploymentToArray(employment, from: resume)
            context["employment"] = employmentArray
        }
        // Ensure skills are represented as an array of dictionaries
        if let skillsDict = context["skills-and-expertise"] as? [String: Any] {
            var skillsArray: [[String: Any]] = []
            for (title, description) in skillsDict {
                skillsArray.append([
                    "title": title,
                    "description": description
                ])
            }
            context["skills-and-expertise"] = skillsArray
        }
        // Convert education object to array format
        if let educationDict = context["education"] as? [String: Any] {
            var educationArray: [[String: Any]] = []
            for (institution, details) in educationDict {
                if var detailsDict = details as? [String: Any] {
                    detailsDict["institution"] = institution
                    normalizeLocation(in: &detailsDict)
                    educationArray.append(detailsDict)
                }
            }
            context["education"] = educationArray
        }
        if let moreInfo = context["more-info"] as? String {
            let cleaned = moreInfo
                .replacingOccurrences(of: #"<\/?[^>]+(>|$)|↪︎"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            context["more-info"] = cleaned
        }
    }
    /// Decode HTML entities that may appear in rendered plain-text output
    private func sanitizeRenderedText(_ text: String) -> String {
        return text
            .decodingHTMLEntities()
            .collapsingConsecutiveBlankLines()
    }
    private func convertEmploymentToArray(_ employment: [String: Any], from resume: Resume) -> [[String: Any]] {
        if let rootNode = resume.rootNode,
           let employmentSection = rootNode.children?.first(where: { $0.name == "employment" }),
           let employmentNodes = employmentSection.children {
            let sortedNodes = employmentNodes.sorted { $0.myIndex < $1.myIndex }
            var employmentArray: [[String: Any]] = []
            for node in sortedNodes {
                let employer = node.name
                if let details = employment[employer] as? [String: Any] {
                    var detailsDict = details
                    detailsDict["employer"] = employer
                    normalizeLocation(in: &detailsDict)
                    employmentArray.append(detailsDict)
                }
            }
            return employmentArray
        }
        // Fallback to simple conversion without sorting
        return employment.map { employer, details in
            var detailsDict = details as? [String: Any] ?? [:]
            detailsDict["employer"] = employer
            normalizeLocation(in: &detailsDict)
            return detailsDict
        }
    }
    private func appendIfPresent(_ value: Any?, to array: inout [String]) {
        guard let value else { return }
        if let string = value as? String {
            let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                array.append(cleaned)
            }
        } else if let number = value as? NSNumber {
            array.append(number.stringValue)
        }
    }
    private func normalizeLocation(in dict: inout [String: Any]) {
        if let locationDict = dict["location"] as? [String: Any] {
            let city = (locationDict["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let state = (locationDict["state"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !city.isEmpty || !state.isEmpty {
                dict["location"] = state.isEmpty ? city : "\(city), \(state)"
            } else {
                dict["location"] = nil
            }
        } else if let location = dict["location"] as? String {
            let cleaned = location.trimmingCharacters(in: .whitespacesAndNewlines)
            dict["location"] = cleaned.isEmpty ? nil : cleaned
        }
    }
    private func logTranslationWarnings(_ warnings: [String], template: String) {
        guard warnings.isEmpty == false else { return }
        for warning in warnings {
            Logger.warning("Handlebars compatibility (\(template)): \(warning)")
        }
    }
}
