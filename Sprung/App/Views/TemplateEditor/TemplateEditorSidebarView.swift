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
    let onDuplicateTemplate: (String) -> Void
    let onRequestDeleteTemplate: (String) -> Void
    @Binding var showingAddTemplate: Bool
    @Binding var textEditorInsertion: TextEditorInsertionRequest?
    let textFilters: [TextFilterInfo]

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
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(availableTemplates, id: \.self) { template in
                        templateRow(template)
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
    }

    @ViewBuilder
    private func templateRow(_ template: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: templateIconName(template))
                .foregroundColor(templateMatchesCurrentResume(template) ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(templateDisplayName(template))
                if templateMatchesCurrentResume(template) {
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
                onDuplicateTemplate(template)
            }
            Button("Delete Template", role: .destructive) {
                onRequestDeleteTemplate(template)
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

