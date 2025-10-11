//
//  TemplateEditorView.swift
//  Sprung
//
//  Template editor for bundled resume templates
//

import SwiftUI
import SwiftData
import AppKit
import PDFKit
import Combine

private struct TextFilterInfo: Identifiable {
    let id = UUID()
    let name: String
    let signature: String
    let description: String
}

private enum TemplateEditorTab: String, CaseIterable, Identifiable {
    case pdfTemplate = "PDF Template"
    case txtTemplate = "TXT Template"
    case manifest = "Data Manifest"
    case seed = "Seed Values"

    var id: String { rawValue }
}

private enum PendingTemplateChange {
    case template
}

struct TemplateEditorView: View {
    @Environment(NavigationStateService.self) private var navigationState
    @Environment(AppEnvironment.self) private var appEnvironment
    
    @State private var selectedTemplate: String = "archer"
    @State private var selectedTab: TemplateEditorTab = .pdfTemplate
    @State private var templateContent: String = ""
    @State private var assetHasChanges: Bool = false
    @State private var showingSaveAlert: Bool = false
    @State private var saveError: String?
    @State private var isGeneratingPreview: Bool = false
    @State private var showingAddTemplate: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var newTemplateName: String = ""
    @State private var manifestContent: String = ""
    @State private var manifestHasChanges: Bool = false
    @State private var manifestValidationMessage: String?
    @State private var seedContent: String = ""
    @State private var seedHasChanges: Bool = false
    @State private var seedValidationMessage: String?
    @State private var pendingTemplateChange: PendingTemplateChange?
    
    // Live preview state
    @State private var previewPDFData: Data?
    @State private var showInspector: Bool = true
    @State private var debounceTimer: Timer?
    @State private var isGeneratingLivePreview: Bool = false
    
    // Overlay state
    @State private var showOverlay: Bool = false
    @State private var overlayPDFData: Data?
    @State private var overlayOpacity: Double = 0.75
    @State private var showingOverlayPicker: Bool = false
    
    @State private var availableTemplates: [String] = []
    
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    private let textFilterReference: [TextFilterInfo] = [
        TextFilterInfo(
            name: "center",
            signature: "center(text, width)",
            description: "Centers the provided text within the given width."
        ),
        TextFilterInfo(
            name: "wrap",
            signature: "wrap(text, width, leftMargin, rightMargin)",
            description: "Wraps text to the specified width with optional margins."
        ),
        TextFilterInfo(
            name: "sectionLine",
            signature: "sectionLine(label, width)",
            description: "Builds a decorative section header line."
        ),
        TextFilterInfo(
            name: "join",
            signature: "join(array, separator)",
            description: "Joins array elements into a single string using the separator."
        ),
        TextFilterInfo(
            name: "bulletList",
            signature: "bulletList(array, width, indent, bullet, valueKey)",
            description: "Formats an array as bullet points. `valueKey` is optional for dictionary arrays."
        ),
        TextFilterInfo(
            name: "formatDate",
            signature: "formatDate(date, outputFormat, inputFormat)",
            description: "Formats dates (default input patterns include ISO and yyyy-MM)."
        ),
        TextFilterInfo(
            name: "uppercase",
            signature: "uppercase(text)",
            description: "Uppercases the provided text if present."
        )
    ]
    
    private var selectedResume: Resume? {
        navigationState.selectedResume
    }

    private func templateDisplayName(_ template: String) -> String {
        template
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func templateIconName(for template: String) -> String {
        templateMatchesSelectedResume(template) ? "doc.text.fill" : "doc.text"
    }

    private func templateMatchesSelectedResume(_ template: String) -> Bool {
        guard let resumeTemplateIdentifier else { return false }
        return resumeTemplateIdentifier == template.lowercased()
    }

    private func toggleInspectorVisibility() {
        guard selectedTab == .pdfTemplate else { return }
        showInspector.toggle()
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    private func updateSplitVisibility(animated: Bool) {
        let shouldShowInspector = showInspector && selectedTab == .pdfTemplate
        let newVisibility: NavigationSplitViewVisibility = shouldShowInspector ? .all : .doubleColumn
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                splitVisibility = newVisibility
            }
        } else {
            splitVisibility = newVisibility
        }
    }
    
