//
//  ResumeExportService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/16/25.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

//  ResumeExportService.swift
//  Extracted network export logic out of the Resume model so that the core
//  data objects are no longer coupled to URLSession.

protocol ResumeExportServiceProtocol {
    func export(jsonURL: URL, for resume: Resume) async throws
}

@MainActor
class ResumeExportService: ObservableObject {
    private let nativeGenerator = NativePDFGenerator()
    private let apiService = ApiResumeExportService()
    
    @Published var useNativeGeneration = true
    
    func export(jsonURL: URL, for resume: Resume) async throws {
        // Check if the resume's model has custom settings
        let shouldUseNative = resume.model?.useNativeGeneration ?? useNativeGeneration
        
        if shouldUseNative {
            do {
                try await exportNatively(jsonURL: jsonURL, for: resume)
            } catch PDFGeneratorError.templateNotFound {
                // Prompt user to select template files
                try await handleMissingTemplate(for: resume)
            }
        } else {
            try await apiService.export(jsonURL: jsonURL, for: resume)
        }
    }
    
    private func exportNatively(jsonURL: URL, for resume: Resume) async throws {
        let template = resume.model?.templateName ?? resume.model?.style ?? "archer"
        
        // Generate PDF from HTML template (custom or bundled)
        let pdfData: Data
        if let customHTML = resume.model?.customTemplateHTML {
            pdfData = try await nativeGenerator.generatePDFFromCustomTemplate(for: resume, customHTML: customHTML)
        } else {
            pdfData = try await nativeGenerator.generatePDF(for: resume, template: template, format: "html")
        }
        resume.pdfData = pdfData
        
        // Generate text version using text template (custom or bundled)
        let textContent: String
        if let customText = resume.model?.customTemplateText {
            textContent = try nativeGenerator.generateTextFromCustomTemplate(for: resume, customText: customText)
        } else {
            textContent = try nativeGenerator.generateTextResume(for: resume, template: template)
        }
        resume.textRes = textContent
    }
    
    @MainActor
    private func handleMissingTemplate(for resume: Resume) async throws {
        // Show alert to user about missing template
        let alert = NSAlert()
        alert.messageText = "Template Not Found"
        alert.informativeText = "The selected template could not be found. Please select custom template files to continue with native PDF generation."
        alert.addButton(withTitle: "Select Templates")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            throw ResumeExportError.userCancelled
        }
        
        // Prompt for HTML template
        let htmlPanel = NSOpenPanel()
        htmlPanel.title = "Select HTML Template"
        htmlPanel.message = "Choose an HTML template file for PDF generation"
        htmlPanel.allowedContentTypes = [UTType.html, UTType.text]
        htmlPanel.allowsMultipleSelection = false
        
        guard htmlPanel.runModal() == .OK,
              let htmlURL = htmlPanel.url,
              let htmlContent = try? String(contentsOf: htmlURL, encoding: .utf8) else {
            throw ResumeExportError.templateSelectionFailed
        }
        
        // Prompt for CSS file (optional)
        let cssAlert = NSAlert()
        cssAlert.messageText = "CSS File"
        cssAlert.informativeText = "Would you like to include a separate CSS file, or is the styling embedded in the HTML?"
        cssAlert.addButton(withTitle: "Select CSS File")
        cssAlert.addButton(withTitle: "Skip (Use Embedded CSS)")
        cssAlert.addButton(withTitle: "Cancel")
        
        let cssResponse = cssAlert.runModal()
        var finalHTMLContent = htmlContent
        
        if cssResponse == .alertFirstButtonReturn {
            // User wants to select CSS file
            let cssPanel = NSOpenPanel()
            cssPanel.title = "Select CSS File"
            cssPanel.message = "Choose a CSS file to include with the template"
            cssPanel.allowedContentTypes = [UTType.text]
            cssPanel.allowsMultipleSelection = false
            
            if cssPanel.runModal() == .OK,
               let cssURL = cssPanel.url,
               let cssContent = try? String(contentsOf: cssURL, encoding: .utf8) {
                // Embed CSS into HTML
                finalHTMLContent = embedCSSIntoHTML(html: htmlContent, css: cssContent)
            }
        } else if cssResponse == .alertThirdButtonReturn {
            throw ResumeExportError.userCancelled
        }
        
