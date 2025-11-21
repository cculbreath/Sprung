//
//  ExportTemplateSelection.swift
//  Sprung
//
//  Encapsulates alerts and file pickers used during export to keep UI logic
//  separate from service orchestration.
//
import AppKit
import UniformTypeIdentifiers
import Foundation
enum ExportTemplateSelectionError: Error {
    case userCancelled
    case failedToReadFile
}
struct ExportTemplateSelection {
    /// Show an alert for missing template and prompt the user to select template files.
    /// - Returns: HTML content and optional CSS content
    static func requestTemplateHTMLAndOptionalCSS() throws -> (html: String, css: String?) {
        // Alert explaining the situation
        let alert = NSAlert()
        alert.messageText = "Template Not Found"
        alert.informativeText = "The selected template could not be found. Please select custom template files to continue with native PDF generation."
        alert.addButton(withTitle: "Select Templates")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        guard alert.runModal() == .alertFirstButtonReturn else { throw ExportTemplateSelectionError.userCancelled }
        // Pick HTML template
        let htmlPanel = NSOpenPanel()
        htmlPanel.title = "Select HTML Template"
        htmlPanel.message = "Choose an HTML template file for PDF generation"
        htmlPanel.allowedContentTypes = [UTType.html, UTType.text]
        htmlPanel.allowsMultipleSelection = false
        guard htmlPanel.runModal() == .OK, let htmlURL = htmlPanel.url else { throw ExportTemplateSelectionError.userCancelled }
        guard let htmlContent = try? String(contentsOf: htmlURL, encoding: .utf8) else { throw ExportTemplateSelectionError.failedToReadFile }
        // Ask about CSS
        let cssAlert = NSAlert()
        cssAlert.messageText = "CSS File"
        cssAlert.informativeText = "Would you like to include a separate CSS file, or is the styling embedded in the HTML?"
        cssAlert.addButton(withTitle: "Select CSS File")
        cssAlert.addButton(withTitle: "Skip (Use Embedded CSS)")
        cssAlert.addButton(withTitle: "Cancel")
        let cssResponse = cssAlert.runModal()
        if cssResponse == .alertFirstButtonReturn {
            let cssPanel = NSOpenPanel()
            cssPanel.title = "Select CSS File"
            cssPanel.message = "Choose a CSS file to include with the template"
            cssPanel.allowedContentTypes = [UTType.text]
            cssPanel.allowsMultipleSelection = false
            if cssPanel.runModal() == .OK, let cssURL = cssPanel.url, let cssContent = try? String(contentsOf: cssURL, encoding: .utf8) {
                return (html: htmlContent, css: cssContent)
            } else {
                // Treat cancel as no CSS
                return (html: htmlContent, css: nil)
            }
        } else if cssResponse == .alertSecondButtonReturn {
            return (html: htmlContent, css: nil)
        } else {
            throw ExportTemplateSelectionError.userCancelled
        }
    }
}