    private var hasSelectedResume: Bool {
        selectedResume != nil
    }
    
    private var resumeTemplateIdentifier: String? {
        guard let resume = selectedResume else { return nil }
        if let slug = resume.template?.slug, !slug.isEmpty {
            return slug.lowercased()
        }
        if let name = resume.template?.name, !name.isEmpty {
            return name.lowercased()
        }
        return nil
    }
    
    private var isEditingCurrentTemplate: Bool {
        guard let resumeTemplateIdentifier else { return false }
        return selectedTemplate.lowercased() == resumeTemplateIdentifier && selectedTab == .pdfTemplate
    }

    private var currentFormat: String {
        switch selectedTab {
        case .pdfTemplate:
            return "pdf"
        case .txtTemplate:
            return "txt"
        default:
            return "pdf"
        }
    }

    private var currentHasChanges: Bool {
        switch selectedTab {
        case .pdfTemplate, .txtTemplate:
            return assetHasChanges
        case .manifest:
            return manifestHasChanges
        case .seed:
            return seedHasChanges
        }
    }

    private var hasAnyUnsavedChanges: Bool {
        assetHasChanges || manifestHasChanges || seedHasChanges
    }

    private var templateSelectionBinding: Binding<String?> {
        Binding<String?>(
            get: { selectedTemplate },
            set: { newValue in
                guard let newValue else { return }
                selectedTemplate = newValue
            }
        )
    }

    private var unsavedTabNames: String {
        var names: [String] = []
        if assetHasChanges {
            names.append("Template")
        }
        if manifestHasChanges {
            names.append(TemplateEditorTab.manifest.rawValue)
        }
        if seedHasChanges {
            names.append(TemplateEditorTab.seed.rawValue)
        }
        return names.joined(separator: ", ")
    }

    private var pendingChangeDescription: String {
        switch pendingTemplateChange {
        case .template:
            return "switching views"
        default:
            return "switching views"
        }
    }

