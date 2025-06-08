//
//  BundledTemplates.swift
//  PhysCloudResume
//
//  Embedded template content for when bundle resources aren't available
//

import Foundation

struct BundledTemplates {
    static func getTemplate(name: String, format: String) -> String? {
        switch (name.lowercased(), format.lowercased()) {
        case ("archer", "html"):
            return archerHTMLTemplate
        case ("archer", "txt"):
            return archerTextTemplate
        case ("typewriter", "html"):
            return typewriterHTMLTemplate
        case ("typewriter", "txt"):
            return typewriterTextTemplate
        default:
            // For custom templates, return nil so they fall back to user-created content
            return nil
        }
    }
    
    // Load from the actual files and embed them
    private static let archerHTMLTemplate: String = {
        if let path = Bundle.main.path(forResource: "archer-template", ofType: "html", inDirectory: "Resources/Templates/archer"),
           let content = try? String(contentsOfFile: path) {
            return content
        }
        // Fallback: load from project directory during development
        let projectPath = "/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resources/Templates/archer/archer-template.html"
        return (try? String(contentsOfFile: projectPath)) ?? "<!-- Archer HTML template not found -->"
    }()
    
    private static let archerTextTemplate: String = {
        if let path = Bundle.main.path(forResource: "archer-template", ofType: "txt", inDirectory: "Resources/Templates/archer"),
           let content = try? String(contentsOfFile: path) {
            return content
        }
        let projectPath = "/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resources/Templates/archer/archer-template.txt"
        return (try? String(contentsOfFile: projectPath)) ?? "# Archer text template not found"
    }()
    
    private static let typewriterHTMLTemplate: String = {
        if let path = Bundle.main.path(forResource: "typewriter-template", ofType: "html", inDirectory: "Resources/Templates/typewriter"),
           let content = try? String(contentsOfFile: path) {
            return content
        }
        let projectPath = "/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resources/Templates/typewriter/typewriter-template.html"
        return (try? String(contentsOfFile: projectPath)) ?? "<!-- Typewriter HTML template not found -->"
    }()
    
    private static let typewriterTextTemplate: String = {
        if let path = Bundle.main.path(forResource: "typewriter-template", ofType: "txt", inDirectory: "Resources/Templates/typewriter"),
           let content = try? String(contentsOfFile: path) {
            return content
        }
        let projectPath = "/Users/cculbreath/devlocal/codebase/PhysCloudResume/PhysCloudResume/Resources/Templates/typewriter/typewriter-template.txt"
        return (try? String(contentsOfFile: projectPath)) ?? "# Typewriter text template not found"
    }()
}