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

private extension Color {
    func toNSColor(fallback: NSColor = .systemBlue) -> NSColor {
#if os(macOS)
        if let cgColor = self.cgColor {
            return NSColor(cgColor: cgColor) ?? fallback
        }
        if #available(macOS 12.0, *) {
            return NSColor(self)
        }
#endif
        return fallback
    }
}

private struct TextFilterInfo: Identifiable {
    let id = UUID()
    let name: String
    let signature: String
    let description: String
    let snippet: String
}

private enum TemplateEditorTab: String, CaseIterable, Identifiable {
    case pdfTemplate = "PDF Template"
    case manifest = "Data Manifest"
    case txtTemplate = "Text Template"
    case seed = "Default Values"

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
    @State private var overlayPDFDocument: PDFDocument?
    @State private var overlayPageIndex: Int = 0
    @State private var overlayOpacity: Double = 0.75
    @State private var showingOverlayPicker: Bool = false
    @State private var overlayColor: Color = Color.blue.opacity(0.85)
    @State private var overlayColorSelection: Color = Color.blue.opacity(0.85)
    @State private var showOverlayOptionsSheet: Bool = false
    @State private var pendingOverlayDocument: PDFDocument?
    @State private var overlayPageCount: Int = 0
    @State private var overlayFilename: String?
    @State private var overlayPageSelection: Int = 0
    
    @State private var availableTemplates: [String] = []
    
    @State private var showSidebar: Bool = true
    @State private var sidebarWidth: CGFloat = 180
    private let sidebarWidthRange: ClosedRange<CGFloat> = 150...300
    @State private var textEditorInsertion: TextEditorInsertionRequest?
    @StateObject private var pdfController = PDFPreviewController()
    @State private var templatePendingDeletion: String?
    private let textFilterReference: [TextFilterInfo] = [
        TextFilterInfo(
            name: "center",
            signature: "center(text, width)",
            description: "Centers the provided text within the given width.",
            snippet: "{{{ center(value, 72) }}}"
        ),
        TextFilterInfo(
            name: "wrap",
            signature: "wrap(text, width, leftMargin, rightMargin)",
            description: "Wraps text to the specified width with optional margins.",
            snippet: "{{{ wrap(text, 72, 4, 4) }}}"
        ),
        TextFilterInfo(
            name: "sectionLine",
            signature: "sectionLine(label, width)",
            description: "Builds a decorative section header line.",
            snippet: "{{{ sectionLine(section-labels.summary, 72) }}}"
        ),
        TextFilterInfo(
            name: "join",
            signature: "join(array, separator)",
            description: "Joins array elements into a single string using the separator.",
            snippet: "{{ join(skills, \", \") }}"
        ),
        TextFilterInfo(
            name: "bulletList",
            signature: "bulletList(array, width, indent, bullet, valueKey)",
            description: "Formats an array as bullet points. `valueKey` is optional for dictionary arrays.",
            snippet: "{{{ bulletList(highlights, 72, 2, \"•\") }}}"
        ),
        TextFilterInfo(
            name: "formatDate",
            signature: "formatDate(date, outputFormat, inputFormat)",
            description: "Formats dates (default input patterns include ISO and yyyy-MM).",
            snippet: "{{ formatDate(start, \"MMM yyyy\") }}"
        ),
        TextFilterInfo(
            name: "uppercase",
            signature: "uppercase(text)",
            description: "Uppercases the provided text if present.",
            snippet: "{{ uppercase(section-labels.summary) }}"
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
        withAnimation(.easeInOut(duration: 0.2)) {
            showInspector.toggle()
        }
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showSidebar.toggle()
        }
    }

