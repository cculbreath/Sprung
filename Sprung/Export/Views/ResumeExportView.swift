//
//  ResumeExportView.swift
//  Sprung
//
//
import SwiftUI

// MARK: - Submit Dashboard

struct ResumeExportView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment

    @Binding var selectedTab: TabList

    @State private var selectedStatus: Statuses = .new
    @State private var notes: String = ""
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @State private var toastTimer: Timer?
    @State private var selectedExportOption: ExportOption = .completeApplication
    @State private var showAdvanceStatusAlert: Bool = false
    @State private var exportService: ExportFileService?

    var body: some View {
        if let jobApp = jobAppStore.selectedApp {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Submit Application")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("\(jobApp.jobPosition) at \(jobApp.companyName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        readinessSection(for: jobApp)
                        pipelineSection(for: jobApp)
                        actionsSection(for: jobApp)
                        exportSection(for: jobApp)
                        notesSection(for: jobApp)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .onAppear {
                selectedStatus = jobApp.status
                notes = jobApp.notes
                exportService = ExportFileService(
                    jobAppStore: jobAppStore,
                    coverLetterStore: coverLetterStore,
                    resumeExportCoordinator: appEnvironment.resumeExportCoordinator
                )
            }
            .onChange(of: jobApp.status) { _, newStatus in
                selectedStatus = newStatus
            }
            .onReceive(NotificationCenter.default.publisher(for: .triggerExport)) { notification in
                if let key = notification.userInfo?["option"] as? String,
                   let option = ExportOption.fromKey(key) {
                    exportService?.performExport(option, onToast: showToastNotification)
                }
            }
            .overlay(MacOSToastOverlay(showToast: showToast, message: toastMessage))
            .alert("Update Status?", isPresented: $showAdvanceStatusAlert) {
                Button("Mark as Submitted") {
                    jobAppStore.updateJobAppStatus(jobApp, to: .submitted)
                    jobApp.appliedDate = Date()
                    jobAppStore.updateJobApp(jobApp)
                }
                Button("Keep Current", role: .cancel) {}
            } message: {
                Text("You opened the application link. Would you like to advance the status to Submitted?")
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Application Readiness

    private func readinessSection(for jobApp: JobApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("APPLICATION READINESS")

            HStack(spacing: 12) {
                ReadinessCard(
                    icon: "doc.text",
                    title: "Resume",
                    isReady: jobApp.selectedRes != nil,
                    subtitle: jobApp.selectedRes.map { "Created \($0.createdDateString)" } ?? "Not selected",
                    onTap: { selectedTab = .resume }
                )
                ReadinessCard(
                    icon: "doc.text.fill",
                    title: "Cover Letter",
                    isReady: jobApp.selectedCover != nil,
                    subtitle: jobApp.selectedCover.map { $0.sequencedName } ?? "Not selected",
                    onTap: { selectedTab = .coverLetter }
                )
            }
        }
    }

    // MARK: - Pipeline Tracker

    private func pipelineSection(for jobApp: JobApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PIPELINE")

            PipelineTrackerView(
                currentStatus: jobApp.status,
                dates: pipelineDates(for: jobApp),
                onStatusTap: { newStatus in
                    jobAppStore.updateJobAppStatus(jobApp, to: newStatus)
                    updateDateForStatus(jobApp: jobApp, status: newStatus)
                }
            )
        }
    }

    private func pipelineDates(for jobApp: JobApp) -> [Statuses: Date] {
        var dates: [Statuses: Date] = [:]
        dates[.new] = jobApp.identifiedDate ?? jobApp.createdAt
        if let applied = jobApp.appliedDate { dates[.submitted] = applied }
        if let interview = jobApp.firstInterviewDate { dates[.interview] = interview }
        if let offer = jobApp.offerDate { dates[.offer] = offer }
        if let closed = jobApp.closedDate {
            if jobApp.status == .accepted { dates[.accepted] = closed }
            if jobApp.status == .rejected { dates[.rejected] = closed }
            if jobApp.status == .withdrawn { dates[.withdrawn] = closed }
        }
        return dates
    }

    private func updateDateForStatus(jobApp: JobApp, status: Statuses) {
        switch status {
        case .submitted:
            if jobApp.appliedDate == nil { jobApp.appliedDate = Date() }
        case .interview:
            if jobApp.firstInterviewDate == nil { jobApp.firstInterviewDate = Date() }
        case .offer:
            if jobApp.offerDate == nil { jobApp.offerDate = Date() }
        case .accepted, .rejected, .withdrawn:
            if jobApp.closedDate == nil { jobApp.closedDate = Date() }
        default: break
        }
        jobAppStore.updateJobApp(jobApp)
    }

    // MARK: - Primary Actions

    private func actionsSection(for jobApp: JobApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ACTIONS")

            HStack(spacing: 8) {
                if let primaryURL = getPrimaryApplyURL(for: jobApp) {
                    Button {
                        if let url = URL(string: primaryURL) {
                            NSWorkspace.shared.open(url)
                        }
                        let preSubmitted: [Statuses] = [.new, .queued, .inProgress]
                        if preSubmitted.contains(jobApp.status) {
                            showAdvanceStatusAlert = true
                        }
                    } label: {
                        Label(
                            !jobApp.jobApplyLink.isEmpty ? "Apply Now" : "View Posting",
                            systemImage: !jobApp.jobApplyLink.isEmpty ? "paperplane.fill" : "safari"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    exportService?.exportApplicationPacket(onToast: showToastNotification)
                } label: {
                    Label("Export Application", systemImage: "doc.zipper")
                }
                .buttonStyle(.bordered)
                .disabled(jobApp.selectedRes == nil || jobApp.selectedCover == nil)

                Spacer()
            }
        }
    }

    // MARK: - Export Options

    private func exportSection(for jobApp: JobApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("EXPORT")

            HStack(spacing: 12) {
                Picker("Format", selection: $selectedExportOption) {
                    ForEach(ExportOption.allCases) { option in
                        Label(option.rawValue, systemImage: option.icon).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Button("Export") {
                    exportService?.performExport(selectedExportOption, onToast: showToastNotification)
                }
                .buttonStyle(.bordered)
                .disabled(exportService?.isExportDisabled(selectedExportOption, for: jobApp) ?? true)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    // MARK: - Notes

    private func notesSection(for jobApp: JobApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("NOTES")

            TextEditor(text: $notes)
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .onChange(of: notes) { _, newValue in
                    let updated = jobApp
                    updated.notes = newValue
                    jobAppStore.updateJobApp(updated)
                }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }

    private func showToastNotification(_ message: String) {
        toastTimer?.invalidate()
        toastMessage = message
        withAnimation {
            showToast = true
        }
        toastTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                self.showToast = false
            }
        }
    }

    private func getPrimaryApplyURL(for jobApp: JobApp) -> String? {
        if !jobApp.jobApplyLink.isEmpty {
            return jobApp.jobApplyLink
        } else if !jobApp.postingURL.isEmpty {
            return jobApp.postingURL
        }
        return nil
    }
}