        // Save the custom template to the resume model
        if resume.model == nil {
            // Create a new ResModel if none exists
            let newModel = ResModel(
                name: "Custom Template - \(Date().formatted())",
                json: resume.jsonTxt,
                renderedResumeText: "",
                style: "custom"
            )
            resume.model = newModel
        }
        
        resume.model?.customTemplateHTML = finalHTMLContent
        resume.model?.templateName = "custom-\(Date().timeIntervalSince1970)"
        
        // Now try export again with custom template
        let pdfData = try await nativeGenerator.generatePDFFromCustomTemplate(for: resume, customHTML: finalHTMLContent)
        resume.pdfData = pdfData
        
        // Generate text version (simplified)
        let textContent = try nativeGenerator.generateTextFromCustomTemplate(for: resume, customText: generateBasicTextTemplate())
        resume.textRes = textContent
    }
    
    private func embedCSSIntoHTML(html: String, css: String) -> String {
        // Look for </head> tag and insert CSS before it
        let cssTag = "<style>\n\(css)\n</style>"
        if let headEndRange = html.range(of: "</head>", options: .caseInsensitive) {
            var modifiedHTML = html
            modifiedHTML.insert(contentsOf: "\n\(cssTag)\n", at: headEndRange.lowerBound)
            return modifiedHTML
        } else {
            // If no </head> found, prepend CSS in a style tag
            return "<style>\n\(css)\n</style>\n\(html)"
        }
    }
    
    private func generateBasicTextTemplate() -> String {
        return """
{{r.contact.name}}
{{#each r.job-titles}}{{this}}{{#unless @last}} · {{/unless}}{{/each}}

{{r.contact.location.city}}, {{r.contact.location.state}} • {{r.contact.phone}} • {{r.contact.email}} • {{r.contact.website}}

{{r.summary}}

SKILLS AND EXPERTISE
{{#each r.skills-and-expertise}}
• {{this.title}}: {{this.description}}
{{/each}}

EMPLOYMENT
{{#each r.employment}}
{{this.start}} - {{this.end}} | {{this.position}}, {{this.employer}}
{{#if this.highlights}}
{{#each this.highlights}}
  • {{this}}
{{/each}}
{{/if}}

{{/each}}
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

struct ApiResumeExportService: ResumeExportServiceProtocol {
    private let endpoint = URL(string: "https://resume.physicscloud.net/build-resume-file")!
    
    private var apiKey: String {
        // Try to get from keychain first
        if let storedKey = KeychainHelper.getAPIKey(for: "resume-export-service") {
            return storedKey
        }
        
        // Fallback to default key and store it in keychain
        let defaultKey = "b0b307e1-6eb4-41d9-8c1f-278c254351d3"
        KeychainHelper.setAPIKey(defaultKey, for: "resume-export-service")
        return defaultKey
    }

    func export(jsonURL: URL, for resume: Resume) async throws {
        guard let style = resume.model?.style else { throw ExportError.missingStyle }

        let fileData = try Data(contentsOf: jsonURL)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }

        // style
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"style\"\r\n\r\n")
        append("\(style)\r\n")

        // file
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"resumeFile\"; filename=\"\(jsonURL.lastPathComponent)\"\r\n")
        append("Content-Type: application/json\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pdfUrl = json["pdfUrl"] as? String
        else {
            throw ExportError.invalidResponse
        }

        if let text = json["resumeText"] as? String {
            resume.textRes = text
        }

        try await downloadPDF(from: pdfUrl, into: resume)
    }

    /// Downloads the exported PDF and stores it in the given resume model.
    ///
    /// ⚠️  All writes to `Resume` models **must** occur on the main actor to
    ///     avoid SwiftData/SwiftUI runtime warnings and to ensure UI updates
    ///     are propagated correctly.  Without hopping back to the main actor
    ///     the view displaying the PDF (`ResumePDFView`) would never be
    ///     invalidated after calling `applyChanges()` from `ReviewView`
    ///     because the property change happened on a background thread.
    @MainActor
    private func downloadPDF(from urlString: String, into resume: Resume) async throws {
        guard let url = URL(string: urlString) else { throw ExportError.invalidResponse }

        // Network transfer runs on the current actor (background by default)
        // but the assignment to `resume.pdfData` happens after an explicit
        // hop to the main actor enforced by the `@MainActor` attribute.
        let (data, _) = try await URLSession.shared.data(from: url)
        resume.pdfData = data
    }

    enum ExportError: Error {
        case missingStyle
        case invalidResponse
    }
}