    private func openApplicantEditor() {
        if let delegate = NSApplication.shared.delegate as? AppDelegate {
            delegate.showApplicantProfileWindow()
        } else {
            NotificationCenter.default.post(name: .showApplicantProfile, object: nil)
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
        HStack(spacing: 0) {
            if showSidebar {
                sidebarContainer()
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading))
            }

            mainContent()
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
        }
        .onChange(of: selectedTemplate) { _, _ in
            handleTemplateSelectionChange()
        }
        .onChange(of: selectedTab) { _, newValue in
            handleTabSelectionChange(newValue)
        }
        .onChange(of: selectedResume?.id) { _, _ in
            if selectedTab == .pdfTemplate {
                generateInitialPreview()
            }
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
        .sheet(isPresented: $showOverlayOptionsSheet) {
            overlayOptionsSheet()
        }
        .alert(
            "Delete Template",
            isPresented: Binding(
                get: { templatePendingDeletion != nil },
                set: { if !$0 { templatePendingDeletion = nil } }
            ),
            presenting: templatePendingDeletion
        ) { template in
            Button("Delete", role: .destructive) {
                deleteTemplate(slug: template)
            }
            Button("Cancel", role: .cancel) {
                templatePendingDeletion = nil
            }
        } message: { template in
            Text("Are you sure you want to delete the '\(templateDisplayName(template))' template? This cannot be undone.")
        }
        .toolbar(id: "templateEditorToolbar") {
            TemplateEditorToolbar(
                showSidebar: $showSidebar,
                showInspector: $showInspector,
                hasUnsavedChanges: hasAnyUnsavedChanges,
                canRevert: currentHasChanges,
                onRefresh: performRefresh,
                onRevert: revertCurrentTab,
                onClose: performClose,
                onToggleInspector: toggleInspectorVisibility,
                onToggleSidebar: toggleSidebar,
                onOpenApplicant: openApplicantEditor
            )
        }
        .toolbarRole(.editor)
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
        VStack(spacing: 0) {
            editorHeader()
            Divider()
            editorContent()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private func editorHeader() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Editor Section", selection: $selectedTab) {
                ForEach(TemplateEditorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .labelsHidden()
            .padding(.trailing, 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func mainContent() -> some View {
        Group {
            if showInspector {
                HSplitView {
                    editorContainer()
                        .frame(minWidth: 520)
                        .layoutPriority(2)
                    previewColumn()
                        .frame(minWidth: 320, idealWidth: 360)
                        .layoutPriority(1)
                }
            } else {
                editorContainer()
                    .frame(minWidth: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    @ViewBuilder
    private func sidebarTemplateRow(for template: String) -> some View {
        HStack(spacing: 10) {
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
        .contentShape(Rectangle())
        .contextMenu {
            Button("Duplicate Template") {
                duplicateTemplate(slug: template)
            }
            Button("Delete Template", role: .destructive) {
                templatePendingDeletion = template
            }
            .disabled(availableTemplates.count <= 1)
        }
    }

    @ViewBuilder
    private func textSnippetPanel() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Text Snippets")
                    .font(.headline)
                ForEach(textFilterReference) { filter in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(filter.name.capitalized)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Button("Insert") {
                                textEditorInsertion = TextEditorInsertionRequest(text: filter.snippet)
                            }
                            .buttonStyle(.borderless)
                        }
                        Text(filter.signature)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(filter.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Divider()
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func sidebarContainer() -> some View {
        templateSidebar()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(sidebarGrip, alignment: .trailing)
    }

    private var sidebarGrip: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor).opacity(0.0001))
            .frame(width: 6)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                let proposed = sidebarWidth + value.translation.width
                sidebarWidth = min(max(proposed, sidebarWidthRange.lowerBound), sidebarWidthRange.upperBound)
            })
            .overlay(
                Rectangle()
                    .fill(Color(NSColor.separatorColor).opacity(0.35))
                    .frame(width: 1),
                alignment: .center
            )
    }

    private func templateSidebar() -> some View {
        VStack(spacing: 0) {
            List(selection: templateSelectionBinding) {
                Section("Templates") {
                    if availableTemplates.isEmpty {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(availableTemplates, id: \.self) { template in
                            sidebarTemplateRow(for: template)
                                .tag(template)
                        }
                    }
                }

                Section {
                    Button {
                        showingAddTemplate = true
                    } label: {
                        Label("New Template", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }

            }
            .listStyle(.sidebar)
            .frame(minWidth: 160)
            .background(Color(NSColor.controlBackgroundColor))
            .padding(.top, 4)

            if selectedTab == .txtTemplate {
                Divider()
                textSnippetPanel()
            }

            Spacer(minLength: 0)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func previewColumn() -> some View {
        VStack(spacing: 0) {
            previewToolbar()
            Divider()
            previewContent()
            Divider()
            previewFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func previewToolbar() -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Preview")
                        .font(.headline)
                    Text(isEditingCurrentTemplate ? "(Live)" : "(Current Resume)")
                        .font(.caption)
                        .foregroundStyle(isEditingCurrentTemplate ? Color.orange : Color.secondary)
                }
                if isGeneratingLivePreview || isGeneratingPreview {
                    ProgressView()
                        .controlSize(.small)
                }
                if selectedTab != .pdfTemplate {
                    Text("Preview always shows the PDF template; other tab edits save automatically.")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 2)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    pdfController.goToPreviousPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!pdfController.canGoToPreviousPage)

                Button {
                    pdfController.goToNextPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!pdfController.canGoToNextPage)

                Divider()
                    .frame(height: 16)

                Button {
                    pdfController.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }

                Button {
                    pdfController.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }

                Button {
                    pdfController.resetZoom()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fit to page")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func previewContent() -> some View {
        if let pdfData = previewPDFData {
            PDFPreviewView(
                pdfData: pdfData,
                overlayDocument: showOverlay ? overlayPDFDocument : nil,
                overlayPageIndex: overlayPageIndex,
                overlayOpacity: overlayOpacity,
                overlayColor: overlayColor.toNSColor(),
                controller: pdfController
            )
            .background(Color(NSColor.textBackgroundColor))
        } else {
            previewUnavailableMessage(
                hasSelectedResume
                    ? "Export the resume in the main window to see PDF output."
                    : "Select a resume in the main window to enable preview."
            )
        }
    }

    private func previewUnavailableMessage(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("PDF preview will appear here")
                .foregroundColor(.secondary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            pdfController.updatePagingState()
        }
    }

    private func previewFooter() -> some View {
        HStack(spacing: 12) {
            Button {
                previewPDF()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTab != .pdfTemplate || isGeneratingPreview || !hasSelectedResume)

            Spacer()

            if overlayPDFDocument != nil {
                HStack(spacing: 8) {
                    Text("Overlay Opacity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $overlayOpacity, in: 0...1)
                        .frame(width: 140)
                }
            }

            Button {
                prepareOverlayOptions()
            } label: {
                Label("Choose Overlay…", systemImage: "square.on.square")
            }
            .buttonStyle(.bordered)
            .disabled(selectedTab != .pdfTemplate || isGeneratingPreview)

            if overlayPDFDocument != nil {
                HStack(spacing: 12) {
                    Toggle("Overlay", isOn: $showOverlay)
                        .toggleStyle(.switch)
                    Slider(value: $overlayOpacity, in: 0...1)
                        .frame(width: 140)
                }
            } else {
                Toggle("Overlay", isOn: $showOverlay)
                    .toggleStyle(.switch)
                    .disabled(true)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func assetsEditor() -> some View {
        TemplateTextEditor(text: $templateContent, insertionRequest: $textEditorInsertion) {
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

    private func handleTemplateSelectionChange() {
        if hasAnyUnsavedChanges {
            pendingTemplateChange = .template
            showingSaveAlert = true
        } else {
            applyPendingTemplateChange()
        }
    }

    private func handleTabSelectionChange(_ newTab: TemplateEditorTab) {
        textEditorInsertion = nil
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
        guard selectedTab == .pdfTemplate else { return }
        isGeneratingPreview = true
        Task { @MainActor in
            await generateLivePreview()
            isGeneratingPreview = false
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

    private func duplicateTemplate(slug: String) {
        guard let source = appEnvironment.templateStore.template(slug: slug) else { return }

        var candidateSlug = slug + "-copy"
        var index = 2
        while availableTemplates.contains(candidateSlug) {
            candidateSlug = slug + "-copy-\(index)"
            index += 1
        }

        let candidateName = source.name + " Copy" + (index > 2 ? " \(index - 1)" : "")

        appEnvironment.templateStore.upsertTemplate(
            slug: candidateSlug,
            name: candidateName,
            htmlContent: source.htmlContent,
            textContent: source.textContent,
            cssContent: source.cssContent,
            isCustom: true
        )

        if let manifest = source.manifestData {
            try? appEnvironment.templateStore.updateManifest(slug: candidateSlug, manifestData: manifest)
        }

        if let seed = appEnvironment.templateSeedStore.seed(forSlug: slug),
           let jsonString = String(data: seed.seedData, encoding: .utf8) {
            appEnvironment.templateSeedStore.upsertSeed(slug: candidateSlug, jsonString: jsonString)
        }

        loadAvailableTemplates()
        selectedTemplate = candidateSlug
        loadTemplate()
        loadManifest()
        loadSeed()
    }

    private func deleteTemplate(slug: String) {
        guard availableTemplates.count > 1 else { return }

        // Remove user overrides from Documents directory if present
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let templateDir = documentsPath
                .appendingPathComponent("Sprung")
                .appendingPathComponent("Templates")
                .appendingPathComponent(slug)
            try? FileManager.default.removeItem(at: templateDir)
        }

        availableTemplates.removeAll { $0 == slug }
        appEnvironment.templateStore.deleteTemplate(slug: slug.lowercased())
        appEnvironment.templateSeedStore.deleteSeed(forSlug: slug.lowercased())

        if selectedTemplate == slug {
            selectedTemplate = availableTemplates.first ?? "archer"
            loadTemplate()
            loadManifest()
            loadSeed()
        }

        templatePendingDeletion = nil
        loadAvailableTemplates()
    }

    private func performRefresh() {
        _ = savePendingChanges()
        if selectedTab == .pdfTemplate {
            previewPDF()
        }
    }

private func performClose() {
    guard savePendingChanges() else { return }
    closeEditor()
}

// MARK: - Toolbar Support

private struct TemplateEditorToolbar: CustomizableToolbarContent {
    @Binding var showSidebar: Bool
    @Binding var showInspector: Bool
    var hasUnsavedChanges: Bool
    var canRevert: Bool
    var onRefresh: () -> Void
    var onRevert: () -> Void
    var onClose: () -> Void
    var onToggleInspector: () -> Void
    var onToggleSidebar: () -> Void
    var onOpenApplicant: () -> Void

    var body: some CustomizableToolbarContent {
        Group {
            navigationGroup
            actionGroup
            inspectorGroup
            applicantGroup
            statusGroup
            closeGroup
        }
    }

    private var navigationGroup: some CustomizableToolbarContent {
        ToolbarItem(id: "toggleSidebar", placement: .navigation, showsByDefault: true) {
            Button(action: onToggleSidebar) {
                Label("Sidebar", systemImage: showSidebar ? "sidebar.leading" : "sidebar.leading")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(showSidebar ? Color.accentColor : Color.secondary)
            }
            .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")
        }
    }

    private var inspectorGroup: some CustomizableToolbarContent {
        ToolbarItem(id: "toggleInspector", placement: .automatic, showsByDefault: true) {
            Button(action: onToggleInspector) {
                Label("Preview", systemImage: showInspector ? "sidebar.trailing" : "sidebar.trailing")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(showInspector ? Color.accentColor : Color.secondary)
            }
            .help(showInspector ? "Hide Preview" : "Show Preview")
        }
    }

    private var applicantGroup: some CustomizableToolbarContent {
        ToolbarItem(id: "applicantProfile", placement: .automatic, showsByDefault: true) {
            Button(action: onOpenApplicant) {
                Label("Applicant Profile", systemImage: "person.crop.square")
            }
            .help("Open Applicant Profile Editor")
        }
    }

    private var actionGroup: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "refresh", placement: .primaryAction, showsByDefault: true) {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Save changes and regenerate preview")
            }

            ToolbarItem(id: "revert", placement: .primaryAction, showsByDefault: true) {
                Button(action: onRevert) {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canRevert)
                .help("Discard local edits for the active tab")
            }
        }
    }

    private var closeGroup: some CustomizableToolbarContent {
        ToolbarItem(id: "close", placement: .cancellationAction, showsByDefault: true) {
            Button(action: onClose) {
                Label("Close", systemImage: "xmark.circle")
            }
            .help("Save changes and close editor")
        }
    }

    private var statusGroup: some CustomizableToolbarContent {
        ToolbarItem(id: "unsavedStatus", placement: .status, showsByDefault: true) {
            if hasUnsavedChanges {
                Label("Unsaved", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
            }
        }
    }
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
    
    private func prepareOverlayOptions() {
        overlayColorSelection = overlayColor
        overlayPageSelection = overlayPageIndex
        pendingOverlayDocument = overlayPDFDocument
        overlayPageCount = overlayPDFDocument?.pageCount ?? 0
        showOverlayOptionsSheet = true
    }

    private func overlayOptionsSheet() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Overlay Options")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text(overlayFilename ?? "No overlay selected")
                    .font(.subheadline)
                HStack {
                    Button("Choose…") {
                        showingOverlayPicker = true
                    }
                    if overlayPDFDocument != nil {
                        Button("Clear", role: .destructive) {
                            clearOverlaySelection()
                        }
                    }
                }
            }

            if overlayPageCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Overlay Page")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Stepper(value: $overlayPageSelection, in: 0...max(overlayPageCount - 1, 0)) {
                        Text("Page \(overlayPageSelection + 1) of \(overlayPageCount)")
                    }
                }
            }

            ColorPicker("Overlay Color", selection: $overlayColorSelection, supportsOpacity: true)

            Spacer()

            HStack {
                Button("Cancel", role: .cancel) {
                    showOverlayOptionsSheet = false
                }
                Spacer()
                Button("Save") {
                    applyOverlaySelection()
                }
                .disabled(pendingOverlayDocument == nil && overlayPDFDocument == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
        .onDisappear {
            pendingOverlayDocument = nil
        }
    }

    private func applyOverlaySelection() {
        if let pending = pendingOverlayDocument {
            overlayPDFDocument = pending
            let maxIndex = max(pending.pageCount - 1, 0)
            let clampedIndex = min(max(overlayPageSelection, 0), maxIndex)
            overlayPageIndex = clampedIndex
            overlayPageCount = pending.pageCount
            overlayFilename = pending.documentURL?.lastPathComponent ?? overlayFilename
            showOverlay = true
        } else if overlayPDFDocument != nil {
            let maxIndex = max((overlayPDFDocument?.pageCount ?? 1) - 1, 0)
            overlayPageIndex = min(max(overlayPageSelection, 0), maxIndex)
        }

        overlayColor = overlayColorSelection
        showOverlayOptionsSheet = false
    }

    private func clearOverlaySelection() {
        overlayPDFDocument = nil
        pendingOverlayDocument = nil
        overlayPageCount = 0
        overlayFilename = nil
        overlayPageSelection = 0
        overlayPageIndex = 0
        showOverlay = false
    }

    private func loadOverlayPDF(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            saveError = "Failed to access overlay PDF"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let document = PDFDocument(url: url) else {
            saveError = "Failed to read overlay PDF"
            return
        }

        pendingOverlayDocument = document
        overlayPageCount = document.pageCount
        overlayPageSelection = min(overlayPageSelection, max(document.pageCount - 1, 0))
        overlayFilename = url.lastPathComponent
    }
}
