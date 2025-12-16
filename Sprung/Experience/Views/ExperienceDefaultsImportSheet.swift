import SwiftData
import SwiftUI

struct ExperienceDefaultsImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: \Resume.dateCreated, order: .reverse) private var resumes: [Resume]

    let currentDraft: ExperienceDefaultsDraft
    let onImport: (ExperienceDefaultsDraft) -> Void

    @State private var selectedResumeId: UUID?
    @State private var isMerging = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var selectedResume: Resume? {
        guard let selectedResumeId else { return nil }
        return resumes.first(where: { $0.id == selectedResumeId })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            bodyContent
            Divider()
            footer
        }
        .frame(width: 760, height: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Import From Resume")
                .font(.title2.weight(.semibold))
            Text("Pull values from an existing resume back into Experience Defaults to seed future resumes.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var bodyContent: some View {
        HStack(spacing: 0) {
            resumeList
            Divider()
            optionsPane
        }
    }

    private var resumeList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a resume:")
                .font(.headline)
                .padding(.top, 16)
                .padding(.horizontal, 16)

            if resumes.isEmpty {
                VStack(spacing: 10) {
                    Text("No resumes found.")
                        .foregroundStyle(.secondary)
                    Text("Create a resume first, then come back to import.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedResumeId) {
                    ForEach(resumes, id: \.id) { resume in
                        ResumeRow(resume: resume)
                            .tag(resume.id as UUID?)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 360)
    }

    private var optionsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Mode")
                .font(.headline)
                .padding(.top, 16)

            Toggle("Merge into existing defaults", isOn: $isMerging)
                .help("When enabled, imported values are appended to your current defaults instead of replacing them.")

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What gets imported")
                        .font(.subheadline.weight(.semibold))
                    Text("Sections (work, education, projects, etc.), summary, and any custom fields defined in the resume.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let selectedResume {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected Resume")
                            .font(.subheadline.weight(.semibold))
                        Text(selectedResume.template?.name ?? "Untitled Template")
                            .font(.callout)
                        Text(selectedResume.dateCreated.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)

            Spacer()

            Button {
                Task { await performImport() }
            } label: {
                Label(isImporting ? "Importing…" : "Import", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting || selectedResume == nil)
        }
        .padding(16)
    }

    @MainActor
    private func performImport() async {
        guard let selectedResume else { return }
        isImporting = true
        errorMessage = nil

        do {
            let profile = appEnvironment.applicantProfileStore.currentProfile()
            let imported = try ExperienceDefaultsImportService.importDraft(from: selectedResume, profile: profile)
            let result = isMerging ? ExperienceDefaultsImportService.merged(current: currentDraft, imported: imported) : imported
            onImport(result)
            dismiss()
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }

        isImporting = false
    }
}

private struct ResumeRow: View {
    let resume: Resume

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(resume.template?.name ?? "Resume")
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(resume.dateCreated.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

