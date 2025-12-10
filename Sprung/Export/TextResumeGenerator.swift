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
        // Create and process context
        let context = try createTemplateContext(from: resume)
        var processedContext = preprocessContextForText(context, from: resume)
        processedContext = HandlebarsContextAugmentor.augment(processedContext)
        let translation = HandlebarsTranslator.translate(templateContent)
        logTranslationWarnings(translation.warnings, template: template)
        // Render with Mustache
        let mustacheTemplate = try Mustache.Template(string: translation.template)
        TemplateFilters.register(on: mustacheTemplate)
        return try mustacheTemplate.render(processedContext)
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
    private func createTemplateContext(from resume: Resume) throws -> [String: Any] {
        // Use the shared template processor for consistency
        return try ResumeTemplateProcessor.createTemplateContext(from: resume)
    }
    private func preprocessContextForText(_ context: [String: Any], from resume: Resume) -> [String: Any] {
        // First merge ApplicantProfile data into context
        var processed = mergeApplicantProfile(into: context, for: resume)
        // Normalize contact values and build contactItems
        var contactItems: [String] = []
        if var contact = processed["contact"] as? [String: Any],
           let name = contact["name"] as? String {
            contact["name"] = name.decodingHTMLEntities()
            processed["contact"] = contact
        }
        if let contact = processed["contact"] as? [String: Any] {
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
            processed["contactItems"] = contactItems
            processed["contactLine"] = contactItems.joined(separator: " • ")
        }
        // Convert employment data to array preserving order
        if let employment = processed["employment"] as? [String: Any] {
            let employmentArray = convertEmploymentToArray(employment, from: resume)
            processed["employment"] = employmentArray
        }
        // Ensure skills are represented as an array of dictionaries
        if let skillsDict = processed["skills-and-expertise"] as? [String: Any] {
            var skillsArray: [[String: Any]] = []
            for (title, description) in skillsDict {
                skillsArray.append([
                    "title": title,
                    "description": description
                ])
            }
            processed["skills-and-expertise"] = skillsArray
        }
        // Convert education object to array format
        if let educationDict = processed["education"] as? [String: Any] {
            var educationArray: [[String: Any]] = []
            for (institution, details) in educationDict {
                if var detailsDict = details as? [String: Any] {
                    detailsDict["institution"] = institution
                    normalizeLocation(in: &detailsDict)
                    educationArray.append(detailsDict)
                }
            }
            processed["education"] = educationArray
        }
        if let moreInfo = processed["more-info"] as? String {
            let cleaned = moreInfo
                .replacingOccurrences(of: #"<\/?[^>]+(>|$)|↪︎"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            processed["more-info"] = cleaned
        }
        return processed
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
    // MARK: - Applicant Profile Merging
    private func mergeApplicantProfile(into context: [String: Any], for resume: Resume) -> [String: Any] {
        guard let template = resume.template,
              let manifest = TemplateManifestLoader.manifest(for: template) else {
            return context
        }
        let profile = profileProvider.currentProfile()
        let profileContext = buildApplicantProfileContext(profile: profile, manifest: manifest)
        var merged = context
        for (key, value) in profileContext {
            if var existingDict = merged[key] as? [String: Any],
               let newDict = value as? [String: Any] {
                for (subKey, subValue) in newDict {
                    existingDict[subKey] = subValue
                }
                merged[key] = existingDict
            } else {
                merged[key] = value
            }
        }
        return merged
    }
    private func buildApplicantProfileContext(
        profile: ApplicantProfile,
        manifest: TemplateManifest
    ) -> [String: Any] {
        var payload: [String: Any] = [:]
        let bindings = manifest.applicantProfileBindings()
        if bindings.isEmpty {
            // No explicit bindings in manifest - use default profile paths
            for defaultPath in TemplateManifest.defaultApplicantProfilePaths {
                guard let value = applicantProfileValue(for: defaultPath.path, profile: profile),
                      !isEmptyValue(value) else { continue }
                let updatedSection = setProfileValue(
                    value,
                    for: defaultPath.path,
                    existing: payload[defaultPath.section]
                )
                payload[defaultPath.section] = updatedSection
            }
        } else {
            for binding in bindings {
                guard let value = applicantProfileValue(for: binding.binding.path, profile: profile),
                      !isEmptyValue(value) else { continue }
                let updatedSection = setProfileValue(
                    value,
                    for: binding.path,
                    existing: payload[binding.section]
                )
                payload[binding.section] = updatedSection
            }
        }
        return payload
    }
    private func applicantProfileValue(for path: [String], profile: ApplicantProfile) -> Any? {
        guard let first = path.first else { return nil }
        switch first {
        case "name":
            return profile.name.isEmpty ? nil : profile.name
        case "email":
            return profile.email.isEmpty ? nil : profile.email
        case "phone":
            return profile.phone.isEmpty ? nil : profile.phone
        case "label":
            return profile.label.isEmpty ? nil : profile.label
        case "summary":
            return profile.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : profile.summary
        case "url", "website", "websites":
            return profile.websites.isEmpty ? nil : profile.websites
        case "picture", "image":
            return profile.pictureDataURL()
        case "address":
            return profile.address.isEmpty ? nil : profile.address
        case "city":
            return profile.city.isEmpty ? nil : profile.city
        case "region", "state":
            return profile.state.isEmpty ? nil : profile.state
        case "postalCode", "zip", "code":
            return profile.zip.isEmpty ? nil : profile.zip
        case "countryCode":
            return profile.countryCode.isEmpty ? nil : profile.countryCode
        case "location":
            let remainder = Array(path.dropFirst())
            return remainder.isEmpty ? nil : applicantProfileValue(for: remainder, profile: profile)
        default:
            return nil
        }
    }
    private func isEmptyValue(_ value: Any) -> Bool {
        if let string = value as? String {
            return string.isEmpty
        }
        if let dict = value as? [String: Any] {
            return dict.isEmpty
        }
        return false
    }
    private func setProfileValue(
        _ value: Any,
        for path: [String],
        existing: Any?
    ) -> Any {
        guard let first = path.first else { return value }
        var dictionary = dictionaryValue(from: existing) ?? [:]
        let remainder = Array(path.dropFirst())
        if remainder.isEmpty {
            dictionary[first] = value
        } else {
            let current = dictionary[first]
            dictionary[first] = setProfileValue(value, for: remainder, existing: current)
        }
        return dictionary
    }
    private func dictionaryValue(from value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let dict = value as? [String: Any] {
            return dict
        }
        return nil
    }
}
