//
//  TemplateEditorView.swift
//  PhysCloudResume
//
//  Template editor for bundled resume templates
//

import SwiftUI
import SwiftData
import AppKit
import PDFKit
import Combine

struct TemplateEditorView: View {
    @Query private var resumes: [Resume]
    @Environment(\.appState) private var appState
    
    @State private var selectedTemplate: String = "archer"
    @State private var selectedFormat: String = "pdf"
    @State private var templateContent: String = ""
    @State private var hasChanges: Bool = false
    @State private var showingSaveAlert: Bool = false
    @State private var saveError: String?
    @State private var isGeneratingPreview: Bool = false
    @State private var showingAddTemplate: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var newTemplateName: String = ""
    
    // Live preview state
    @State private var previewPDFData: Data?
    @State private var debounceTimer: Timer?
    @State private var isGeneratingLivePreview: Bool = false
    
    // Overlay state
    @State private var showOverlay: Bool = false
    @State private var overlayPDFData: Data?
    @State private var overlayOpacity: Double = 0.75
    @State private var showingOverlayPicker: Bool = false
    
    // AppStorage for available templates (same as styles)
    @AppStorage("availableStyles") private var availableStylesString: String = "Typewriter"
    @State private var availableTemplates: [String] = []
    
    let formats = ["pdf", "txt"]
    
    private var selectedResume: Resume? {
        appState.selectedResume
    }
    
    private var hasSelectedResume: Bool {
        selectedResume != nil
    }
    
    private var isEditingCurrentTemplate: Bool {
        guard let resume = selectedResume else { return false }
        let resumeTemplate = resume.model?.templateName ?? resume.model?.style ?? "archer"
        return selectedTemplate.lowercased() == resumeTemplate.lowercased() && selectedFormat == "pdf"
    }
    
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
                .frame(width: 120)
                
                Spacer()
                
                // Revert button
                Button("Revert") {
                    loadTemplate()
                    hasChanges = false
                }
                .disabled(!hasChanges)
                
                // Save button
                Button("Save & Close") {
                    saveTemplate()
                    closeEditor()
                }
                .disabled(!hasChanges)
                
                // Cancel button
                Button("Cancel") {
                    closeEditor()
                }
                
