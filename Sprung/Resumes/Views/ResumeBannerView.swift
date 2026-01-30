//
//  ResumeBannerView.swift
//  Sprung
//
//  Banner with resume selector, template picker, and Create Resume button.
//

import SwiftUI

struct ResumeBannerView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(ResStore.self) private var resStore

    @Bindable var jobApp: JobApp

    @State private var selectedTemplateId: UUID?
    @State private var showCreateResumeSheet = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            singleLineLayout
            twoLineLayout
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
        .onAppear {
            if selectedTemplateId == nil {
                selectedTemplateId = appEnvironment.templateStore.templates().first?.id
            }
        }
    }

    // MARK: - Layouts

    private var singleLineLayout: some View {
        HStack(spacing: 12) {
            resumePicker
            templatePicker
            createResumeButton
        }
    }

    private var twoLineLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            resumePicker
            HStack(spacing: 12) {
                templatePicker
                createResumeButton
            }
        }
    }

    // MARK: - Components

    private var resumePicker: some View {
        HStack(spacing: 6) {
            Text("Résumé")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Picker("", selection: $jobApp.selectedRes) {
                if jobApp.resumes.isEmpty {
                    Text("None").tag(Resume?.none)
                }
                ForEach(jobApp.resumes) { resume in
                    Text(resumeLabel(for: resume))
                        .tag(Resume?.some(resume))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var templatePicker: some View {
        HStack(spacing: 6) {
            Text("Template")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Picker("", selection: $selectedTemplateId) {
                ForEach(appEnvironment.templateStore.templates()) { template in
                    Text(template.name).tag(Optional(template.id))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var createResumeButton: some View {
        Button("Create Resume") {
            showCreateResumeSheet = true
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $showCreateResumeSheet) {
            CreateResumeView(
                onCreateResume: { template, sources in
                    if resStore.create(
                        jobApp: jobApp,
                        sources: sources,
                        template: template
                    ) != nil {
                        // Selection updates automatically via ResStore
                    }
                }
            )
            .padding()
        }
    }

    // MARK: - Helpers

    private func resumeLabel(for resume: Resume) -> String {
        let templateName = resume.template?.name ?? "No template"
        return "\(templateName) – \(resume.createdDateString)"
    }
}
