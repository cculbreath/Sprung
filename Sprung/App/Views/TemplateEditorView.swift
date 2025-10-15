//
//  TemplateEditorView.swift
//  Sprung
//
//  Template editor for resume templates
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

struct TemplateEditorView: View {
    @Environment(NavigationStateService.self) var navigationState
    @Environment(AppEnvironment.self) var appEnvironment

    @State var selectedTemplate: String = ""
    @State var selectedTab: TemplateEditorTab = .pdfTemplate
    @State var htmlContent: String = ""
    @State var textContent: String = ""
    @State var htmlHasChanges: Bool = false
    @State var textHasChanges: Bool = false
    @State var isGeneratingPreview: Bool = false
    @State var showingAddTemplate: Bool = false
    @State var newTemplateName: String = ""
    @State var manifestContent: String = ""
    @State var manifestHasChanges: Bool = false
    @State var manifestValidationMessage: String?
    @State var seedContent: String = ""
    @State var seedHasChanges: Bool = false
    @State var seedValidationMessage: String?
    @State var pendingProfileUpdate: ProfileUpdatePrompt?

    // Template renaming state
    @State var renamingTemplate: String?
    @State var tempTemplateName: String = ""
    @State var templateRefreshTrigger: Int = 0  // Force UI refresh

    // Live preview state
    @State var previewPDFData: Data?
    @State var previewTextContent: String?
    @State var htmlDraft: String?
    @State var textDraft: String?
    @State var isPreviewRefreshing: Bool = false
    @State var previewErrorMessage: String?
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
    @State var defaultTemplateSlug: String? = nil

    @State var showSidebar: Bool = true
    @State var sidebarWidth: CGFloat = 150
    private let sidebarWidthRange: ClosedRange<CGFloat> = 140...300
    @State var textEditorInsertion: TextEditorInsertionRequest?
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
        if let record = appEnvironment.templateStore.template(slug: template) {
            return record.name
        }
        return template
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

    private func templateIsDefault(_ template: String) -> Bool {
        guard let defaultTemplateSlug else { return false }
        return defaultTemplateSlug.lowercased() == template.lowercased()
    }

    private func makeTemplateDefault(slug: String) {
        guard let record = appEnvironment.templateStore.template(slug: slug) else { return }
        appEnvironment.templateStore.setDefault(record)
        defaultTemplateSlug = slug
    }