                // Preview button
                Button("Preview PDF") {
                    previewPDF()
                }
                .disabled(selectedFormat != "pdf" || isGeneratingPreview || !hasSelectedResume)
                .help(!hasSelectedResume ? "No resume selected in main window" : "Generate and preview a PDF using the current template")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Main content area with split view
            HSplitView {
                // Template editor with find functionality
                TemplateTextEditor(text: $templateContent) {
                    hasChanges = true
                    if selectedFormat == "pdf" {
                        scheduleLivePreviewUpdate()
                    }
                }
                .frame(minWidth: 400)
                
                // PDF Preview
                VStack(spacing: 0) {
                    // Preview controls toolbar
                    HStack {
                        Text("Preview")
                            .font(.headline)
                        
                        if isEditingCurrentTemplate {
                            Text("(Live)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("(Current Resume)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Overlay controls
                        Toggle("Overlay", isOn: $showOverlay)
                            .disabled(overlayPDFData == nil)
                        
                        if showOverlay && overlayPDFData != nil {
                            Slider(value: $overlayOpacity, in: 0...1) {
                                Text("Opacity")
                            }
                            .frame(width: 100)
                        }
                        
                        Button("Select Overlay PDF") {
                            showingOverlayPicker = true
                        }
                        .buttonStyle(.bordered)
                        
                        if isGeneratingLivePreview {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    // PDF viewer
                    if selectedFormat == "pdf" {
                        if let pdfData = previewPDFData {
                            PDFPreviewView(
                                pdfData: pdfData,
                                overlayPDFData: showOverlay ? overlayPDFData : nil,
                                overlayOpacity: overlayOpacity
                            )
                        } else {
                            VStack {
                                Text("PDF preview will appear here")
                                    .foregroundColor(.secondary)
                                if !hasSelectedResume {
                                    Text("Select a resume in the main window to enable preview")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Export the resume in the main window to see PDF")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        Text("PDF preview only available for HTML templates")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 400)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadAvailableTemplates()
            loadTemplate()
            if selectedFormat == "pdf" {
                generateInitialPreview()
            }
        }
        .onChange(of: selectedTemplate) {
            if hasChanges {
                showingSaveAlert = true
            } else {
                loadTemplate()
                if selectedFormat == "pdf" {
                    generateInitialPreview()
                }
            }
        }
        .onChange(of: selectedFormat) {
            if hasChanges {
                showingSaveAlert = true
            } else {
                loadTemplate()
                if selectedFormat == "pdf" {
                    generateInitialPreview()
                }
            }
        }
        .onChange(of: selectedResume?.id) {
            // When the selected resume changes, update the preview
            if selectedFormat == "pdf" {
                generateInitialPreview()
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
        .fileImporter(
            isPresented: $showingOverlayPicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let files):
                if let file = files.first {
                    loadOverlayPDF(from: file)
                }
            case .failure(let error):
                saveError = "Failed to load overlay PDF: \(error.localizedDescription)"
            }
        }
    }
    
    private func loadTemplate() {
        let resourceName = "\(selectedTemplate)-template"
        let fileExtension = selectedFormat == "pdf" ? "html" : selectedFormat
        
        // Try to load from Documents directory first (user modifications)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let templatePath = documentsPath
            .appendingPathComponent("PhysCloudResume")
            .appendingPathComponent("Templates")
            .appendingPathComponent(selectedTemplate)
            .appendingPathComponent("\(resourceName).\(fileExtension)")
        
        if let content = try? String(contentsOf: templatePath, encoding: .utf8) {
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
        bundlePath = Bundle.main.path(forResource: resourceName, ofType: fileExtension, inDirectory: "Resources/Templates/\(selectedTemplate)")
        if bundlePath != nil {
            print("Found via Resources/Templates/\(selectedTemplate)")
        }
        
        // Strategy 2: Templates subdirectory
        if bundlePath == nil {
            bundlePath = Bundle.main.path(forResource: resourceName, ofType: fileExtension, inDirectory: "Templates/\(selectedTemplate)")
            if bundlePath != nil {
                print("Found via Templates/\(selectedTemplate)")
            }
        }
        
        // Strategy 3: Direct lookup
        if bundlePath == nil {
            bundlePath = Bundle.main.path(forResource: resourceName, ofType: fileExtension)
            if bundlePath != nil {
                print("Found via direct lookup")
            }
        }
        
        if let path = bundlePath,
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            templateContent = content
            hasChanges = false
        } else if let embeddedContent = BundledTemplates.getTemplate(name: selectedTemplate, format: fileExtension) {
            templateContent = embeddedContent
            hasChanges = false
        } else {
            templateContent = "// Template not found: \(resourceName).\(fileExtension)\n// Bundle path: \(Bundle.main.bundlePath)\n// Resource path: \(Bundle.main.resourcePath ?? "nil")"
            hasChanges = false
        }
    }
    
    private func saveTemplate() {
        let resourceName = "\(selectedTemplate)-template"
        let fileExtension = selectedFormat == "pdf" ? "html" : selectedFormat
        
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
            let templatePath = templateDir.appendingPathComponent("\(resourceName).\(fileExtension)")
            try templateContent.write(to: templatePath, atomically: true, encoding: .utf8)
            
            hasChanges = false
        } catch {
            saveError = "Failed to save template: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func previewPDF() {
        guard let resume = selectedResume else { return }
        
        // Auto-save if there are changes
        if hasChanges {
            saveTemplate()
        }
        
        isGeneratingPreview = true
        
        Task {
            do {
                let pdfData: Data
                
                if isEditingCurrentTemplate && hasChanges {
                    // User is editing the template that the resume uses, so preview with custom content
                    let generator = NativePDFGenerator()
                    pdfData = try await generator.generatePDFFromCustomTemplate(
                        for: resume,
                        customHTML: templateContent
                    )
                } else {
                    // Use the same export logic as the normal flow
                    try await resume.ensureFreshRenderedText()
                    pdfData = resume.pdfData ?? Data()
                }
                
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
        let fileExtension = selectedFormat == "pdf" ? "html" : selectedFormat
        templateContent = createEmptyTemplate(name: trimmedName, format: fileExtension)
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
    
    private func closeEditor() {
        // Close the template editor window
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Template Editor" }) {
            window.close()
        }
    }
    
    // MARK: - Live Preview Methods
    
    private func scheduleLivePreviewUpdate() {
        // Cancel existing timer
        debounceTimer?.invalidate()
        
        // Schedule new update after 0.5 seconds
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            Task { @MainActor in
                await generateLivePreview()
            }
        }
    }
    
    @MainActor
    private func generateInitialPreview() {
        Task {
            await generateLivePreview()
        }
    }
    
    @MainActor
    private func generateLivePreview() async {
        guard let resume = selectedResume else { return }
        
        // If we're not editing the current template, just show the existing PDF
        if !isEditingCurrentTemplate || !hasChanges {
            previewPDFData = resume.pdfData
            return
        }
        
        // Only generate live preview when editing the current template
        isGeneratingLivePreview = true
        
        do {
            let generator = NativePDFGenerator()
            // User is editing the template that the resume uses, so preview with custom content
            let pdfData = try await generator.generatePDFFromCustomTemplate(
                for: resume,
                customHTML: templateContent
            )
            previewPDFData = pdfData
        } catch {
            // Don't show error for live preview, just log it
            Logger.error("Live preview generation failed: \(error)")
        }
        
        isGeneratingLivePreview = false
    }
    
    private func loadOverlayPDF(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            saveError = "Failed to access overlay PDF"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            overlayPDFData = try Data(contentsOf: url)
        } catch {
            saveError = "Failed to load overlay PDF: \(error.localizedDescription)"
        }
    }
}

struct TemplateEditorWindow: View {
    var body: some View {
        TemplateEditorView()
            .frame(minWidth: 800, minHeight: 600)
    }
}