//
//  TemplateEditorEditorColumn.swift
//  Sprung
//

import SwiftUI

struct TemplateEditorEditorColumn: View {
    @Binding var selectedTab: TemplateEditorTab
    @Binding var templateContent: String
    @Binding var manifestContent: String
    @Binding var seedContent: String
    @Binding var assetHasChanges: Bool
    @Binding var manifestHasChanges: Bool
    @Binding var seedHasChanges: Bool
    @Binding var manifestValidationMessage: String?
    @Binding var seedValidationMessage: String?
    @Binding var textEditorInsertion: TextEditorInsertionRequest?
    let selectedResume: Resume?
    let onTemplateChange: (String) -> Void
    let onValidateManifest: () -> Void
    let onSaveManifest: () -> Void
    let onReloadManifest: () -> Void
    let onPromoteSeed: () -> Void
    let onSaveSeed: () -> Void

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
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func editorContent() -> some View {
        switch selectedTab {
        case .pdfTemplate, .txtTemplate:
            TemplateTextEditor(text: $templateContent, insertionRequest: $textEditorInsertion) {
                assetHasChanges = true
                onTemplateChange(templateContent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .manifest:
            manifestEditor()
        case .seed:
            seedEditor()
        }
    }

    @ViewBuilder
    private func manifestEditor() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Validate", action: onValidateManifest)
                    .buttonStyle(.bordered)
                Button("Save") {
                    onSaveManifest()
                }
                .disabled(!manifestHasChanges)
                .buttonStyle(.borderedProminent)
                Button("Reload", action: onReloadManifest)
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
                Button("Promote Current Resume", action: onPromoteSeed)
                    .disabled(selectedResume == nil)
                    .buttonStyle(.bordered)
                Button("Save") {
                    onSaveSeed()
                }
                .disabled(!seedHasChanges)
                .buttonStyle(.borderedProminent)
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
}
