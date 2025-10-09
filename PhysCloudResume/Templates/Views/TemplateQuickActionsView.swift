//
//  TemplateQuickActionsView.swift
//  PhysCloudResume
//
//  Created by Codex Agent on 10/27/25.
//

import Foundation
import SwiftUI

@MainActor
struct TemplateQuickActionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var statusMessage: String?
    @State private var statusKind: StatusKind = .info
    @State private var isProcessing: Bool = false

    private enum StatusKind {
        case info
        case success
        case error

        var tint: Color {
            switch self {
            case .info:
                return .secondary
            case .success:
                return .green
            case .error:
                return .red
            }
        }
    }

    private var selectedResume: Resume? {
        appState.selectedResume
    }

    private var selectedTemplate: Template? {
        selectedResume?.template
    }

    private var currentSeed: TemplateSeed? {
        guard let template = selectedTemplate else { return nil }
        return appEnvironment.templateSeedStore.seed(for: template)
    }

    private var templateSummary: String {
        guard let template = selectedTemplate else {
            return "Select a resume to see its template details and quick actions."
        }

        let slug = template.slug.isEmpty ? template.name : template.slug
        return "Current template: \(template.name) (\(slug))"
    }

    private var seedSummary: String {
        guard let template = selectedTemplate else {
            return "Seed defaults load from template manifests until you promote a resume."
        }

        if let seed = currentSeed {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let relative = formatter.localizedString(for: seed.updatedAt, relativeTo: .now)
            return "Seed saved \(relative)."
        } else {
            return "No seed saved yet for \(template.name). Promote a resume to capture curated defaults."
        }
    }

    private var canPromote: Bool {
        selectedResume?.template != nil && !isProcessing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Template Management")
                    .font(.headline)
                Spacer()
            }

            Text("Manifests and seed data now live in the Template Editor. Promote refined resumes to refresh default content before creating new ones.")
                .font(.callout)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(templateSummary)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(seedSummary)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("Open Template Editor") {
                    openTemplateEditor()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    promoteSelectedResumeToSeed()
                } label: {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Promote Selected Resume to Seed")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!canPromote)
                .help("Capture the current resume tree as the default seed for this template.")
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundColor(statusKind.tint)
                    .transition(.opacity)
            }
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
        NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
        setStatus("Template Editor opened.", kind: .info)
    }

    @MainActor
    private func promoteSelectedResumeToSeed() {
        guard !isProcessing else { return }
        guard let resume = selectedResume else {
            setStatus("Select a resume to promote.", kind: .error)
            return
        }
        guard let template = resume.template else {
            setStatus("The selected resume is missing a template link.", kind: .error)
            return
        }

        isProcessing = true
        setStatus(nil, kind: .info)

        Task { @MainActor in
            defer { isProcessing = false }

            do {
                let context = try ResumeTemplateDataBuilder.buildContext(from: resume)
                guard let formatted = prettyJSONString(from: context) else {
                    setStatus("Unable to serialize resume context.", kind: .error)
                    return
                }

                appEnvironment.templateSeedStore.upsertSeed(
                    slug: template.slug,
                    jsonString: formatted,
                    attachTo: template
                )
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                setStatus("Seed saved for \(template.name) at \(formatter.string(from: .now)).", kind: .success)
            } catch {
                setStatus("Failed to build seed data: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    private func prettyJSONString(from object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func setStatus(_ message: String?, kind: StatusKind) {
        statusMessage = message
        statusKind = kind
    }
}
