//
//  TemplateQuickActionsView.swift
//  Sprung
//
import AppKit
import Foundation
import SwiftUI
@MainActor
struct TemplateQuickActionsView: View {
    @Environment(NavigationStateService.self) private var navigationState
    private var selectedResume: Resume? {
        navigationState.selectedResume
    }
    private var selectedTemplate: Template? {
        selectedResume?.template
    }
    private var templateSummary: String {
        guard let template = selectedTemplate else {
            return "Select a resume to see its template details."
        }
        let slug = template.slug.isEmpty ? template.name : template.slug
        return "Current template: \(template.name) (\(slug))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Template Management")
                    .font(.headline)
                Spacer()
            }
            Text("Edit template manifests and HTML/CSS in the Template Editor.")
                .font(.callout)
                .foregroundColor(.secondary)
            Text(templateSummary)
                .font(.subheadline)
                .foregroundColor(.primary)
            Button("Open Template Editor") {
                openTemplateEditor()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.windowBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    private func openTemplateEditor() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.showTemplateEditorWindow()
        } else {
            NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
        }
    }
}
