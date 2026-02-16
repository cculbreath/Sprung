//
//  ResumeExportView.swift
//  Sprung
//
//
import PDFKit
import SwiftUI

// MARK: - Export Option Model

enum ExportOption: String, CaseIterable, Identifiable {
    case resumePDF = "Resume PDF"
    case resumeText = "Resume Text"
    case resumeJSON = "Resume JSON"
    case coverLetterPDF = "Cover Letter PDF"
    case coverLetterText = "Cover Letter Text"
    case allCoverLetters = "All Cover Letters"
    case completeApplication = "Complete Application"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .resumePDF: return "doc.richtext"
        case .resumeText: return "doc.plaintext"
        case .resumeJSON: return "curlybraces"
        case .coverLetterPDF: return "doc.richtext.fill"
        case .coverLetterText: return "doc.plaintext.fill"
        case .allCoverLetters: return "doc.on.doc"
        case .completeApplication: return "doc.zipper"
        }
    }

    var key: String {
        switch self {
        case .resumePDF: return "resumePDF"
        case .resumeText: return "resumeText"
        case .resumeJSON: return "resumeJSON"
        case .coverLetterPDF: return "coverLetterPDF"
        case .coverLetterText: return "coverLetterText"
        case .allCoverLetters: return "allCoverLetters"
        case .completeApplication: return "completeApplication"
        }
    }

    static func fromKey(_ key: String) -> ExportOption? {
        allCases.first { $0.key == key }
    }
}

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
            }
            .onChange(of: jobApp.status) { _, newStatus in
                selectedStatus = newStatus
            }
            .onReceive(NotificationCenter.default.publisher(for: .triggerExport)) { notification in
                if let key = notification.userInfo?["option"] as? String,
                   let option = ExportOption.fromKey(key) {
                    performExport(option)
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
                    exportApplicationPacket()
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
                    performExport(selectedExportOption)
                }
                .buttonStyle(.bordered)
                .disabled(isExportDisabled(selectedExportOption, for: jobApp))
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

    private func performExport(_ option: ExportOption) {
        switch option {
        case .resumePDF: exportResumePDF()
        case .resumeText: exportResumeText()
        case .resumeJSON: exportResumeJSON()
        case .coverLetterPDF: exportCoverLetterPDF()
        case .coverLetterText: exportCoverLetterText()
        case .allCoverLetters: exportAllCoverLetters()
        case .completeApplication: exportApplicationPacket()
        }
    }

    private func isExportDisabled(_ option: ExportOption, for jobApp: JobApp) -> Bool {
        switch option {
        case .resumePDF, .resumeText, .resumeJSON:
            return jobApp.selectedRes == nil
        case .coverLetterPDF, .coverLetterText:
            return jobApp.selectedCover == nil
        case .allCoverLetters:
            return jobApp.coverLetters.filter { $0.generated }.isEmpty
        case .completeApplication:
            return jobApp.selectedRes == nil || jobApp.selectedCover == nil
        }
    }

    // MARK: - Toast

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

    // MARK: - File Utilities

    private func sanitizeFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }

    private func createUniqueFileURL(baseFileName: String, extension: String, in directory: URL) -> (URL, String) {
        let sanitizedBaseName = sanitizeFilename(baseFileName)
        var fullFileName = "\(sanitizedBaseName).\(`extension`)"
        var fileURL = directory.appendingPathComponent(fullFileName)
        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fullFileName = "\(sanitizedBaseName)_\(counter).\(`extension`)"
            fileURL = directory.appendingPathComponent(fullFileName)
            counter += 1
        }
        return (fileURL, fullFileName)
    }

    private func combinePDFs(pdfDataArray: [Data]) -> Data? {
        guard !pdfDataArray.isEmpty else { return nil }
        if pdfDataArray.count == 1 {
            return pdfDataArray[0]
        }
        let combinedPDF = PDFDocument()
        for pdfData in pdfDataArray {
            if let pdfDoc = PDFDocument(data: pdfData) {
                for i in 0 ..< pdfDoc.pageCount {
                    if let page = pdfDoc.page(at: i) {
                        combinedPDF.insert(page, at: combinedPDF.pageCount)
                    }
                }
            }
        }
        var expectedPages = 0
        for pdfData in pdfDataArray {
            if let doc = PDFDocument(data: pdfData) {
                expectedPages += doc.pageCount
            }
        }
        if combinedPDF.pageCount != expectedPages {
            Logger.debug("Warning: Expected \(expectedPages) pages but got \(combinedPDF.pageCount)")
        }
        return combinedPDF.dataRepresentation()
    }

    // MARK: - Export Methods

    private func exportResumePDF() {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes
        else {
            showToastNotification("No resume selected. Please select a resume first.")
            return
        }
        showToastNotification("Generating fresh PDF...")
        appEnvironment.resumeExportCoordinator.debounceExport(
            resume: resume,
            onStart: {},
            onFinish: { [self] in
                DispatchQueue.main.async {
                    self.performPDFExport(for: resume)
                }
            }
        )
    }

    private func performPDFExport(for resume: Resume) {
        guard let pdfData = resume.pdfData else {
            showToastNotification("Failed to generate PDF data. Please try again.")
            return
        }
        let jobPosition = resume.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: "\(jobPosition) Resume",
            extension: "pdf",
            in: downloadsURL
        )
        do {
            try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true, attributes: nil)
            try pdfData.write(to: fileURL)
            showToastNotification("Resume PDF has been exported to \"\(filename)\"")
        } catch {
            showToastNotification("Failed to export PDF: \(error.localizedDescription)")
        }
    }

    private func exportResumeText() {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes
        else {
            showToastNotification("No resume selected. Please select a resume first.")
            return
        }
        showToastNotification("Generating fresh text resume...")
        appEnvironment.resumeExportCoordinator.debounceExport(
            resume: resume,
            onStart: {},
            onFinish: { [self] in
                let jobPosition = resume.jobApp?.jobPosition ?? "unknown"
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
                let (fileURL, filename) = createUniqueFileURL(
                    baseFileName: "\(jobPosition) Resume",
                    extension: "txt",
                    in: downloadsURL
                )
                do {
                    try resume.textResume.write(to: fileURL, atomically: true, encoding: .utf8)
                    showToastNotification("Resume text has been exported to \"\(filename)\"")
                } catch {
                    showToastNotification("Failed to export text: \(error.localizedDescription)")
                }
            }
        )
    }

    private func exportResumeJSON() {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes
        else {
            showToastNotification("No resume selected. Please select a resume first.")
            return
        }
        let jobPosition = resume.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: "\(jobPosition) Resume",
            extension: "json",
            in: downloadsURL
        )
        let jsonString = resume.jsonTxt
        do {
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
            showToastNotification("Resume JSON has been exported to \"\(filename)\"")
        } catch {
            showToastNotification("Failed to export JSON: \(error.localizedDescription)")
        }
    }

    private func exportCoverLetterText() {
        guard let jobApp = jobAppStore.selectedApp,
              let coverLetter = jobApp.selectedCover
        else {
            showToastNotification("No cover letter selected. Please select a cover letter first.")
            return
        }
        let jobPosition = coverLetter.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: "\(jobPosition) Cover Letter",
            extension: "txt",
            in: downloadsURL
        )
        do {
            try coverLetter.content.write(to: fileURL, atomically: true, encoding: .utf8)
            showToastNotification("Cover letter has been exported to \"\(filename)\"")
        } catch {
            showToastNotification("Failed to export: \(error.localizedDescription)")
        }
    }

    private func exportCoverLetterPDF() {
        guard let jobApp = jobAppStore.selectedApp,
              let coverLetter = jobApp.selectedCover
        else {
            showToastNotification("No cover letter selected. Please select a cover letter first.")
            return
        }
        let jobPosition = coverLetter.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: "\(jobPosition) Cover Letter",
            extension: "pdf",
            in: downloadsURL
        )
        let pdfData = coverLetterStore.exportPDF(from: coverLetter)
        do {
            try pdfData.write(to: fileURL)
            showToastNotification("Cover letter PDF has been exported to \"\(filename)\"")
        } catch {
            showToastNotification("Failed to export PDF: \(error.localizedDescription)")
        }
    }

    private func exportApplicationPacket() {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes,
              let resumePdfData = resume.pdfData
        else {
            showToastNotification("No resume selected. Please select a resume first.")
            return
        }
        guard let coverLetter = jobApp.selectedCover else {
            showToastNotification("No cover letter selected. Please select a cover letter first.")
            return
        }
        let jobPosition = coverLetter.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: "\(jobPosition) Application",
            extension: "pdf",
            in: downloadsURL
        )
        let coverLetterPdfData = coverLetterStore.exportPDF(from: coverLetter)
        if let combinedPdfData = combinePDFs(pdfDataArray: [coverLetterPdfData, resumePdfData]) {
            do {
                try combinedPdfData.write(to: fileURL)
                showToastNotification("Application packet has been exported to \"\(filename)\"")
            } catch {
                showToastNotification("Failed to export application packet: \(error.localizedDescription)")
            }
        } else {
            showToastNotification("Failed to combine PDFs for application packet.")
        }
    }

    private func exportAllCoverLetters() {
        guard let jobApp = jobAppStore.selectedApp else {
            return
        }
        let allCoverLetters = jobApp.coverLetters.filter { $0.generated }.sorted(by: { $0.moddedDate > $1.moddedDate })
        if allCoverLetters.isEmpty {
            showToastNotification("No cover letters available to export for this job application.")
            return
        }
        let jobPosition = jobApp.jobPosition
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (textFileURL, textFilename) = createUniqueFileURL(
            baseFileName: "\(jobPosition) All Cover Letters",
            extension: "txt",
            in: downloadsURL
        )
        let combinedText = createCombinedCoverLettersText(jobApp: jobApp, coverLetters: allCoverLetters)
        do {
            try combinedText.write(to: textFileURL, atomically: true, encoding: .utf8)
            showToastNotification("All cover letter options have been exported to \"\(textFilename)\"")
        } catch {
            showToastNotification("Failed to export: \(error.localizedDescription)")
        }
    }

    private func createCombinedCoverLettersText(jobApp: JobApp, coverLetters: [CoverLetter]) -> String {
        var combinedText = "ALL COVER LETTER OPTIONS FOR \(jobApp.jobPosition.uppercased()) AT \(jobApp.companyName.uppercased())\n\n"
        let letterLabels = Array("abcdefghijklmnopqrstuvwxyz")
        for (index, letter) in coverLetters.enumerated() {
            let optionLabel = index < letterLabels.count ? String(letterLabels[index]) : "\(index + 1)"
            combinedText += "=============================================\n"
            combinedText += "OPTION \(optionLabel): (\(letter.name))\n"
            combinedText += "=============================================\n\n"
            combinedText += letter.content
            combinedText += "\n\n\n"
        }
        return combinedText
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

// MARK: - Readiness Card

private struct ReadinessCard: View {
    let icon: String
    let title: String
    let isReady: Bool
    let subtitle: String
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isReady ? .green : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                        if isReady {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.8 : 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Pipeline Tracker

private struct PipelineTrackerView: View {
    let currentStatus: Statuses
    let dates: [Statuses: Date]
    let onStatusTap: (Statuses) -> Void

    private let mainPipeline: [Statuses] = [
        .new, .queued, .inProgress, .submitted, .interview, .offer, .accepted
    ]

    private var currentIndex: Int {
        mainPipeline.firstIndex(of: currentStatus) ?? -1
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(mainPipeline.enumerated()), id: \.element) { index, status in
                    pipelineNode(status: status, index: index)

                    if index < mainPipeline.count - 1 {
                        connector(afterIndex: index)
                    }
                }
            }

            if currentStatus == .rejected || currentStatus == .withdrawn {
                HStack(spacing: 12) {
                    Spacer()
                    terminalNode(status: .rejected)
                    terminalNode(status: .withdrawn)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func pipelineNode(status: Statuses, index: Int) -> some View {
        let isPast = currentIndex >= 0 && index < currentIndex
        let isCurrent = status == currentStatus
        let isFuture = !isPast && !isCurrent

        return Button {
            onStatusTap(status)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? status.color : isPast ? status.color.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.3))
                        .frame(width: 28, height: 28)
                    Image(systemName: status.icon)
                        .font(.system(size: 11))
                        .foregroundColor(isCurrent ? .white : isPast ? status.color : Color.secondary.opacity(0.5))
                }
                Text(status.displayName)
                    .font(.system(size: 9, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? .primary : isFuture ? Color.secondary.opacity(0.5) : .secondary)
                    .lineLimit(1)
                    .fixedSize()
                if let date = dates[status] {
                    Text(Self.shortDate.string(from: date))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func connector(afterIndex index: Int) -> some View {
        let isPast = currentIndex >= 0 && index < currentIndex
        return Rectangle()
            .fill(isPast ? Color.secondary.opacity(0.4) : Color(nsColor: .separatorColor).opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, dates.isEmpty ? 16 : 28)
    }

    private func terminalNode(status: Statuses) -> some View {
        let isCurrent = status == currentStatus
        return Button {
            onStatusTap(status)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.caption)
                    .foregroundStyle(isCurrent ? status.color : .secondary)
                Text(status.displayName)
                    .font(.caption)
                    .foregroundStyle(isCurrent ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isCurrent ? status.color.opacity(0.15) : Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isCurrent ? status.color.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toast Overlay

struct MacOSToastOverlay: View {
    let showToast: Bool
    let message: String
    var body: some View {
        ZStack {
            if showToast {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.subheadline)
                        Text(message)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, 8)
                .zIndex(1)
                .animation(.easeInOut(duration: 0.3), value: showToast)
            }
        }
    }
}
