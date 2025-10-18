//
//  TemplateEditorSidebarView.swift
//  Sprung
//

import SwiftUI

struct TemplateEditorSidebarView: View {
    let availableTemplates: [String]
    let selection: Binding<String?>
    let selectedTab: TemplateEditorTab
    let templateDisplayName: (String) -> String
    let templateIconName: (String) -> String
    let templateMatchesCurrentResume: (String) -> Bool
    let templateIsDefault: (String) -> Bool
    let onMakeDefault: (String) -> Void
    let onDuplicateTemplate: (String) -> Void
    let onRequestDeleteTemplate: (String) -> Void
    let onRenameTemplate: (String, String) -> Void
    @Binding var showingAddTemplate: Bool
    @Binding var textEditorInsertion: TextEditorInsertionRequest?
    @Binding var renamingTemplate: String?
    @Binding var tempTemplateName: String
    let textFilters: [TextFilterInfo]
    
    @FocusState private var isRenamingFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            templateList()
            if selectedTab == .txtTemplate {
                Divider()
                textSnippetPanel()
            }
            Spacer(minLength: 0)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func templateList() -> some View {
        List(selection: selection) {
            Section("Templates") {
                if availableTemplates.isEmpty {
                    VStack(spacing: 8) {
                        Text("No templates available")
                            .foregroundColor(.secondary)
                        Text("Use 'New Template' to add one.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(availableTemplates, id: \.self) { template in
                        templateRow(template)
                            .tag(template)
                            .onTapGesture {
                                selection.wrappedValue = template
                            }
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
        .frame(minWidth: 140)
        .background(Color(NSColor.controlBackgroundColor))
        .padding(.top, 4)
    }

    @ViewBuilder
    private func templateRow(_ template: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: templateIconName(template))
                .foregroundColor(templateMatchesCurrentResume(template) ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                if renamingTemplate == template {
                    // Show text field for renaming
                    TextField("Template name", text: $tempTemplateName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            finishRenaming()
                        }
                        .onKeyPress(.escape) {
                            cancelRenaming()
                            return .handled
                        }
                        .focused($isRenamingFocused)
                        .onAppear {
                            isRenamingFocused = true
                        }
                } else {
                    Text(templateDisplayName(template))
                        .onTapGesture(count: 2) {
                            startRenaming(template)
                        }
                }
                
                if templateMatchesCurrentResume(template) {
                    Text("Current resume")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if templateIsDefault(template) {
                    Label("Default", systemImage: "star.fill")
                        .font(.caption2)
                        .labelStyle(.titleAndIcon)
                        .foregroundColor(.yellow)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            startRenaming(template)
        }
        .contextMenu {
            Button("Rename Template") {
                startRenaming(template)
            }
            Button("Duplicate Template") {
                onDuplicateTemplate(template)
            }
            Button("Make Default") {
                onMakeDefault(template)
            }
            .disabled(templateIsDefault(template))
            Button("Delete Template", role: .destructive) {
                onRequestDeleteTemplate(template)
            }
            .disabled(availableTemplates.count <= 1)
        }
    }
    
    private func startRenaming(_ template: String) {
        renamingTemplate = template
        tempTemplateName = templateDisplayName(template)
    }
    
    private func finishRenaming() {
        guard let template = renamingTemplate else { return }
        let trimmedName = tempTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmedName.isEmpty && trimmedName != templateDisplayName(template) {
            onRenameTemplate(template, trimmedName)
        }
        
        renamingTemplate = nil
        tempTemplateName = ""
        isRenamingFocused = false
    }
    
    private func cancelRenaming() {
        renamingTemplate = nil
        tempTemplateName = ""
        isRenamingFocused = false
    }

    @ViewBuilder
    private func textSnippetPanel() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Text Snippets")
                    .font(.headline)
                ForEach(textFilters) { filter in
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
}
