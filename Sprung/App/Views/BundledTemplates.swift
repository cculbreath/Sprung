//
//  BundledTemplates.swift
//  Sprung
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
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            return content
        }
        return "<!-- Archer HTML template not found -->"
    }()
    
    private static let archerTextTemplate: String = {
        if let path = Bundle.main.path(forResource: "archer-template", ofType: "txt", inDirectory: "Resources/Templates/archer"),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            return content
        }
        return "# Archer text template not found"
    }()
    
    private static let typewriterHTMLTemplate: String = {
        if let path = Bundle.main.path(forResource: "typewriter-template", ofType: "html", inDirectory: "Resources/Templates/typewriter"),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            return content
        }
        return "<!-- Typewriter HTML template not found -->"
    }()
    
    private static let typewriterTextTemplate: String = {
        if let path = Bundle.main.path(forResource: "typewriter-template", ofType: "txt", inDirectory: "Resources/Templates/typewriter"),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            return content
        }
        return "# Typewriter text template not found"
    }()
}
