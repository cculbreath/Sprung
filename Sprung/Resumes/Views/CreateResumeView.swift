//
//  CreateResumeView.swift
//  Sprung
//
import SwiftUI
import SwiftData
import AppKit
import Foundation
// Helper view for creating a resume
struct CreateResumeView: View {
    @Environment(TemplateStore.self) private var templateStore: TemplateStore
    var onCreateResume: (Template) throws -> Void
    @State private var selectedTemplateID: UUID?
    @State private var createError: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let templates = templateStore.templates()
        VStack(alignment: .leading, spacing: 20) {
            Text("Create Resume")
                .font(.title)
                .fontWeight(.bold)
                .padding(.bottom, 10)
            // Resume Model Selector
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Select Template")
                        .font(.headline)
                    Spacer()
                    Button("Manage Templates…", action: manageTemplates)
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
                Picker("Select Template", selection: $selectedTemplateID) {
                    Text("Select a template").tag(nil as UUID?)
                    ForEach(templates) { template in
                        Text(template.name).tag(template.id as UUID?)
                    }
                }
                .frame(minWidth: 200)
                if templates.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No templates available")
                            .foregroundColor(.secondary)
                        Button("Manage Templates…", action: manageTemplates)
                            .buttonStyle(.borderedProminent)
                    }
                }
                if let templateID = selectedTemplateID,
                   let selectedTemplate = templates.first(where: { $0.id == templateID }) {
                    HStack {
                        Text("Style:")
                            .fontWeight(.semibold)
                        Text(selectedTemplate.name)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.bottom, 10)
            Spacer()
            if let createError {
                Text(createError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(action: {
                    guard
                        let templateID = selectedTemplateID,
                        let selectedTemplate = templates.first(where: { $0.id == templateID })
                    else {
                        Logger.warning(
                            "CreateResumeView: Create tapped without a template selection",
                            category: .ui
                        )
                        return
                    }
                    do {
                        try onCreateResume(selectedTemplate)
                        dismiss()
                    } catch {
                        createError = "Couldn't create resume — \(error.localizedDescription)"
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text("Create Resume")
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedTemplateID == nil)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
        .onAppear {
            // Default model selection
            if selectedTemplateID == nil {
                if let defaultTemplate = templateStore.defaultTemplate() {
                    selectedTemplateID = defaultTemplate.id
                } else if let firstTemplate = templates.first {
                    selectedTemplateID = firstTemplate.id
                }
            }
        }
    }

    /// Dismiss and deep-link to the References module's Templates tab, where
    /// templates are created and edited.
    private func manageTemplates() {
        dismiss()
        NotificationCenter.default.post(
            name: .navigateToModule, object: nil,
            userInfo: ["module": AppModule.references.rawValue]
        )
        NotificationCenter.default.post(
            name: .navigateToReferencesTab, object: nil,
            userInfo: ["tab": "Templates"]
        )
    }
}
