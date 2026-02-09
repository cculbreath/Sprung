//
//  ResumeBannerView.swift
//  Sprung
//
//  Banner with resume selector and action buttons.
//

import SwiftUI

struct ResumeBannerView: View {
    @Environment(ResStore.self) private var resStore

    @Bindable var jobApp: JobApp

    @State private var showCreateResumeSheet = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 6) {
            Text("\(jobApp.companyName): \(jobApp.jobPosition)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            createResumeButton
            resumePicker
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            // Base layer: match window/toolbar background so macOS 26
            // icon-only toolbar mode doesn't show a mismatched color
            Color(.windowBackgroundColor)
        }
        .background {
            // Visual layer: the actual banner tint
            Color(red: 222/255, green: 226/255, blue: 228/255)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 205/255, green: 205/255, blue: 206/255))
                .frame(height: 1)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 205/255, green: 205/255, blue: 206/255))
                .frame(height: 1)
        }
    }

    // MARK: - Components

    private var resumePicker: some View {
        HStack(spacing: 6) {
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

            if jobApp.selectedRes != nil {
                Button {
                    if let resume = jobApp.selectedRes {
                        let dup = resStore.duplicate(resume)
                        if let dup { jobApp.selectedRes = dup }
                    }
                } label: {
                    Image(systemName: "document.on.document")
                }
                .buttonStyle(.borderless)
                .help("Duplicate resume")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete resume")
                .alert("Delete Resume?", isPresented: $showDeleteConfirmation) {
                    Button("Delete", role: .destructive) {
                        guard let resume = jobApp.selectedRes else { return }
                        // Update selection and remove from array immediately so the
                        // selectedRes getter fallback doesn't return the deleted resume
                        let nextResume = jobApp.resumes.first(where: { $0.id != resume.id })
                        jobApp.selectedRes = nextResume
                        if let index = jobApp.resumes.firstIndex(of: resume) {
                            jobApp.resumes.remove(at: index)
                        }
                        // Defer model deletion to let SwiftUI update first
                        DispatchQueue.main.async {
                            resStore.deleteRes(resume)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This resume will be permanently deleted.")
                }
            }
        }
    }

    private var createResumeButton: some View {
        Button {
            showCreateResumeSheet = true
        } label: {
            Image("custom.resume.new")
        }
        .buttonStyle(.borderless)
        .help("Create resume")
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
