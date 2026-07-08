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
        HStack(spacing: 10) {
            Text("\(jobApp.companyName): \(jobApp.jobPosition)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 16)
            createResumeButton
            resumePicker
        }
        .controlSize(.small)
        .padding(.leading, 14)
        .padding(.trailing, 20)
        .padding(.vertical, 9)
        .background {
            Color(nsColor: .controlBackgroundColor).opacity(0.85)
        }
        .background {
            Color(red: 190/255, green: 194/255, blue: 198/255)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 170/255, green: 172/255, blue: 175/255))
                .frame(height: 1)
        }
    }

    // MARK: - Components

    private var resumePicker: some View {
        HStack(spacing: 8) {
            Picker("", selection: $jobApp.selectedRes) {
                if jobApp.resumes.isEmpty {
                    Text("None").tag(Resume?.none)
                }
                ForEach(sortedResumes) { resume in
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
                onCreateResume: { template in
                    try resStore.create(
                        jobApp: jobApp,
                        template: template
                    )
                }
            )
            .padding()
        }
    }

    // MARK: - Helpers

    /// `JobApp.resumes` is an unordered SwiftData to-many, so picker order is not
    /// a persisted contract — sort explicitly by creation time (oldest first, so
    /// versions read chronologically).
    private var sortedResumes: [Resume] {
        jobApp.resumes.sorted { $0.dateCreated < $1.dateCreated }
    }

    /// Prefer the resume's provenance label (e.g. "Aleo — AI revised"), stamped
    /// at each creation site, so tailored versions are distinguishable at a
    /// glance. Records created before labels existed fall back to the old
    /// template-plus-timestamp string.
    private func resumeLabel(for resume: Resume) -> String {
        if !resume.label.isEmpty {
            return resume.label
        }
        let templateName = resume.template?.name ?? "No template"
        return "\(templateName) – \(resume.createdDateString)"
    }
}