    private var unsavedChangesAlertMessage: String {
        let tabs = unsavedTabNames.isEmpty ? "current editor" : unsavedTabNames
        return "Unsaved changes detected in \(tabs). Save them before \(pendingChangeDescription)?"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            templateSidebar()
        } content: {
            editorContainer()
        } detail: {
            inspectorContainer()
        }
        .frame(minWidth: 1024, minHeight: 640)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadAvailableTemplates()
            loadTemplate()
            loadManifest()
            loadSeed()
            manifestHasChanges = false
            seedHasChanges = false
            if selectedTab == .pdfTemplate {
                generateInitialPreview()
            }
            updateSplitVisibility(animated: false)
        }
        .onChange(of: selectedTemplate) { _ in
            if hasAnyUnsavedChanges {
                pendingTemplateChange = .template
                showingSaveAlert = true
            } else {
                applyPendingTemplateChange()
            }
        }
        .onChange(of: selectedTab) { newTab in
            switch newTab {
            case .pdfTemplate, .txtTemplate:
                if hasAnyUnsavedChanges {
                    pendingTemplateChange = .template
                    showingSaveAlert = true
                } else {
                    loadTemplate()
                    if newTab == .pdfTemplate {
                        generateInitialPreview()
                    } else {
                        previewPDFData = nil
                    }
                }
            case .manifest:
                if manifestContent.isEmpty {
                    loadManifest()
                }
            case .seed:
                if seedContent.isEmpty {
                    loadSeed()
                }
            }
            updateSplitVisibility(animated: true)
        }
        .onChange(of: selectedResume?.id) {
            if selectedTab == .pdfTemplate {
                generateInitialPreview()
            }
        }
        .onChange(of: showInspector) { _ in
            updateSplitVisibility(animated: true)
        }
        .alert("Unsaved Changes", isPresented: $showingSaveAlert) {
            Button("Save") {
                if savePendingChanges() {
                    applyPendingTemplateChange()
                }
            }
            Button("Don't Save") {
                discardPendingChanges()
                applyPendingTemplateChange()
            }
            Button("Cancel", role: .cancel) {
                pendingTemplateChange = nil
            }
        } message: {
            Text(unsavedChangesAlertMessage)
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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Template List")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    toggleInspectorVisibility()
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .foregroundStyle((selectedTab == .pdfTemplate && showInspector) ? Color.accentColor : Color.secondary)
                }
                .help(showInspector ? "Hide Preview" : "Show Preview")
                .disabled(selectedTab != .pdfTemplate)
            }

            ToolbarItem(placement: .principal) {
                Picker("Editor Section", selection: $selectedTab) {
                    ForEach(TemplateEditorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }

            ToolbarItem(placement: .status) {
                if hasAnyUnsavedChanges {
                    Label("Unsaved Changes", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button("Revert") {
                    revertCurrentTab()
                }
                .disabled(!currentHasChanges)

                Button("Save") {
                    _ = saveCurrentTab()
                }
                .disabled(!currentHasChanges)

                Button("Save & Close") {
                    if saveCurrentTab(closeAfter: true) {
                        closeEditor()
                    }
                }
                .disabled(!currentHasChanges)
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    closeEditor()
                }
            }

            ToolbarItemGroup(placement: .secondaryAction) {
                Button {
                    showingAddTemplate = true
                } label: {
                    Label("New Template", systemImage: "plus")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Template", systemImage: "trash")
                }
                .disabled(availableTemplates.count <= 1)
            }
        }
    }

    @ViewBuilder
    private func editorContent() -> some View {
        switch selectedTab {
        case .pdfTemplate, .txtTemplate:
            assetsEditor()
        case .manifest:
            manifestEditor()
        case .seed:
            seedEditor()
        }
    }

    @ViewBuilder
    private func editorContainer() -> some View {
        editorContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
    }

    @ViewBuilder
    private func inspectorContainer() -> some View {
        inspectorContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func templateSidebar() -> some View {
        List(selection: templateSelectionBinding) {
            Section("Templates") {
                if availableTemplates.isEmpty {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(availableTemplates, id: \.self) { template in
                        HStack(spacing: 8) {
                            Image(systemName: templateIconName(for: template))
                                .foregroundColor(templateMatchesSelectedResume(template) ? .accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(templateDisplayName(template))
                                if templateMatchesSelectedResume(template) {
                                    Text("Current resume")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .tag(template)
                    }
                }
            }

            if let resume = selectedResume {
                Section("Current Resume") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resume.jobApp?.jobPosition ?? "Untitled Resume")
                            .font(.body)
                        if let company = resume.jobApp?.companyName, !company.isEmpty {
                            Text(company)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
        .navigationTitle("Templates")
    }

    @ViewBuilder
    private func inspectorContent() -> some View {
        switch selectedTab {
        case .pdfTemplate:
            previewInspector()
        case .txtTemplate:
            textTemplateInspector()
        case .manifest:
            manifestInspector()
        case .seed:
            seedInspector()
        }
    }

    private func previewInspector() -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
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
                    if isGeneratingLivePreview || isGeneratingPreview {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                if selectedTab == .pdfTemplate {
                    HStack(spacing: 12) {
                        Button {
                            previewPDF()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGeneratingPreview || !hasSelectedResume)

                        Button {
                            showingOverlayPicker = true
                        } label: {
                            Label("Overlay PDF", systemImage: "square.on.square")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratingPreview)

                        Toggle("Overlay", isOn: $showOverlay)
                            .toggleStyle(.switch)
                            .disabled(overlayPDFData == nil)

                        if showOverlay && overlayPDFData != nil {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Opacity")
                                    .font(.caption)
                                Slider(value: $overlayOpacity, in: 0...1)
                                    .frame(width: 140)
                            }
                        }
                    }
                } else {
                    Text("Preview is available for PDF templates only.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            Group {
                if selectedTab == .pdfTemplate {
                    if let pdfData = previewPDFData {
                        PDFPreviewView(
                            pdfData: pdfData,
                            overlayPDFData: showOverlay ? overlayPDFData : nil,
                            overlayOpacity: overlayOpacity
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 8) {
                            Text("PDF preview will appear here")
                                .foregroundColor(.secondary)
                            if !hasSelectedResume {
                                Text("Select a resume in the main window to enable preview.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Export the resume in the main window to see PDF output.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Text("Switch to PDF format to enable live preview.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(NSColor.textBackgroundColor))

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func textTemplateInspector() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Available Text Filters")
                    .font(.headline)
                ForEach(textFilterReference) { filter in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(filter.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(filter.signature)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(filter.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Divider()
                }
                Text("Filters are Mustache helpers available within TXT templates.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func manifestInspector() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manifest Status")
                .font(.headline)

            if let message = manifestValidationMessage {
                Text(message)
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                Text("Validate manifests before saving seeds to ensure schema completeness.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            if manifestHasChanges {
                Text("Unsaved edits in manifest tab.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func seedInspector() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seed Status")
                .font(.headline)

            if let message = seedValidationMessage {
                Text(message)
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                Text("Promote a resume to seed, then review and save changes.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            if seedHasChanges {
                Text("Unsaved edits in seed tab.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func assetsEditor() -> some View {
        TemplateTextEditor(text: $templateContent) {
            assetHasChanges = true
            if selectedTab == .pdfTemplate {
                scheduleLivePreviewUpdate()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func manifestEditor() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Validate") {
                    validateManifest()
                }
                .buttonStyle(.bordered)
                Button("Save") {
                    saveManifest()
                }
                .disabled(!manifestHasChanges)
                .buttonStyle(.borderedProminent)
                Button("Reload") {
                    loadManifest()
                }
                .buttonStyle(.bordered)
                Spacer()
                if let message = manifestValidationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding([.top, .horizontal])

            TemplateTextEditor(text: $manifestContent) {
                manifestHasChanges = true
                manifestValidationMessage = nil
            }
            .frame(minWidth: 600, minHeight: 400)
        }
    }

    @ViewBuilder
    private func seedEditor() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Promote Current Resume") {
                    promoteCurrentResumeToSeed()
                }
                .disabled(selectedResume == nil)
                .buttonStyle(.bordered)
                Button("Save") {
                    saveSeed()
                }
                .disabled(!seedHasChanges)
                .buttonStyle(.borderedProminent)
                Button("Reload") {
                    loadSeed()
                }
                .buttonStyle(.bordered)
                Spacer()
                if let message = seedValidationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding([.top, .horizontal])

            TemplateTextEditor(text: $seedContent) {
                seedHasChanges = true
                seedValidationMessage = nil
            }
            .frame(minWidth: 600, minHeight: 400)
        }
    }

    private func revertCurrentTab() {
        switch selectedTab {
        case .pdfTemplate, .txtTemplate:
            loadTemplate()
        case .manifest:
            loadManifest()
        case .seed:
            loadSeed()
        }
    }

    @discardableResult
    private func saveCurrentTab(closeAfter: Bool = false) -> Bool {
        let success: Bool
        switch selectedTab {
        case .pdfTemplate, .txtTemplate:
            success = saveTemplate()
        case .manifest:
            success = saveManifest()
        case .seed:
            success = saveSeed()
        }
        if success && closeAfter {
            return true
        }
        return success
    }

    @discardableResult
    private func savePendingChanges() -> Bool {
        var success = true
        if assetHasChanges {
            success = saveTemplate() && success
        }
        if manifestHasChanges {
            success = saveManifest() && success
        }
        if seedHasChanges {
            success = saveSeed() && success
        }
        return success
    }

    private func discardPendingChanges() {
        assetHasChanges = false
        manifestHasChanges = false
        seedHasChanges = false
        manifestValidationMessage = nil
        seedValidationMessage = nil
    }

    private func applyPendingTemplateChange() {
        reloadForTemplateChange()
        pendingTemplateChange = nil
    }

    private func reloadForTemplateChange() {
        loadTemplate()
        loadManifest()
        loadSeed()
        if selectedTab == .pdfTemplate {
            generateInitialPreview()
        } else {
            previewPDFData = nil
        }
    }

    private func loadTemplate() {
        let resourceName = "\(selectedTemplate)-template"
        let fileExtension = currentFormat == "pdf" ? "html" : currentFormat

        // Prefer SwiftData-stored templates when available
        let storedSlug = selectedTemplate.lowercased()
        if fileExtension == "html", let stored = appEnvironment.templateStore.htmlTemplateContent(slug: storedSlug) {
            templateContent = stored
            assetHasChanges = false
            return
        }
        if fileExtension == "txt", let stored = appEnvironment.templateStore.textTemplateContent(slug: storedSlug) {
            templateContent = stored
            assetHasChanges = false
            return
        }

        // Try to load from Documents directory first (user modifications)
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let templatePath = documentsPath
                .appendingPathComponent("Sprung")
                .appendingPathComponent("Templates")
                .appendingPathComponent(selectedTemplate)
                .appendingPathComponent("\(resourceName).\(fileExtension)")
            if let content = try? String(contentsOf: templatePath, encoding: .utf8) {
                templateContent = content
                assetHasChanges = false
                return
            }
        }
        
        // Debug: List bundle contents
        if let bundlePath = Bundle.main.resourcePath {
            let fileManager = FileManager.default
            if let contents = try? fileManager.contentsOfDirectory(atPath: bundlePath) {
                Logger.debug("🗂️ Bundle contents: \(contents)")
                
                // Look for Templates directory
                let templatesPath = bundlePath + "/Templates"
                if fileManager.fileExists(atPath: templatesPath) {
                    if let templateContents = try? fileManager.contentsOfDirectory(atPath: templatesPath) {
                        Logger.debug("📁 Templates directory contents: \(templateContents)")
                    }
                } else {
                    Logger.debug("❓ Templates directory not found in bundle")
                }
            }
        }
        
        // Try multiple bundle lookup strategies
        var bundlePath: String?
        
        // Strategy 1: Resources/Templates subdirectory
        bundlePath = Bundle.main.path(forResource: resourceName, ofType: fileExtension, inDirectory: "Resources/Templates/\(selectedTemplate)")
        if bundlePath != nil {
            Logger.debug("✅ Found via Resources/Templates/\(selectedTemplate)")
        }
        
        // Strategy 2: Templates subdirectory
        if bundlePath == nil {
            bundlePath = Bundle.main.path(forResource: resourceName, ofType: fileExtension, inDirectory: "Templates/\(selectedTemplate)")
            if bundlePath != nil {
                Logger.debug("✅ Found via Templates/\(selectedTemplate)")
            }
        }
        
        // Strategy 3: Direct lookup
        if bundlePath == nil {
            bundlePath = Bundle.main.path(forResource: resourceName, ofType: fileExtension)
            if bundlePath != nil {
                Logger.debug("✅ Found via direct lookup")
            }
        }
        
        if let path = bundlePath,
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            templateContent = content
            assetHasChanges = false
        } else if let embeddedContent = BundledTemplates.getTemplate(name: selectedTemplate, format: fileExtension) {
            templateContent = embeddedContent
            assetHasChanges = false
        } else {
            templateContent = "// Template not found: \(resourceName).\(fileExtension)\n// Bundle path: \(Bundle.main.bundlePath)\n// Resource path: \(Bundle.main.resourcePath ?? "nil")"
            assetHasChanges = false
        }
    }

    private func loadManifest() {
        manifestValidationMessage = nil
        let slug = selectedTemplate.lowercased()

        if let template = appEnvironment.templateStore.template(slug: slug),
           let data = template.manifestData,
           let formatted = prettyJSONString(from: data) {
            manifestContent = formatted
            manifestHasChanges = false
            return
        }

        if let documentsContent = manifestStringFromDocuments(slug: slug) {
            manifestContent = documentsContent
            manifestHasChanges = false
            return
        }

        if let bundleContent = manifestStringFromBundle(slug: slug) {
            manifestContent = bundleContent
            manifestHasChanges = false
            return
        }

        manifestContent = """
{
  \"slug\": \"\(slug)\",
  \"sectionOrder\": [],
  \"sections\": {}
}
"""
        manifestHasChanges = false
    }

    @discardableResult
    private func saveManifest() -> Bool {
        manifestValidationMessage = nil
        let slug = selectedTemplate.lowercased()

        guard let rawData = manifestContent.data(using: .utf8) else {
            manifestValidationMessage = "Unable to encode manifest text."
            return false
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: rawData)
            guard let formatted = prettyJSONString(from: jsonObject),
                  let data = formatted.data(using: .utf8) else {
                manifestValidationMessage = "Manifest must be a valid JSON object."
                return false
            }

            // Decode to ensure it matches expected manifest structure
            _ = try JSONDecoder().decode(TemplateManifest.self, from: data)

            try appEnvironment.templateStore.updateManifest(slug: slug, manifestData: data)
            manifestContent = formatted
            manifestHasChanges = false
            manifestValidationMessage = "Manifest saved."
            return true
        } catch {
            manifestValidationMessage = "Manifest validation failed: \(error.localizedDescription)"
            return false
        }
    }

    private func validateManifest() {
        manifestValidationMessage = nil
        guard let data = manifestContent.data(using: .utf8) else {
            manifestValidationMessage = "Unable to encode manifest text."
            return
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard let formatted = prettyJSONString(from: jsonObject),
                  let normalized = formatted.data(using: .utf8) else {
                manifestValidationMessage = "Manifest must be a valid JSON object."
                return
            }
            _ = try JSONDecoder().decode(TemplateManifest.self, from: normalized)
            manifestContent = formatted
            manifestValidationMessage = "Manifest is valid."
        } catch {
            manifestValidationMessage = "Validation failed: \(error.localizedDescription)"
        }
    }

    private func loadSeed() {
        seedValidationMessage = nil
        let slug = selectedTemplate.lowercased()

        if let template = appEnvironment.templateStore.template(slug: slug),
           let seed = appEnvironment.templateSeedStore.seed(for: template),
           let formatted = prettyJSONString(from: seed.seedData) {
            seedContent = formatted
            seedHasChanges = false
            return
        }

        seedContent = "{}"
        seedHasChanges = false
    }

    @discardableResult
    private func saveSeed() -> Bool {
        seedValidationMessage = nil
        let slug = selectedTemplate.lowercased()

        guard let template = appEnvironment.templateStore.template(slug: slug) else {
            seedValidationMessage = "Template not found."
            return false
        }

        guard let data = seedContent.data(using: .utf8) else {
            seedValidationMessage = "Unable to encode seed JSON."
            return false
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard let formatted = prettyJSONString(from: jsonObject) else {
                seedValidationMessage = "Seed must be valid JSON."
                return false
            }

            appEnvironment.templateSeedStore.upsertSeed(
                slug: slug,
                jsonString: formatted,
                attachTo: template
            )
            seedContent = formatted
            seedHasChanges = false
            seedValidationMessage = "Seed saved."
            return true
        } catch {
            seedValidationMessage = "Seed validation failed: \(error.localizedDescription)"
            return false
        }
    }

    private func promoteCurrentResumeToSeed() {
        seedValidationMessage = nil
        guard let resume = selectedResume else { return }

        do {
            let context = try ResumeTemplateDataBuilder.buildContext(from: resume)
            guard let formatted = prettyJSONString(from: context) else {
                seedValidationMessage = "Unable to serialize resume context."
                return
            }
            seedContent = formatted
            seedHasChanges = true
            seedValidationMessage = "Seed staged from selected resume."
        } catch {
            seedValidationMessage = "Failed to build context: \(error.localizedDescription)"
        }
    }

    private func manifestStringFromDocuments(slug: String) -> String? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let manifestURL = documentsPath
            .appendingPathComponent("Sprung")
            .appendingPathComponent("Templates")
            .appendingPathComponent(slug)
            .appendingPathComponent("\(slug)-manifest.json")
        return try? String(contentsOf: manifestURL, encoding: .utf8)
    }

    private func manifestStringFromBundle(slug: String) -> String? {
        let resourceName = "\(slug)-manifest"
        let candidates: [URL?] = [
            Bundle.main.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: "Resources/Templates/\(slug)"
            ),
            Bundle.main.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: "Templates/\(slug)"
            ),
            Bundle.main.url(forResource: resourceName, withExtension: "json")
        ]

        for candidate in candidates {
            if let url = candidate, let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        return nil
    }

    private func prettyJSONString(from data: Data) -> String? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return prettyJSONString(from: jsonObject)
    }

    private func prettyJSONString(from object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func saveTemplate() -> Bool {
        let resourceName = "\(selectedTemplate)-template"
        let fileExtension = currentFormat == "pdf" ? "html" : currentFormat

        // Save to Documents directory
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            saveError = "Unable to locate Documents directory."
            return false
        }
        let templateDir = documentsPath
            .appendingPathComponent("Sprung")
            .appendingPathComponent("Templates")
            .appendingPathComponent(selectedTemplate)

        do {
            // Create directory if needed
            try FileManager.default.createDirectory(at: templateDir, withIntermediateDirectories: true)
            
            // Write file
            let templatePath = templateDir.appendingPathComponent("\(resourceName).\(fileExtension)")
            try templateContent.write(to: templatePath, atomically: true, encoding: .utf8)
            
            let slug = selectedTemplate.lowercased()
            if fileExtension == "html" {
                appEnvironment.templateStore.upsertTemplate(
                    slug: slug,
                    name: selectedTemplate.capitalized,
                    htmlContent: templateContent,
                    textContent: nil,
                    isCustom: true
                )
            } else if fileExtension == "txt" {
                appEnvironment.templateStore.upsertTemplate(
                    slug: slug,
                    name: selectedTemplate.capitalized,
                    htmlContent: nil,
                    textContent: templateContent,
                    isCustom: true
                )
            }
            
            assetHasChanges = false
            return true
        } catch {
            saveError = "Failed to save template: \(error.localizedDescription)"
            return false
        }
    }
    
    @MainActor
    private func previewPDF() {
        guard selectedTab == .pdfTemplate, let resume = selectedResume else { return }

        // Auto-save if there are changes
        if assetHasChanges {
            _ = saveTemplate()
        }

        isGeneratingPreview = true
        
        Task {
            do {
                let pdfData: Data
                
                if isEditingCurrentTemplate && assetHasChanges {
                    // User is editing the template that the resume uses, so preview with custom content
                    let generator = NativePDFGenerator(templateStore: appEnvironment.templateStore)
                    pdfData = try await generator.generatePDFFromCustomTemplate(
                        for: resume,
                        customHTML: templateContent
                    )
                } else {
                    // Use the same export logic as the normal flow
                    try await appEnvironment.resumeExportCoordinator.ensureFreshRenderedText(for: resume)
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
        let templates = appEnvironment.templateStore.templates()
        if templates.isEmpty {
            availableTemplates = ["archer", "typewriter"]
        } else {
            availableTemplates = templates.map { $0.slug }.sorted()
        }

        if !availableTemplates.contains(selectedTemplate) {
            selectedTemplate = availableTemplates.first ?? "archer"
        }
    }
    
    private func addNewTemplate() {
        let trimmedName = newTemplateName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedName.isEmpty, !availableTemplates.contains(trimmedName) else {
            newTemplateName = ""
            return
        }
        
        let fileExtension = currentFormat == "pdf" ? "html" : currentFormat
        let initialContent = createEmptyTemplate(name: trimmedName, format: fileExtension)
        appEnvironment.templateStore.upsertTemplate(
            slug: trimmedName,
            name: trimmedName.capitalized,
            htmlContent: fileExtension == "html" ? initialContent : nil,
            textContent: fileExtension == "txt" ? initialContent : nil,
            isCustom: true
        )

        loadAvailableTemplates()
        selectedTemplate = trimmedName
        newTemplateName = ""

        templateContent = initialContent
        assetHasChanges = true
        loadManifest()
        loadSeed()
    }

    private func deleteCurrentTemplate() {
        guard availableTemplates.count > 1 else { return }
        
        // Remove from Documents directory if it exists
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let templateDir = documentsPath
                .appendingPathComponent("Sprung")
                .appendingPathComponent("Templates")
                .appendingPathComponent(selectedTemplate)
            try? FileManager.default.removeItem(at: templateDir)
        }
        
        
        // Remove from available templates
        availableTemplates.removeAll { $0 == selectedTemplate }

        appEnvironment.templateStore.deleteTemplate(slug: selectedTemplate.lowercased())
        appEnvironment.templateSeedStore.deleteSeed(forSlug: selectedTemplate.lowercased())

        // Switch to first available template
        selectedTemplate = availableTemplates.first ?? "archer"
        loadTemplate()
        loadManifest()
        loadSeed()
        loadAvailableTemplates()
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
{{{ center(contact.name, 80) }}}

{{{ center(join(job-titles), 80) }}}

{{#contactLine}}
{{{ center(contactLine, 80) }}}
{{/contactLine}}

{{{ wrap(summary, 80, 6, 6) }}}

{{#section-labels.employment}}
{{{ sectionLine(section-labels.employment, 80) }}}
{{/section-labels.employment}}
{{#employment}}
{{ employer }}{{#location}} | {{{.}}}{{/location}}
{{#position}}
{{ position }}
{{/position}}
{{ formatDate(start) }} – {{ formatDate(end) }}
{{{ bulletList(highlights, 80, 2, "•") }}}

{{/employment}}

{{#more-info}}
{{{ wrap(uppercase(more-info), 80, 0, 0) }}}
{{/more-info}}
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
        guard selectedTab == .pdfTemplate else { return }
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
        guard selectedTab == .pdfTemplate else { return }
        Task {
            await generateLivePreview()
        }
    }

    @MainActor
    private func generateLivePreview() async {
        guard selectedTab == .pdfTemplate, let resume = selectedResume else { return }

        // If we're not editing the current template, just show the existing PDF
        if !isEditingCurrentTemplate || !assetHasChanges {
            previewPDFData = resume.pdfData
            return
        }
        
        // Only generate live preview when editing the current template
        isGeneratingLivePreview = true
        
        // Auto-save template changes and use normal export flow
        if assetHasChanges {
            _ = saveTemplate()
        }
        
        do {
            // Use the normal TreeNode→JSON→export flow for consistency
            try await appEnvironment.resumeExportCoordinator.ensureFreshRenderedText(for: resume)
            previewPDFData = resume.pdfData
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
