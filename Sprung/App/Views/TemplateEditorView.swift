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

extension Color {
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

enum PendingTemplateChange {
    case template
}

struct TemplateEditorView: View {
    @Environment(NavigationStateService.self) var navigationState
    @Environment(AppEnvironment.self) var appEnvironment

    @State var selectedTemplate: String = "archer"
    @State var selectedTab: TemplateEditorTab = .pdfTemplate
    @State var templateContent: String = ""
    @State var assetHasChanges: Bool = false
    @State var showingSaveAlert: Bool = false
    @State var saveError: String?
    @State var isGeneratingPreview: Bool = false
    @State var showingAddTemplate: Bool = false
    @State var newTemplateName: String = ""
    @State var manifestContent: String = ""
    @State var manifestHasChanges: Bool = false
    @State var manifestValidationMessage: String?
    @State var seedContent: String = ""
    @State var seedHasChanges: Bool = false
    @State var seedValidationMessage: String?
    @State var pendingTemplateChange: PendingTemplateChange?

    // Live preview state
    @State var previewPDFData: Data?
    @State var previewTextContent: String?
    @State var htmlDraft: String?
    @State var textDraft: String?
    @State var isPreviewRefreshing: Bool = false
    @State var showInspector: Bool = true
    @State var debounceTimer: Timer?
    @State var isGeneratingLivePreview: Bool = false

    // Overlay state
    @State var showOverlay: Bool = false
    @State var overlayPDFDocument: PDFDocument?
    @State var overlayPageIndex: Int = 0
    @State var overlayOpacity: Double = 0.75
    @State var showingOverlayPicker: Bool = false
    @State var overlayColor: Color = Color.blue.opacity(0.85)
    @State var overlayColorSelection: Color = Color.blue.opacity(0.85)
    @State var showOverlayOptionsSheet: Bool = false
    @State var pendingOverlayDocument: PDFDocument?
    @State var overlayPageCount: Int = 0
    @State var overlayFilename: String?
    @State var overlayPageSelection: Int = 0

    @State var availableTemplates: [String] = []

    @State var showSidebar: Bool = true
    @State var sidebarWidth: CGFloat = 150
    private let sidebarWidthRange: ClosedRange<CGFloat> = 140...300
    @State private var textEditorInsertion: TextEditorInsertionRequest?
    @StateObject private var pdfController = PDFPreviewController()
    @State var templatePendingDeletion: String?
    @State var showRevertConfirmation: Bool = false
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
    
    var selectedResume: Resume? {
        navigationState.selectedResume
    }

