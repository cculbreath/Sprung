//
//  TemplateEditorEditorColumn.swift
//  Sprung
//
import SwiftUI
struct TemplateEditorEditorColumn: View {
    @Binding var selectedTab: TemplateEditorTab
    @Binding var htmlContent: String
    @Binding var textContent: String
    @Binding var manifestContent: String
    @Binding var htmlHasChanges: Bool
    @Binding var textHasChanges: Bool
    @Binding var manifestHasChanges: Bool
    @Binding var manifestValidationMessage: String?
    @Binding var customFieldWarningMessage: String?
    @Binding var textEditorInsertion: TextEditorInsertionRequest?
    let selectedResume: Resume?
    let onTemplateChange: (TemplateEditorTab, String) -> Void
    let hasUnsavedChanges: Bool
    let onSaveAndRefresh: () -> Void
    let onValidateManifest: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            header()
            Divider()
            editorContent()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    @ViewBuilder
    private func header() -> some View {
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
            controlsRow()
            if selectedTab == .txtTemplate, let warning = customFieldWarningMessage {
                warningBanner(text: warning)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }
    @ViewBuilder
    private func editorContent() -> some View {
        switch selectedTab {
        case .pdfTemplate:
            TemplateTextEditor(text: $htmlContent, insertionRequest: $textEditorInsertion) {
                htmlHasChanges = true
                onTemplateChange(.pdfTemplate, htmlContent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .txtTemplate:
            TemplateTextEditor(text: $textContent, insertionRequest: $textEditorInsertion) {
                textHasChanges = true
                onTemplateChange(.txtTemplate, textContent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .manifest:
            manifestEditor()
        }
    }
    private func saveButton() -> some View {
        TemplateRefreshButton(
            hasUnsavedChanges: hasUnsavedChanges,
            isAnimating: false,
            isEnabled: hasUnsavedChanges,
            help: "Save all changes and refresh previews",
            action: onSaveAndRefresh
        )
    }
    private func validateManifestButton() -> some View {
        Button(action: onValidateManifest) {
            Image(systemName: "questionmark.diamond")
        }
        .buttonStyle(.borderless)
        .help("Validate manifest JSON")
    }
    @ViewBuilder
    private func controlsRow() -> some View {
        HStack(spacing: 12) {
            switch selectedTab {
            case .pdfTemplate:
                saveButton()
            case .txtTemplate:
                saveButton()
            case .manifest:
                validateManifestButton()
                saveButton()
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
    @ViewBuilder
    private func manifestEditor() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = manifestValidationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding([.top, .horizontal])
            }
            TemplateTextEditor(text: $manifestContent) {
                manifestHasChanges = true
                manifestValidationMessage = nil
            }
            .frame(
                minWidth: 300,
                idealWidth: 600,
                maxWidth: .infinity,
                minHeight: 400,
                maxHeight: .infinity
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func warningBanner(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(text)
                .font(.footnote)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}
