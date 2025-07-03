//
//  ResumeTemplateProcessor.swift
//  PhysCloudResume
//
//  Created by Assistant on 12/20/24.
//

import Foundation

/// Shared template processing logic for resume generation
@MainActor
class ResumeTemplateProcessor {
    
    /// Create template context from Resume data
    static func createTemplateContext(from resume: Resume) throws -> [String: Any] {
        // Use the TreeToJson system to generate proper JSON structure
        guard let rootNode = resume.rootNode else {
            throw NSError(domain: "ResumeTemplateProcessor", code: 1001,
                         userInfo: [NSLocalizedDescriptionKey: "No root node found in resume"])
        }
        
        // Generate JSON using TreeToJson system
        guard let treeToJson = TreeToJson(rootNode: rootNode) else {
            throw NSError(domain: "ResumeTemplateProcessor", code: 1001,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to initialize TreeToJson"])
        }
        
        let jsonString = treeToJson.buildJsonString()
        Logger.debug("Generated JSON for template: \(jsonString)")
        
        // Parse the generated JSON
        guard let data = jsonString.data(using: String.Encoding.utf8),
              let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ResumeTemplateProcessor", code: 1001,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse generated JSON"])
        }
        
        return jsonObject
    }
    
    /// Load template content from various sources
    static func loadTemplate(named template: String, format: String) throws -> String {
        let resourceName = "\(template.lowercased())-template"
        var templateContent: String?
        
        // Strategy 0: Check Documents directory first for user modifications
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let userTemplatePath = documentsPath
            .appendingPathComponent("PhysCloudResume")
            .appendingPathComponent("Templates")
            .appendingPathComponent(template)
            .appendingPathComponent("\(resourceName).\(format)")
        
        if let content = try? String(contentsOf: userTemplatePath, encoding: .utf8) {
            templateContent = content
            Logger.debug("Using user-modified template from: \(userTemplatePath.path)")
        }
        
        // Strategy 1: Look in Templates/template subdirectory
        if templateContent == nil {
            if let path = Bundle.main.path(forResource: resourceName, ofType: format, inDirectory: "Templates/\(template)") {
                templateContent = try? String(contentsOfFile: path, encoding: .utf8)
            }
        }
        
        // Strategy 2: Look directly in main bundle
        if templateContent == nil {
            if let path = Bundle.main.path(forResource: resourceName, ofType: format) {
                templateContent = try? String(contentsOfFile: path, encoding: .utf8)
            }
        }
        
        // Strategy 3: Look for the template file anywhere in the bundle
        if templateContent == nil {
            let bundlePath = Bundle.main.bundlePath
            let fileManager = FileManager.default
            let enumerator = fileManager.enumerator(atPath: bundlePath)
            while let file = enumerator?.nextObject() as? String {
                if file.hasSuffix("\(resourceName).\(format)") {
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
            templateContent = BundledTemplates.getTemplate(name: template, format: format)
            if templateContent != nil {
                Logger.debug("Using embedded template for \(template).\(format)")
            }
        }
        
        guard let content = templateContent else {
            throw NSError(domain: "ResumeTemplateProcessor", code: 404,
                         userInfo: [NSLocalizedDescriptionKey: "Template not found: \(template).\(format)"])
        }
        
        return content
    }
    
    /// Convert employment dictionary to sorted array preserving TreeNode order
    static func convertEmploymentToArrayWithSorting(_ employment: [String: Any], from resume: Resume) -> [[String: Any]] {
        // Get employment nodes directly from TreeNode structure to preserve sort order
        guard let rootNode = resume.rootNode,
              let employmentSection = rootNode.children?.first(where: { $0.name == "employment" }),
              let employmentNodes = employmentSection.children else {
            // Fallback to simple conversion
            return convertEmploymentToArray(employment)
        }
        
        // Sort by TreeNode myIndex to preserve user's drag-and-drop ordering
        let sortedNodes = employmentNodes.sorted { $0.myIndex < $1.myIndex }
        
        var employmentArray: [[String: Any]] = []
        
        for node in sortedNodes {
            let employer = node.name
            if let details = employment[employer] as? [String: Any] {
                var detailsDict = details
                detailsDict["employer"] = employer
                employmentArray.append(detailsDict)
            }
        }
        
        return employmentArray
    }
    
    /// Simple employment conversion without sorting
    static func convertEmploymentToArray(_ employment: [String: Any]) -> [[String: Any]] {
        var employmentArray: [[String: Any]] = []
        
        for (employer, details) in employment {
            if var detailsDict = details as? [String: Any] {
                detailsDict["employer"] = employer
                employmentArray.append(detailsDict)
            }
        }
        
        return employmentArray
    }
}