    func templateDisplayName(_ template: String) -> String {
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

    private func handleTemplateDraftUpdate(with content: String) {
        switch selectedTab {
        case .pdfTemplate:
            htmlDraft = content
        case .txtTemplate:
            textDraft = content
        default:
            break
        }
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
    

    var currentFormat: String {
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
            refreshTemplatePreview(force: true)
        }
        .onChange(of: selectedTemplate) { _, _ in
            handleTemplateSelectionChange()
        }
        .onChange(of: selectedTab) { _, newValue in
            handleTabSelectionChange(newValue)
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
            TemplateEditorOverlayOptionsView(
                overlayFilename: overlayFilename,
                overlayPageCount: overlayPageCount,
                overlayPageSelection: $overlayPageSelection,
                overlayColorSelection: $overlayColorSelection,
                canClearOverlay: overlayPDFDocument != nil,
                canSaveOverlay: pendingOverlayDocument != nil || overlayPDFDocument != nil,
                onChooseOverlay: { showingOverlayPicker = true },
                onClearOverlay: clearOverlaySelection,
                onCancel: { showOverlayOptionsSheet = false },
                onSave: applyOverlaySelection,
                onDismiss: { pendingOverlayDocument = nil }
            )
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
        .alert("Revert All Changes?", isPresented: $showRevertConfirmation) {
            Button("Revert", role: .destructive) {
                revertAllChanges()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Reloads the template, manifest, and default values from the last saved state.")
        }
        .toolbar(id: "templateEditorToolbar") {
            TemplateEditorToolbar(
                showSidebar: $showSidebar,
                showInspector: $showInspector,
                hasUnsavedChanges: hasAnyUnsavedChanges,
                canRevert: hasAnyUnsavedChanges,
                onRefresh: performRefresh,
                onRevert: { showRevertConfirmation = true },
                onClose: performClose,
                onToggleInspector: toggleInspectorVisibility,
                onToggleSidebar: toggleSidebar,
                onOpenApplicant: openApplicantEditor
            )
        }
        .toolbarRole(.editor)
    }

    @ViewBuilder
    private func mainContent() -> some View {
        Group {
            if showInspector {
                HSplitView {
                    TemplateEditorEditorColumn(
                        selectedTab: $selectedTab,
                        templateContent: $templateContent,
                        manifestContent: $manifestContent,
                        seedContent: $seedContent,
                        assetHasChanges: $assetHasChanges,
                        manifestHasChanges: $manifestHasChanges,
                        seedHasChanges: $seedHasChanges,
                        manifestValidationMessage: $manifestValidationMessage,
                        seedValidationMessage: $seedValidationMessage,
                        textEditorInsertion: $textEditorInsertion,
                        selectedResume: selectedResume,
                        onTemplateChange: { updatedContent in
                            handleTemplateDraftUpdate(with: updatedContent)
                        },
                        onValidateManifest: validateManifest,
                        onSaveManifest: { _ = saveManifest() },
                        onReloadManifest: loadManifest,
                        onPromoteSeed: promoteCurrentResumeToSeed,
                        onSaveSeed: { _ = saveSeed() }
                    )
                        .frame(minWidth: 300)
                        .layoutPriority(2)
                    TemplateEditorPreviewColumn(
                        previewPDFData: previewPDFData,
                        textPreview: previewTextContent,
                        showOverlay: $showOverlay,
                        overlayDocument: overlayPDFDocument,
                        overlayPageIndex: overlayPageIndex,
                        overlayOpacity: $overlayOpacity,
                        overlayColor: overlayColor,
                        isGeneratingPreview: isGeneratingPreview,
                        isGeneratingLivePreview: isGeneratingLivePreview,
                        selectedTab: selectedTab,
                        pdfController: pdfController,
                        onRefresh: { refreshTemplatePreview(force: true) },
                        onPrepareOverlayOptions: prepareOverlayOptions
                    )
                    .frame(minWidth: 540, idealWidth: 600)
                    .layoutPriority(1)
                }
            } else {
                TemplateEditorEditorColumn(
                    selectedTab: $selectedTab,
                    templateContent: $templateContent,
                    manifestContent: $manifestContent,
                    seedContent: $seedContent,
                    assetHasChanges: $assetHasChanges,
                    manifestHasChanges: $manifestHasChanges,
                    seedHasChanges: $seedHasChanges,
                    manifestValidationMessage: $manifestValidationMessage,
                    seedValidationMessage: $seedValidationMessage,
                    textEditorInsertion: $textEditorInsertion,
                    selectedResume: selectedResume,
                    onTemplateChange: { updatedContent in
                        handleTemplateDraftUpdate(with: updatedContent)
                    },
                    onValidateManifest: validateManifest,
                    onSaveManifest: { _ = saveManifest() },
                    onReloadManifest: loadManifest,
                    onPromoteSeed: promoteCurrentResumeToSeed,
                    onSaveSeed: { _ = saveSeed() }
                )
                    .frame(minWidth: 300)
                TemplateEditorPreviewColumn(
                    previewPDFData: previewPDFData,
                    textPreview: previewTextContent,
                    showOverlay: $showOverlay,
                    overlayDocument: overlayPDFDocument,
                    overlayPageIndex: overlayPageIndex,
                    overlayOpacity: $overlayOpacity,
                    overlayColor: overlayColor,
                    isGeneratingPreview: isGeneratingPreview,
                    isGeneratingLivePreview: isGeneratingLivePreview,
                    selectedTab: selectedTab,
                    pdfController: pdfController,
                    onRefresh: { refreshTemplatePreview(force: true) },
                    onPrepareOverlayOptions: prepareOverlayOptions
                )
                .frame(minWidth: 540, idealWidth: 600)
                .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    @ViewBuilder
    private func sidebarContainer() -> some View {
        TemplateEditorSidebarView(
            availableTemplates: availableTemplates,
            selection: templateSelectionBinding,
            selectedTab: selectedTab,
            templateDisplayName: templateDisplayName(_:),
            templateIconName: { templateIconName(for: $0) },
            templateMatchesCurrentResume: { templateMatchesSelectedResume($0) },
            onDuplicateTemplate: { slug in duplicateTemplate(slug: slug) },
            onRequestDeleteTemplate: { slug in templatePendingDeletion = slug },
            showingAddTemplate: $showingAddTemplate,
            textEditorInsertion: $textEditorInsertion,
            textFilters: textFilterReference
        )
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
            .onHover { hovering in
#if os(macOS)
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
#endif
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
    func savePendingChanges() -> Bool {
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

    private func revertAllChanges() {
        discardPendingChanges()
        loadTemplate()
        loadManifest()
        loadSeed()
        showOverlay = false
        overlayPDFDocument = nil
        overlayFilename = nil
        overlayPageCount = 0
        refreshTemplatePreview(force: true)
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
                refreshTemplatePreview(force: false)
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
        if selectedTab == .pdfTemplate || selectedTab == .txtTemplate {
            refreshTemplatePreview(force: false)
        }
    }

}
