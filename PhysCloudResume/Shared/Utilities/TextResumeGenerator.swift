//
//  TextResumeGenerator.swift
//  PhysCloudResume
//
//  Created by Assistant on 12/20/24.
//

import Foundation
import Mustache

/// Handles generation of plain text resumes from Resume data
@MainActor
class TextResumeGenerator {
    private let templateStore: TemplateStore

    init(templateStore: TemplateStore) {
        self.templateStore = templateStore
    }
    
    // MARK: - Public Methods
    
    /// Generate a text resume using the specified template
    func generateTextResume(for resume: Resume, template: String = "archer") throws -> String {
        return try renderTemplate(for: resume, template: template)
    }
    // MARK: - Private Methods
    
    private func renderTemplate(for resume: Resume, template: String) throws -> String {
        // Load template
        let templateContent = try loadTextTemplate(named: template)
        
        // Create and process context
        let context = try createTemplateContext(from: resume)
        let processedContext = preprocessContextForText(context, from: resume)
        
        // Render with Mustache
        let mustacheTemplate = try Mustache.Template(string: templateContent)
        TemplateFilters.register(on: mustacheTemplate)
        return try mustacheTemplate.render(processedContext)
    }
    
    private func loadTextTemplate(named template: String) throws -> String {
        let resourceName = "\(template.lowercased())-template"
        
        // Try multiple path strategies to find the template
        var templateContent: String?
        
        if let stored = templateStore.textTemplateContent(slug: template.lowercased()) {
            templateContent = stored
        }

        // Strategy 0: Check Documents directory first for user modifications
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let userTemplatePath = documentsPath
                .appendingPathComponent("PhysCloudResume")
                .appendingPathComponent("Templates")
                .appendingPathComponent(template)
                .appendingPathComponent("\(resourceName).txt")
            if let content = try? String(contentsOf: userTemplatePath, encoding: .utf8) {
                templateContent = content
                Logger.debug("Using user-modified text template from: \(userTemplatePath.path)")
            }
        }
        
        // Strategy 1: Look in Templates/template subdirectory
        if templateContent == nil {
            if let path = Bundle.main.path(forResource: resourceName, ofType: "txt", inDirectory: "Templates/\(template)") {
                templateContent = try? String(contentsOfFile: path, encoding: .utf8)
            }
        }
        
        // Strategy 2: Look directly in main bundle
        if templateContent == nil {
            if let path = Bundle.main.path(forResource: resourceName, ofType: "txt") {
                templateContent = try? String(contentsOfFile: path, encoding: .utf8)
            }
        }
        
        // Strategy 3: Look for the template file anywhere in the bundle
        if templateContent == nil {
            let bundlePath = Bundle.main.bundlePath
            let fileManager = FileManager.default
            let enumerator = fileManager.enumerator(atPath: bundlePath)
            while let file = enumerator?.nextObject() as? String {
                if file.hasSuffix("\(resourceName).txt") {
                    let fullPath = bundlePath + "/" + file
                    templateContent = try? String(contentsOfFile: fullPath, encoding: .utf8)
                    if templateContent != nil {
                        break
                    }
                }
            }
        }
        
        // Fallback to embedded templates
        if templateContent == nil {
            templateContent = BundledTemplates.getTemplate(name: template, format: "txt")
            if templateContent != nil {
                Logger.debug("Using embedded text template for \(template)")
            }
        }
        
        guard let content = templateContent else {
            throw NSError(domain: "TextResumeGenerator", code: 404, 
                         userInfo: [NSLocalizedDescriptionKey: "Template not found: \(template)"])
        }
        
        var sanitized = content
        let legacySnippet = "{{{ center(join(job-titles, \" · \"), 80) }}}"
        let updatedSnippet = "{{{ center(join(job-titles), 80) }}}"
        if sanitized.contains(legacySnippet) {
            Logger.debug("TextResumeGenerator: migrated legacy join syntax in template \(template)")
            sanitized = sanitized.replacingOccurrences(of: legacySnippet, with: updatedSnippet)
        }
        sanitized = Self.migrateLegacyFormatDateCalls(in: sanitized)
        return sanitized
    }
    
    private func createTemplateContext(from resume: Resume) throws -> [String: Any] {
        // Use the shared template processor for consistency
        return try ResumeTemplateProcessor.createTemplateContext(from: resume)
    }
    
    private func preprocessContextForText(_ context: [String: Any], from resume: Resume) -> [String: Any] {
        var processed = context
        
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
}

private extension TextResumeGenerator {
    static func migrateLegacyFormatDateCalls(in template: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"formatDate\(\s*([A-Za-z0-9_\.\-]+)\s*,\s*\"MMM yyyy\"\s*\)"#
        ) else {
            return template
        }
        let range = NSRange(template.startIndex..., in: template)
        return regex.stringByReplacingMatches(in: template, options: [], range: range, withTemplate: "formatDate($1)")
    }
}
