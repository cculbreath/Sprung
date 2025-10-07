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
    
    // MARK: - Public Methods
    
    /// Generate a text resume using the specified template
    func generateTextResume(for resume: Resume, template: String = "archer") throws -> String {
        return try renderTemplate(for: resume, template: template)
    }
    
    /// Generate text from a custom template string
    func generateTextFromCustomTemplate(for resume: Resume, customText: String) throws -> String {
        let context = try createTemplateContext(from: resume)
        let processedContext = preprocessContextForText(context, from: resume)
        let mustacheTemplate = try Template(string: customText)
        return try mustacheTemplate.render(processedContext)
    }
    
    // MARK: - Private Methods
    
    private func renderTemplate(for resume: Resume, template: String) throws -> String {
        // Load template
        let templateContent = try loadTextTemplate(named: template)
        
        // Create and process context
        let context = try createTemplateContext(from: resume)
        let processedContext = preprocessContextForText(context, from: resume)
        
        // Render with Mustache
        let mustacheTemplate = try Template(string: templateContent)
        return try mustacheTemplate.render(processedContext)
    }
    
    private func loadTextTemplate(named template: String) throws -> String {
        let resourceName = "\(template.lowercased())-template"
        
        // Try multiple path strategies to find the template
        var templateContent: String?
        
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
        
        return content
    }
    
    private func createTemplateContext(from resume: Resume) throws -> [String: Any] {
        // Use the shared template processor for consistency
        return try ResumeTemplateProcessor.createTemplateContext(from: resume)
    }
    
    private func preprocessContextForText(_ context: [String: Any], from resume: Resume) -> [String: Any] {
        var processed = context
        
        // Text-specific preprocessing
        
        // Process contact information for text output
        if let contact = processed["contact"] as? [String: Any] {
            if let name = contact["name"] as? String {
                // Decode HTML entities for text output
                let cleanName = name.decodingHTMLEntities()
                processed["centeredName"] = TextFormatHelpers.wrapper(cleanName, width: 80, centered: true)
            }
            
            if let location = contact["location"] as? [String: Any] {
                let city = location["city"] as? String ?? ""
                let state = location["state"] as? String ?? ""
                let phone = contact["phone"] as? String ?? ""
                let email = contact["email"] as? String ?? ""
                let website = contact["website"] as? String ?? ""
                
                let contactLine = "\(city), \(state) * \(phone) * \(email) * \(website)"
                processed["centeredContact"] = TextFormatHelpers.wrapper(contactLine, width: 80, centered: true)
            }
        }
        
        // Process job titles
        if let jobTitles = processed["job-titles"] as? [String] {
            let plainJobTitles = jobTitles.joined(separator: " · ")
            processed["centeredJobTitles"] = TextFormatHelpers.wrapper(plainJobTitles, width: 80, centered: true)
        }
        
        // Process summary with trimming
        if let summary = processed["summary"] as? String {
            let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            processed["wrappedSummary"] = TextFormatHelpers.wrapper(trimmedSummary, width: 80, leftMargin: 6, rightMargin: 6)
        }
        
        // Convert employment to array format and add text formatting
        if let employment = processed["employment"] as? [String: Any] {
            let employmentArray = convertEmploymentToArray(employment, from: resume)
            processed["employment"] = employmentArray
        }
        
        // Handle skills-and-expertise
        if let skillsDict = processed["skills-and-expertise"] as? [String: Any] {
            var skillsArray: [[String: Any]] = []
            for (title, description) in skillsDict {
                skillsArray.append([
                    "title": title,
                    "description": description
                ])
            }
            processed["skills-and-expertise"] = skillsArray
            processed["skillsAndExpertiseFormatted"] = TextFormatHelpers.formatSkillsWithIndent(skillsArray, width: 80, indent: 3)
        } else if let skillsArray = processed["skills-and-expertise"] as? [[String: Any]] {
            processed["skillsAndExpertiseFormatted"] = TextFormatHelpers.formatSkillsWithIndent(skillsArray, width: 80, indent: 3)
        }
        
        // Convert education object to array format
        if let educationDict = processed["education"] as? [String: Any] {
            var educationArray: [[String: Any]] = []
            for (institution, details) in educationDict {
                if var detailsDict = details as? [String: Any] {
                    detailsDict["institution"] = institution
                    educationArray.append(detailsDict)
                }
            }
            processed["education"] = educationArray
        }
        
        // Handle projects-highlights
        if let projectsDict = processed["projects-highlights"] as? [String: Any] {
            var projectsArray: [[String: Any]] = []
            for (name, description) in projectsDict {
                projectsArray.append([
                    "name": name,
                    "description": description
                ])
            }
            processed["projects-highlights"] = projectsArray
            processed["projectsHighlightsFormatted"] = TextFormatHelpers.wrapBlurb(projectsArray)
        } else if let projectsArray = processed["projects-highlights"] as? [[String: Any]] {
            processed["projectsHighlightsFormatted"] = TextFormatHelpers.wrapBlurb(projectsArray)
        }
        
        // Add section line formatting with camelCase conversion
        if let sectionLabels = processed["section-labels"] as? [String: Any] {
            for (key, value) in sectionLabels {
                if let label = value as? String {
                    let camelCaseKey = key.split(separator: "-")
                        .enumerated()
                        .map { index, word in
                            index == 0 ? String(word) : word.capitalized
                        }
                        .joined()
                    processed["sectionLine_\(camelCaseKey)"] = TextFormatHelpers.sectionLine(label, width: 80)
                }
            }
        }
        
        // Process footer text
        if let moreInfo = processed["more-info"] as? String {
            let cleanFooterText = moreInfo.replacingOccurrences(of: #"<\/?[^>]+(>|$)|↪︎"#, with: "", options: .regularExpression).uppercased()
            processed["footerTextFormatted"] = TextFormatHelpers.formatFooter(cleanFooterText, width: 80)
        }
        
        return processed
    }
    
    private func convertEmploymentToArray(_ employment: [String: Any], from resume: Resume) -> [[String: Any]] {
        // Get employment nodes directly from TreeNode structure to preserve sort order
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
                    
                    // Add formatted employment line for text templates
                    let location = detailsDict["location"] as? String ?? ""
                    let start = detailsDict["start"] as? String ?? ""
                    let end = detailsDict["end"] as? String ?? ""
                    detailsDict["employmentFormatted"] = TextFormatHelpers.jobString(employer, location: location, start: start, end: end, width: 80)
                    
                    // Add formatted highlights with proper text wrapping
                    if let highlights = detailsDict["highlights"] as? [String] {
                        let formattedHighlights = highlights.map { highlight in
                            TextFormatHelpers.bulletText(highlight, marginLeft: 2, width: 80, bullet: "•")
                        }
                        detailsDict["highlightsFormatted"] = formattedHighlights
                    }
                    
                    // Add formatted dates for text display
                    detailsDict["startFormatted"] = formatDateForText(start)
                    detailsDict["endFormatted"] = formatDateForText(end)
                    
                    employmentArray.append(detailsDict)
                }
            }
            
            return employmentArray
        }
        
        // Fallback to simple conversion without sorting
        return employment.map { employer, details in
            var detailsDict = details as? [String: Any] ?? [:]
            detailsDict["employer"] = employer
            
            let location = detailsDict["location"] as? String ?? ""
            let start = detailsDict["start"] as? String ?? ""
            let end = detailsDict["end"] as? String ?? ""
            detailsDict["employmentFormatted"] = TextFormatHelpers.jobString(employer, location: location, start: start, end: end, width: 80)
            
            if let highlights = detailsDict["highlights"] as? [String] {
                let formattedHighlights = highlights.map { highlight in
                    TextFormatHelpers.bulletText(highlight, marginLeft: 2, width: 80, bullet: "•")
                }
                detailsDict["highlightsFormatted"] = formattedHighlights
            }
            
            detailsDict["startFormatted"] = formatDateForText(start)
            detailsDict["endFormatted"] = formatDateForText(end)
            
            return detailsDict
        }
    }
    
    private func formatDateForText(_ dateStr: String) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", 
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        
        if dateStr.isEmpty || dateStr.trimmingCharacters(in: .whitespaces) == "undefined" {
            return "Present"
        }
        
        let parts = dateStr.split(separator: "-")
        if parts.count == 2, 
           let year = Int(parts[0]),
           let month = Int(parts[1]), 
           month >= 1 && month <= 12 {
            return "\(months[month - 1]) \(year)"
        }
        
        return dateStr
    }
}
