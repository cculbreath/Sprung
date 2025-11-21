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
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    var onCreateResume: (Template, [ResRef]) -> Void

    @State private var selectedTemplateID: UUID?

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
                Text("Select Template")
                    .font(.headline)

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
                        Button("Open Template Editor") {
                            NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
                        }
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
                    onCreateResume(selectedTemplate, resRefStore.resRefs)
                    dismiss()
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
}