    private func handleTemplateDraftUpdate(for tab: TemplateEditorTab, content: String) {
        switch tab {
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
        Task { @MainActor in
            NotificationCenter.default.post(name: .showApplicantProfile, object: nil)
            if !NSApp.sendAction(#selector(AppDelegate.showApplicantProfileWindow), to: nil, from: nil),
               let delegate = NSApplication.shared.delegate as? AppDelegate {
                delegate.showApplicantProfileWindow()
            }
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
    
    private var hasAnyUnsavedChanges: Bool {
        htmlHasChanges || textHasChanges || manifestHasChanges || seedHasChanges
    }

    private var templateSelectionBinding: Binding<String?> {
        Binding<String?>(
            get: { selectedTemplate.isEmpty ? nil : selectedTemplate },
            set: { newValue in
                selectedTemplate = newValue ?? ""
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebarContainer()
                    .clipped()
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading))
            }

            mainContent()
        }
        .frame(minWidth: 1024, minHeight: 640)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadAvailableTemplates()
            loadTemplateAssets()
            loadManifest()
            loadSeed()
            manifestHasChanges = false
            seedHasChanges = false
            refreshTemplatePreview(force: true)
        }
        .onChange(of: selectedTemplate) { oldValue, _ in
            handleTemplateSelectionChange(previousSlug: oldValue)
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            handleTabSelectionChange(previous: oldValue, newValue: newValue)
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
                Logger.error("TemplateEditor: Failed to load overlay PDF: \(error)")
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
        .alert(
            "Update Applicant Profile?",
            isPresented: Binding(
                get: { pendingProfileUpdate != nil },
                set: { if !$0 { pendingProfileUpdate = nil } }
            ),
            presenting: pendingProfileUpdate
        ) { prompt in
            Button("Update Profile") {
                applyProfileUpdate(prompt)
            }
            Button("Cancel", role: .cancel) {
                pendingProfileUpdate = nil
            }
        } message: { prompt in
            Text(prompt.message)
        }
        .toolbar(id: "templateEditorToolbar") {
            TemplateEditorToolbar(
                showSidebar: $showSidebar,
                hasUnsavedChanges: hasAnyUnsavedChanges,
                onToggleSidebar: toggleSidebar,
                onOpenApplicant: openApplicantEditor,
                onCloseWithoutSaving: {
                    closeWithoutSaving()
                },
                onRevert: { showRevertConfirmation = true },
                onSaveAndClose: saveAndClose
            )
        }
        .toolbarRole(.editor)
    }

    @ViewBuilder
    private func mainContent() -> some View {
        if availableTemplates.isEmpty {
            TemplateEditorEmptyState(showingAddTemplate: $showingAddTemplate)
        } else if selectedTemplate.isEmpty {
            TemplateSelectionState(showingAddTemplate: $showingAddTemplate)
        } else {
            Group {
                if showInspector {
                    HSplitView {
                        editorColumn
                            .frame(minWidth: 300)
                            .layoutPriority(2)
                        previewColumn
                            .frame(minWidth: 540, idealWidth: 600)
                            .layoutPriority(1)
                    }
                } else {
                    editorColumn
                        .frame(minWidth: 300)
                    previewColumn
                        .frame(minWidth: 540, idealWidth: 600)
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    private var editorColumn: some View {
        TemplateEditorEditorColumn(
            selectedTab: $selectedTab,
            htmlContent: $htmlContent,
            textContent: $textContent,
            manifestContent: $manifestContent,
            seedContent: $seedContent,
            htmlHasChanges: $htmlHasChanges,
            textHasChanges: $textHasChanges,
            manifestHasChanges: $manifestHasChanges,
            seedHasChanges: $seedHasChanges,
            manifestValidationMessage: $manifestValidationMessage,
            seedValidationMessage: $seedValidationMessage,
            textEditorInsertion: $textEditorInsertion,
            selectedResume: selectedResume,
            onTemplateChange: { tab, updatedContent in
                handleTemplateDraftUpdate(for: tab, content: updatedContent)
            },
            hasUnsavedChanges: hasAnyUnsavedChanges,
            onSaveAndRefresh: performRefresh,
            onValidateManifest: validateManifest,
            onPromoteSeed: promoteCurrentResumeToSeed,
            onValidateSeed: validateSeedFormat
        )
    }

    private var previewColumn: some View {
        TemplateEditorPreviewColumn(
            previewPDFData: previewPDFData,
            textPreview: previewTextContent,
            previewError: previewErrorMessage,
            showOverlay: $showOverlay,
            overlayDocument: overlayPDFDocument,
            overlayPageIndex: overlayPageIndex,
            overlayOpacity: $overlayOpacity,
            overlayColor: overlayColor,
            isGeneratingPreview: isGeneratingPreview,
            isGeneratingLivePreview: isGeneratingLivePreview,
            selectedTab: selectedTab,
            pdfController: pdfController,
            onForceRefresh: { refreshTemplatePreview(force: true) },
            onSaveAndRefresh: performRefresh,
            hasUnsavedChanges: hasAnyUnsavedChanges,
            onPrepareOverlayOptions: prepareOverlayOptions
        )
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
            templateIsDefault: { templateIsDefault($0) },
            onMakeDefault: { makeTemplateDefault(slug: $0) },
            onDuplicateTemplate: { slug in duplicateTemplate(slug: slug) },
            onRequestDeleteTemplate: { slug in templatePendingDeletion = slug },
            onRenameTemplate: { slug, newName in renameTemplate(slug: slug, newName: newName) },
            showingAddTemplate: $showingAddTemplate,
            textEditorInsertion: $textEditorInsertion,
            renamingTemplate: $renamingTemplate,
            tempTemplateName: $tempTemplateName,
            textFilters: textFilterReference
        )
        .id(templateRefreshTrigger)  // Force refresh when this changes
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

}

private struct TemplateEditorEmptyState: View {
    @Binding var showingAddTemplate: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("No templates found")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Create a template to begin editing resumes.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 360)
            Button("New Template") {
                showingAddTemplate = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TemplateSelectionState: View {
    @Binding var showingAddTemplate: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("Select a template to begin")
                .font(.title3)
                .fontWeight(.medium)
            Text("Choose an existing template from the sidebar or create a new one.")
                .foregroundColor(.secondary)
            Button("New Template") {
                showingAddTemplate = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
