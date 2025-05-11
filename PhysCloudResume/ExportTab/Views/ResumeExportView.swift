//
//  ResumeExportView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/16/24.
//

import PDFKit
import SwiftUI

struct ResumeExportView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore

    // Local state for controlling the status picker
    @State private var selectedStatus: Statuses = .new

    // Local state for notes text
    @State private var notes: String = ""

    // State for toast notification
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @State private var toastTimer: Timer? = nil

    // Application review sheet control

    var body: some View {
        // Only show if we actually have a selected JobApp in the store
        if let jobApp = jobAppStore.selectedApp {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Resume Section

                // Add a GroupBox to show the current resume and cover letter
                GroupBox(label: Text("Export Documents").fontWeight(.medium)) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Job information
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Position:")
                                    .fontWeight(.semibold)
                                    .frame(width: 80, alignment: .leading)
                                Text(jobApp.jobPosition)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Company:")
                                    .fontWeight(.semibold)
                                    .frame(width: 80, alignment: .leading)
                                Text(jobApp.companyName)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        // Documents being exported
                        HStack(alignment: .top, spacing: 16) {
                            // Resume information
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Resume:")
                                    .fontWeight(.semibold)
                                if let resume = jobApp.selectedRes {
                                    Text("Created at \(resume.createdDateString)")
                                        .foregroundColor(.secondary)
                                        .font(.callout)
                                } else {
                                    Text("None selected")
                                        .foregroundColor(.secondary)
                                        .font(.callout)
                                        .italic()
                                }
                            }

                            Spacer()

                            // Cover Letter information if available
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cover Letter:")
                                    .fontWeight(.semibold)
                                if let coverLetter = jobApp.selectedCover {
                                    Text(coverLetter.sequencedName)
                                        .foregroundColor(.secondary)
                                        .font(.callout)
                                } else {
                                    Text("None selected")
                                        .foregroundColor(.secondary)
                                        .font(.callout)
                                        .italic()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Resume export buttons
                GroupBox(label: Text("Resume Export").fontWeight(.medium)) {
                    HStack(spacing: 15) {
                        Button("Export PDF") {
                            exportResumePDF()
                        }
                        .disabled(jobApp.selectedRes == nil)

                        Button("Export Text") {
                            exportResumeText()
                        }
                        .disabled(jobApp.selectedRes == nil)

                        Button("Export JSON") {
                            exportResumeJSON()
                        }
                        .disabled(jobApp.selectedRes == nil)
                    }
                    .padding(.vertical, 4)
                }

                // Cover letter export buttons
                GroupBox(label: Text("Cover Letter Export").fontWeight(.medium)) {
                    HStack(spacing: 15) {
                        Button("Export PDF") {
                            exportCoverLetterPDF()
                        }
                        .disabled(jobApp.selectedCover == nil)

                        Button("Export Text") {
                            exportCoverLetterText()
                        }
                        .disabled(jobApp.selectedCover == nil)

                        Button("Export All Cover Letters") {
                            exportAllCoverLetters()
                        }
                        .disabled(jobApp.coverLetters.isEmpty)
                    }
                    .padding(.vertical, 4)
                }

                // Application packet export button
                GroupBox(label: Text("Application Packet").fontWeight(.medium)) {
                    Button("Export Complete Application (Resume + Cover Letter)") {
                        exportApplicationPacket()
                    }
                    .disabled(jobApp.selectedRes == nil || jobApp.selectedCover == nil)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
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
                        let updated = jobApp
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
            }
            .overlay(
                // Toast notification overlay
                ZStack {
                    if showToast {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(toastMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(NSColor.windowBackgroundColor))
                                    .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .zIndex(1)
                        .animation(.easeInOut, value: showToast)
                    }
                }
            )
        } else {
            // If there's no selected jobApp
            EmptyView()
        }
    }

    // MARK: - Toolbar

    private func showToastNotification(_ message: String) {
        // Cancel any existing timer
        toastTimer?.invalidate()

        // Update toast message and show it
        toastMessage = message

        withAnimation {
            showToast = true
        }

        // Schedule timer to hide toast after 3 seconds
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

    /// Creates a unique file URL for the given base filename by appending an incrementing number if the file already exists
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

    /// Joins multiple PDF documents together into a single PDF with multiple pages
    private func combinePDFs(pdfDataArray: [Data]) -> Data? {
        guard !pdfDataArray.isEmpty else { return nil }

        // If only one PDF, return it as-is
        if pdfDataArray.count == 1 {
            return pdfDataArray[0]
        }

        // Create a new empty PDF document
        let combinedPDF = PDFDocument()

        // Process each PDF document and maintain its pages
        for pdfData in pdfDataArray {
            if let pdfDoc = PDFDocument(data: pdfData) {
                // Process each page in the current document
                for i in 0 ..< pdfDoc.pageCount {
                    if let page = pdfDoc.page(at: i) {
                        // Add each page to the combined document preserving page boundaries
                        combinedPDF.insert(page, at: combinedPDF.pageCount)
                    }
                }
            }
        }

        // Verify we have the expected number of pages
        var expectedPages = 0
        for pdfData in pdfDataArray {
            if let doc = PDFDocument(data: pdfData) {
                expectedPages += doc.pageCount
            }
        }

        if combinedPDF.pageCount != expectedPages {
            print("Warning: Expected \(expectedPages) pages but got \(combinedPDF.pageCount)")
        }

        // Return the combined document as data
        return combinedPDF.dataRepresentation()
    }

    // MARK: - Export Methods

    private func exportResumePDF() {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes,
              let pdfData = resume.pdfData
        else {
            showToastNotification("No resume selected. Please select a resume first.")
            return
        }

        let jobPosition = resume.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        // Create unique filename using the job position: e.g. "Software Engineer Resume.pdf"
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

        let jobPosition = resume.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        // Create unique filename using the job position: e.g. "Software Engineer Resume.txt"
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: "\(jobPosition) Resume",
            extension: "txt",
            in: downloadsURL
        )

        do {
            try resume.textRes.write(to: fileURL, atomically: true, encoding: .utf8)
            showToastNotification("Resume text has been exported to \"\(filename)\"")
        } catch {
            showToastNotification("Failed to export text: \(error.localizedDescription)")
        }
    }

    private func exportResumeJSON() {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes
        else {
            showToastNotification("No resume selected. Please select a resume first.")
            return
        }

        let jobPosition = resume.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        // Create unique filename using the job position: e.g. "Software Engineer Resume.json"
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
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        // Create unique filename using the job position: e.g. "Software Engineer Cover Letter.txt"
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
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        // Create unique filename using the job position: e.g. "Software Engineer Cover Letter.pdf"
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
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        // Create unique filename using the job position: e.g. "Software Engineer Application.pdf"
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: "\(jobPosition) Application",
            extension: "pdf",
            in: downloadsURL
        )

        // Get cover letter PDF data
        let coverLetterPdfData = coverLetterStore.exportPDF(from: coverLetter)

        // Combine PDFs - cover letter first, then resume
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

        // Get all cover letters for this job app
        let allCoverLetters = jobApp.coverLetters.filter { $0.generated }.sorted(by: { $0.moddedDate > $1.moddedDate })

        if allCoverLetters.isEmpty {
            showToastNotification("No cover letters available to export for this job application.")
            return
        }

        let jobPosition = jobApp.jobPosition
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        // Create unique filename using the job position: e.g. "Software Engineer All Cover Letters.txt"
        let (textFileURL, textFilename) = createUniqueFileURL(
            baseFileName: "\(jobPosition) All Cover Letters",
            extension: "txt",
            in: downloadsURL
        )

        // Create and export combined text file
        let combinedText = createCombinedCoverLettersText(jobApp: jobApp, coverLetters: allCoverLetters)

        do {
            // Export text file
            try combinedText.write(to: textFileURL, atomically: true, encoding: .utf8)
            showToastNotification("All cover letter options have been exported to \"\(textFilename)\"")
        } catch {
            showToastNotification("Failed to export: \(error.localizedDescription)")
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
