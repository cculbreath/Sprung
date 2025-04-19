import SwiftUI

struct ResumeExportView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    // Local state for picking a resume or cover letter
    @State private var selectedResume: Resume?
    @State private var selectedCoverLetter: CoverLetter?

    // Local state for controlling the status picker
    @State private var selectedStatus: Statuses = .new

    // Local state for notes text
    @State private var notes: String = ""

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

                Picker("Select a Cover Letter", selection: $selectedCoverLetter) {
                    Text("None").tag(nil as CoverLetter?)
                    ForEach(
                        jobApp.coverLetters.sorted(by: { $0.moddedDate > $1.moddedDate }),
                        id: \.id
                    ) { coverLetter in
                        Text("Generated at \(coverLetter.modDate)").tag(coverLetter as CoverLetter?)
                    }
                }
                .pickerStyle(.menu)

                Button("Export Cover Letter Text") {
                    exportCoverLetterText()
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
                // Sync local state from the store’s selectedApp
                selectedStatus = jobApp.status
                notes = jobApp.notes
                // Optionally, restore selectedResume/selectedCoverLetter if desired
                // selectedResume = ...
                // selectedCoverLetter = ...
            }
        } else {
            // If there’s no selected jobApp
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
            print("No PDF data available for this resume")
            return
        }
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(sanitizeFilename("\(resume.jobApp?.jobPosition ?? "unknown").pdf"))

        do {
            try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true, attributes: nil)
            try pdfData.write(to: fileURL)
            print("PDF exported to \(fileURL)")
        } catch {
            print("Failed to export PDF: \(error)")
        }
    }

    private func exportResumeText() {
        guard let resume = selectedResume else {
            print("No resume selected")
            return
        }
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(
            sanitizeFilename("\(resume.jobApp?.jobPosition ?? "unknown").txt")
        )

        do {
            try resume.textRes.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Text file exported to \(fileURL)")
        } catch {
            print("Failed to export resume text: \(error)")
        }
    }

    private func exportResumeJSON() {
        guard let resume = selectedResume else {
            print("No resume selected")
            return
        }
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(sanitizeFilename("\(resume.jobApp?.jobPosition ?? "unknown").json"))

        let jsonString = resume.jsonTxt
        do {
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
            print("JSON file exported to \(fileURL)")
        } catch {
            print("Failed to export resume JSON: \(error)")
        }
    }

    private func exportCoverLetterText() {
        guard let coverLetter = selectedCoverLetter else {
            print("No cover letter selected")
            return
        }
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(sanitizeFilename("\(coverLetter.jobApp?.jobPosition ?? "")_CoverLetter.txt"))

        do {
            try coverLetter.content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Cover letter text file exported to \(fileURL)")
        } catch {
            print("Failed to export cover letter text: \(error)")
        }
    }
}
