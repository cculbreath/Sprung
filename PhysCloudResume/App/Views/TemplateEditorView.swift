//
//  TemplateEditorView.swift
//  PhysCloudResume
//
//  Template editor for bundled resume templates
//

import SwiftUI
import SwiftData
import AppKit

struct TemplateEditorView: View {
    @Query private var resumes: [Resume]
    
    @State private var selectedTemplate: String = "archer"
    @State private var selectedFormat: String = "html"
    @State private var templateContent: String = ""
    @State private var hasChanges: Bool = false
    @State private var showingSaveAlert: Bool = false
    @State private var saveError: String?
    @State private var isGeneratingPreview: Bool = false
    @State private var showingAddTemplate: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var newTemplateName: String = ""
    
    // AppStorage for available templates (same as styles)
    @AppStorage("availableStyles") private var availableStylesString: String = "Typewriter"
    @State private var availableTemplates: [String] = []
    
    let formats = ["html", "txt"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Template picker
                Picker("Template:", selection: $selectedTemplate) {
                    ForEach(availableTemplates, id: \.self) { template in
                        Text(template.capitalized).tag(template)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 150)
                
                // Add template button
                Button(action: { showingAddTemplate = true }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.green)
                }
                .help("Add new template")
                
                // Delete template button
                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.red)
                }
                .disabled(availableTemplates.count <= 1)
                .help("Delete current template")
                
                // Format picker
                Picker("Format:", selection: $selectedFormat) {
                    ForEach(formats, id: \.self) { format in
                        Text(format.uppercased()).tag(format)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 100)
                
                Spacer()
                
                // Revert button
                Button("Revert") {
                    loadTemplate()
                    hasChanges = false
                }
                .disabled(!hasChanges)
                
                // Save button
                Button("Save") {
                    saveTemplate()
                }
                .disabled(!hasChanges)
                
                // Preview button
                Button("Preview PDF") {
                    previewPDF()
                }
                .disabled(selectedFormat != "html" || isGeneratingPreview || resumes.isEmpty)
                .help(resumes.isEmpty ? "No resumes available for preview" : "Generate and preview a PDF using the current template")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Template editor
            ScrollView {
                TextEditor(text: $templateContent)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: templateContent) { _ in
                        hasChanges = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadAvailableTemplates()
            loadTemplate()
        }
        .onChange(of: selectedTemplate) { _ in
            if hasChanges {
                showingSaveAlert = true
            } else {
                loadTemplate()
            }
        }
        .onChange(of: selectedFormat) { _ in
            if hasChanges {
                showingSaveAlert = true
            } else {
                loadTemplate()
            }
        }
        .alert("Unsaved Changes", isPresented: $showingSaveAlert) {
            Button("Save") {
                saveTemplate()
                loadTemplate()
            }
            Button("Don't Save") {
                hasChanges = false
                loadTemplate()
            }
            Button("Cancel", role: .cancel) {
                // Revert the selection
                // This is a bit tricky with SwiftUI, so we'll just leave it
            }
        } message: {
            Text("You have unsaved changes. Do you want to save them before switching templates?")
        }
        .alert("Save Error", isPresented: .constant(saveError != nil)) {
            Button("OK") {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "Unknown error")
        }
        .alert("Add New Template", isPresented: $showingAddTemplate) {
            TextField("Template name", text: $newTemplateName)
            Button("Add") {
                addNewTemplate()
            }
            Button("Cancel", role: .cancel) { 
                newTemplateName = ""
            }
        } message: {
            Text("Enter a name for the new template")
        }
        .alert("Delete Template", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteCurrentTemplate()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete the '\(selectedTemplate)' template? This cannot be undone.")
        }
    }
    
    private func loadTemplate() {
        let resourceName = "\(selectedTemplate)-template"
        
        // Try to load from Documents directory first (user modifications)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let templatePath = documentsPath
            .appendingPathComponent("PhysCloudResume")
            .appendingPathComponent("Templates")
            .appendingPathComponent(selectedTemplate)
            .appendingPathComponent("\(resourceName).\(selectedFormat)")
        
        if let content = try? String(contentsOf: templatePath) {
            templateContent = content
            hasChanges = false
            return
        }
        
        // Debug: List bundle contents
        if let bundlePath = Bundle.main.resourcePath {
            let fileManager = FileManager.default
            if let contents = try? fileManager.contentsOfDirectory(atPath: bundlePath) {
                print("Bundle contents: \(contents)")
                
                // Look for Templates directory
                let templatesPath = bundlePath + "/Templates"
                if fileManager.fileExists(atPath: templatesPath) {
                    if let templateContents = try? fileManager.contentsOfDirectory(atPath: templatesPath) {
                        print("Templates directory contents: \(templateContents)")
                    }
                } else {
                    print("Templates directory not found in bundle")
                }
            }
        }
        
        // Try multiple bundle lookup strategies
        var bundlePath: String?
        
        // Strategy 1: Resources/Templates subdirectory
        bundlePath = Bundle.main.path(forResource: resourceName, ofType: selectedFormat, inDirectory: "Resources/Templates/\(selectedTemplate)")
        if bundlePath != nil {
            print("Found via Resources/Templates/\(selectedTemplate)")
        }
        
        // Strategy 2: Templates subdirectory
        if bundlePath == nil {
            bundlePath = Bundle.main.path(forResource: resourceName, ofType: selectedFormat, inDirectory: "Templates/\(selectedTemplate)")
            if bundlePath != nil {
                print("Found via Templates/\(selectedTemplate)")
            }
        }
        
        // Strategy 3: Direct lookup
        if bundlePath == nil {
            bundlePath = Bundle.main.path(forResource: resourceName, ofType: selectedFormat)
            if bundlePath != nil {
                print("Found via direct lookup")
            }
        }
        
        if let path = bundlePath,
           let content = try? String(contentsOfFile: path) {
            templateContent = content
            hasChanges = false
        } else if let embeddedContent = BundledTemplates.getTemplate(name: selectedTemplate, format: selectedFormat) {
            templateContent = embeddedContent
            hasChanges = false
        } else {
            templateContent = "// Template not found: \(resourceName).\(selectedFormat)\n// Bundle path: \(Bundle.main.bundlePath)\n// Resource path: \(Bundle.main.resourcePath ?? "nil")"
            hasChanges = false
        }
    }
    
    private func saveTemplate() {
        let resourceName = "\(selectedTemplate)-template"
        
        // Save to Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let templateDir = documentsPath
            .appendingPathComponent("PhysCloudResume")
            .appendingPathComponent("Templates")
            .appendingPathComponent(selectedTemplate)
        
        do {
            // Create directory if needed
            try FileManager.default.createDirectory(at: templateDir, withIntermediateDirectories: true)
            
            // Write file
            let templatePath = templateDir.appendingPathComponent("\(resourceName).\(selectedFormat)")
            try templateContent.write(to: templatePath, atomically: true, encoding: .utf8)
            
            hasChanges = false
        } catch {
            saveError = "Failed to save template: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func previewPDF() {
        guard let firstResume = resumes.first else { return }
        guard !hasChanges else {
            saveError = "Please save your changes before previewing"
            return
        }
        
        isGeneratingPreview = true
        
        Task {
            do {
                let generator = NativePDFGenerator()
                let pdfData = try await generator.generatePDF(for: firstResume, template: selectedTemplate, format: "html")
                
                // Save to temp file and open
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("template_preview_\(UUID().uuidString).pdf")
                try pdfData.write(to: tempURL)
                
                // Open in default PDF viewer
                NSWorkspace.shared.open(tempURL)
                
                isGeneratingPreview = false
            } catch {
                isGeneratingPreview = false
                saveError = "Failed to generate preview: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Template Management
    
    private func loadAvailableTemplates() {
        availableTemplates = availableStylesString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Ensure defaults are present
        let defaults = ["archer", "typewriter"]
        for defaultTemplate in defaults {
            if !availableTemplates.contains(defaultTemplate) {
                availableTemplates.append(defaultTemplate)
            }
        }
        
        // If no templates, add defaults
        if availableTemplates.isEmpty {
            availableTemplates = defaults
        }
        
        // Ensure selected template is valid
        if !availableTemplates.contains(selectedTemplate) {
            selectedTemplate = availableTemplates.first ?? "archer"
        }
        
        saveAvailableTemplates()
    }
    
    private func addNewTemplate() {
        let trimmedName = newTemplateName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedName.isEmpty, !availableTemplates.contains(trimmedName) else {
            newTemplateName = ""
            return
        }
        
        availableTemplates.append(trimmedName)
        saveAvailableTemplates()
        selectedTemplate = trimmedName
        newTemplateName = ""
        
        // Create initial empty template content
        templateContent = createEmptyTemplate(name: trimmedName, format: selectedFormat)
        hasChanges = true
    }
    
    private func deleteCurrentTemplate() {
        guard availableTemplates.count > 1 else { return }
        
        // Remove from Documents directory if it exists
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let templateDir = documentsPath
            .appendingPathComponent("PhysCloudResume")
            .appendingPathComponent("Templates")
            .appendingPathComponent(selectedTemplate)
        
        try? FileManager.default.removeItem(at: templateDir)
        
        // Remove from available templates
        availableTemplates.removeAll { $0 == selectedTemplate }
        saveAvailableTemplates()
        
        // Switch to first available template
        selectedTemplate = availableTemplates.first ?? "archer"
        loadTemplate()
    }
    
    private func saveAvailableTemplates() {
        availableStylesString = availableTemplates.joined(separator: ", ")
    }
    
    private func createEmptyTemplate(name: String, format: String) -> String {
        switch format {
        case "html":
            return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>{{{contact.name}}}</title>
    <style>
        /* Add your CSS here */
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { text-align: center; margin-bottom: 20px; }
        .name { font-size: 24px; font-weight: bold; }
        .job-titles { font-size: 16px; color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <div class="name">{{{contact.name}}}</div>
        <div class="job-titles">{{{jobTitlesJoined}}}</div>
    </div>
    
    <div class="contact">
        <p>{{contact.email}} | {{contact.phone}} | {{contact.location.city}}, {{contact.location.state}}</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <p>{{{summary}}}</p>
    </div>
    
    <!-- Add more sections as needed -->
</body>
</html>
"""
        case "txt":
            return """
{{{centeredName}}}
{{{centeredJobTitles}}}
{{{centeredContact}}}

{{{sectionLine_summary}}}
{{{wrappedSummary}}}

{{{sectionLine_employment}}}
{{#employment}}
{{{employmentFormatted}}}
{{#highlights}}
{{#.}}
* {{.}}
{{/.}}
{{/highlights}}

{{/employment}}

{{{footerTextFormatted}}}
"""
        default:
            return "// New \(name) template in \(format) format"
        }
    }
}

struct TemplateEditorWindow: View {
    var body: some View {
        TemplateEditorView()
            .frame(minWidth: 800, minHeight: 600)
    }
}