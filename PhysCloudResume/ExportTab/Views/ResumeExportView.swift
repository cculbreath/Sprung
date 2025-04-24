import SwiftUI

struct ResumeExportView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore

    // Local state for picking a resume or cover letter
    @State private var selectedResume: Resume?
    @State private var selectedCoverLetter: CoverLetter?

    // Local state for controlling the status picker
    @State private var selectedStatus: Statuses = .new

    // Local state for notes text
    @State private var notes: String = ""

    // State for showing export success notification
    @State private var showExportAlert: Bool = false
    @State private var exportAlertMessage: String = ""

    var body: some View {
        // Only show if we actually have a selected JobApp in the store
        if let jobApp = jobAppStore.selectedApp {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Resume Section

                Text("Resume")
                    .font(.headline)
                    .padding(.top)

                Picker("Select a Resume", selection: $selectedResume) {
                    Text("None").tag(nil as Resume?)
                    ForEach(
                        jobApp.resumes.sorted(by: { $0.createdDateString > $1.createdDateString }),
                        id: \.self
                    ) { resume in
                        Text("Created at \(resume.createdDateString)")
                            .tag(resume as Resume?)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 15) {
                    Button("Export PDF") {
                        exportResumePDF()
                    }
                    Button("Export Text") {
                        exportResumeText()
                    }
                    Button("Export JSON") {
                        exportResumeJSON()
                    }
                }

                Divider()

                // MARK: - Cover Letter Section

                Text("Cover Letter")
                    .font(.headline)

                CoverLetterPicker(
                    coverLetters: jobApp.coverLetters.sorted(by: { $0.moddedDate > $1.moddedDate }),
                    selection: $selectedCoverLetter,
                    includeNoneOption: true,
                    noneLabel: "None",
                    label: "Select a Cover Letter"
                )
                .pickerStyle(.menu)

                HStack(spacing: 15) {
                    Button("Export PDF") {
                        exportCoverLetterPDF()
                    }

                    Button("Export Text") {
                        exportCoverLetterText()
                    }

                    Button("Export All Cover Letters") {
                        exportAllCoverLetters()
                    }
                }

                Divider()

                // MARK: - Status Section

                Text("Application Status")
                    .font(.headline)

                Picker("", selection: $selectedStatus) {
                    ForEach(Statuses.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedStatus) { _, newStatus in
                    // Call store method instead of mutating jobApp directly
                    jobAppStore.updateJobAppStatus(jobApp, to: newStatus)
                }

                // MARK: - Notes

                Text("Notes")
                    .font(.headline)
                TextEditor(text: $notes)
                    .onChange(of: notes) { _, newValue in
                        // Build an updated copy of jobApp, then call store method
                        var updated = jobApp
                        updated.notes = newValue
                        jobAppStore.updateJobApp(updated)
                    }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            .onAppear {
                // Sync local state from the store's selectedApp
                selectedStatus = jobApp.status
                notes = jobApp.notes
                // Optionally, restore selectedResume/selectedCoverLetter if desired
                // selectedResume = ...
                // selectedCoverLetter = ...
            }
            .alert(isPresented: $showExportAlert) {
                Alert(
                    title: Text("Export Complete"),
                    message: Text(exportAlertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        } else {
            // If there's no selected jobApp
            EmptyView()
        }
    }

    // MARK: - Export Methods

    private func sanitizeFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }

    private func exportResumePDF() {
        guard let resume = selectedResume, let pdfData = resume.pdfData else {
            return
        }
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(sanitizeFilename("\(resume.jobApp?.jobPosition ?? "unknown").pdf"))

        do {
            try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true, attributes: nil)
            try pdfData.write(to: fileURL)
        } catch {
        }
    }

    private func exportResumeText() {
        guard let resume = selectedResume else {
            return
        }
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(
            sanitizeFilename("\(resume.jobApp?.jobPosition ?? "unknown").txt")
        )

        do {
            try resume.textRes.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
        }
    }

    private func exportResumeJSON() {
        guard let resume = selectedResume else {
            return
        }
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(sanitizeFilename("\(resume.jobApp?.jobPosition ?? "unknown").json"))

        let jsonString = resume.jsonTxt
        do {
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
        }
    }

    private func exportCoverLetterText() {
        guard let coverLetter = selectedCoverLetter else {
            exportAlertMessage = "No cover letter selected. Please select a cover letter first."
            showExportAlert = true
            return
        }
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let filename = sanitizeFilename("\(coverLetter.jobApp?.jobPosition ?? "")_CoverLetter.txt")
        let fileURL = downloadsURL.appendingPathComponent(filename)

        do {
            try coverLetter.content.write(to: fileURL, atomically: true, encoding: .utf8)
            exportAlertMessage = "Cover letter has been exported to \"\(filename)\""
            showExportAlert = true
        } catch {
            exportAlertMessage = "Failed to export: \(error.localizedDescription)"
            showExportAlert = true
        }
    }

    private func exportCoverLetterPDF() {
        guard let coverLetter = selectedCoverLetter else {
            exportAlertMessage = "No cover letter selected. Please select a cover letter first."
            showExportAlert = true
            return
        }

        let pdfData = coverLetterStore.exportPDF(from: coverLetter)
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let filename = sanitizeFilename("\(coverLetter.jobApp?.jobPosition ?? "")_CoverLetter.pdf")
        let fileURL = downloadsURL.appendingPathComponent(filename)

        do {
            try pdfData.write(to: fileURL)
            exportAlertMessage = "Cover letter PDF has been exported to \"\(filename)\""
            showExportAlert = true
        } catch {
            exportAlertMessage = "Failed to export PDF: \(error.localizedDescription)"
            showExportAlert = true
        }
    }

    private func exportAllCoverLetters() {
        guard let jobApp = jobAppStore.selectedApp else {
            return
        }

        // Get all cover letters for this job app
        let allCoverLetters = jobApp.coverLetters.filter { $0.generated }.sorted(by: { $0.moddedDate > $1.moddedDate })

        if allCoverLetters.isEmpty {
            exportAlertMessage = "No cover letters available to export for this job application."
            showExportAlert = true
            return
        }

        // Create and export combined text file
        let combinedText = createCombinedCoverLettersText(jobApp: jobApp, coverLetters: allCoverLetters)
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let textFilename = sanitizeFilename("All cover letter options for \(jobApp.jobPosition) job.txt")
        let textFileURL = downloadsURL.appendingPathComponent(textFilename)

        // Create folder for PDFs
        let folderName = sanitizeFilename("Cover Letters for \(jobApp.jobPosition)")
        let folderURL = downloadsURL.appendingPathComponent(folderName)

        do {
            // Export text file
            try combinedText.write(to: textFileURL, atomically: true, encoding: .utf8)

            // Create folder for PDFs if needed
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)

            // Export individual PDFs
            let letterLabels = Array("abcdefghijklmnopqrstuvwxyz")

            for (index, letter) in allCoverLetters.enumerated() {
                // Determine the option label
                let optionLabel = index < letterLabels.count ? String(letterLabels[index]) : "\(index + 1)"
                let pdfFilename = sanitizeFilename("Option \(optionLabel) - \(jobApp.jobPosition) Cover Letter.pdf")
                let pdfFileURL = folderURL.appendingPathComponent(pdfFilename)

                // Generate and save PDF
                let pdfData = coverLetterStore.exportPDF(from: letter)
                try pdfData.write(to: pdfFileURL)
            }

            // Show success alert
            exportAlertMessage = "\(allCoverLetters.count) cover letter options have been exported as text and PDFs"
            showExportAlert = true
        } catch {
            exportAlertMessage = "Failed to export: \(error.localizedDescription)"
            showExportAlert = true
        }
    }

    private func createCombinedCoverLettersText(jobApp: JobApp, coverLetters: [CoverLetter]) -> String {
        var combinedText = "ALL COVER LETTER OPTIONS FOR \(jobApp.jobPosition.uppercased()) AT \(jobApp.companyName.uppercased())\n\n"

        // Use letters a, b, c, etc. to label options
        let letterLabels = Array("abcdefghijklmnopqrstuvwxyz")

        for (index, letter) in coverLetters.enumerated() {
            // Determine the option label (a, b, c, etc.)
            let optionLabel = index < letterLabels.count ? String(letterLabels[index]) : "\(index + 1)"

            combinedText += "=============================================\n"
            // Use the editable name for each option
            combinedText += "OPTION \(optionLabel): (\(letter.name))\n"
            combinedText += "=============================================\n\n"
            combinedText += letter.content
            combinedText += "\n\n\n"
        }

        return combinedText
    }
}
