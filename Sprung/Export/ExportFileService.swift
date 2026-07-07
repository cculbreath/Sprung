//
//  ExportFileService.swift
//  Sprung
//
//
import Foundation
import PDFKit

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

// MARK: - Submitted Packet Errors

enum SubmittedPacketError: LocalizedError {
    case noResumeSelected
    case renderProducedNoPDF

    var errorDescription: String? {
        switch self {
        case .noResumeSelected:
            return "No resume is selected to record."
        case .renderProducedNoPDF:
            return "The resume render produced no PDF."
        }
    }
}

// MARK: - Export File Service

@MainActor
final class ExportFileService {
    private let jobAppStore: JobAppStore
    private let coverLetterStore: CoverLetterStore
    private let resumeExportCoordinator: ResumeExportCoordinator
    private let applicantProfileStore: ApplicantProfileStore

    init(jobAppStore: JobAppStore,
         coverLetterStore: CoverLetterStore,
         resumeExportCoordinator: ResumeExportCoordinator,
         applicantProfileStore: ApplicantProfileStore) {
        self.jobAppStore = jobAppStore
        self.coverLetterStore = coverLetterStore
        self.resumeExportCoordinator = resumeExportCoordinator
        self.applicantProfileStore = applicantProfileStore
    }

    /// Freeze what's currently selected into a persisted `SubmittedPacket`:
    /// force a FRESH PDF render (never the possibly-stale `resume.pdfData`),
    /// snapshot the resume tree with the revision encoder, and record it via the
    /// store. Throws on render failure so callers surface it instead of
    /// archiving stale bytes (app-audit resume-editor #2 + #5).
    @discardableResult
    func renderAndRecordPacket() async throws -> SubmittedPacket {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            throw SubmittedPacketError.noResumeSelected
        }
        try await resumeExportCoordinator.forceRender(for: resume)
        guard let pdfData = resume.pdfData else {
            throw SubmittedPacketError.renderProducedNoPDF
        }
        let treeSnapshot = resume.rootNode.flatMap { root in
            try? JSONSerialization.data(
                withJSONObject: root.toRevisionDictionary(),
                options: [.prettyPrinted, .sortedKeys]
            )
        }
        let packet = SubmittedPacket(
            jobAppId: jobApp.id,
            submittedDate: Date(),
            resumePdfData: pdfData,
            treeSnapshotData: treeSnapshot,
            coverLetterText: jobApp.selectedCover?.content,
            templateSlug: resume.template?.slug ?? "",
            label: resume.label
        )
        jobAppStore.recordSubmittedPacket(packet)
        return packet
    }

    func performExport(_ option: ExportOption, onToast: @escaping (String) -> Void) {
        switch option {
        case .resumePDF: exportResumePDF(onToast: onToast)
        case .resumeText: exportResumeText(onToast: onToast)
        case .resumeJSON: exportResumeJSON(onToast: onToast)
        case .coverLetterPDF: exportCoverLetterPDF(onToast: onToast)
        case .coverLetterText: exportCoverLetterText(onToast: onToast)
        case .allCoverLetters: exportAllCoverLetters(onToast: onToast)
        case .completeApplication: exportApplicationPacket(onToast: onToast)
        }
    }

    func isExportDisabled(_ option: ExportOption, for jobApp: JobApp) -> Bool {
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

    // MARK: - File Utilities

    private func sanitizeFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }

    /// Builds an export base filename prefixed with the candidate's name so a
    /// recruiter's download folder reads "<Name> - <jobPosition> <suffix>"
    /// instead of just "<jobPosition> <suffix>" (app-audit resume-editor,
    /// below-the-fold: export filenames omit the candidate name).
    private func exportBaseName(_ suffix: String, jobPosition: String) -> String {
        let candidateName = applicantProfileStore.currentProfile().name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidateName.isEmpty else {
            return "\(jobPosition) \(suffix)"
        }
        return "\(candidateName) - \(jobPosition) \(suffix)"
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
            Logger.error("Failed to combine PDFs: expected \(expectedPages) pages but got \(combinedPDF.pageCount)")
            return nil
        }
        return combinedPDF.dataRepresentation()
    }

    // MARK: - Export Methods

    private func exportResumePDF(onToast: @escaping (String) -> Void) {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes
        else {
            onToast("No resume selected. Please select a resume first.")
            return
        }
        onToast("Generating fresh PDF...")
        resumeExportCoordinator.debounceExport(
            resume: resume,
            onStart: {},
            onFinish: { [self] in
                DispatchQueue.main.async {
                    self.performPDFExport(for: resume, onToast: onToast)
                }
            },
            onFailure: { error in
                onToast("Couldn't export resume PDF — the render failed: \(error.localizedDescription)")
            }
        )
    }

    private func performPDFExport(for resume: Resume, onToast: @escaping (String) -> Void) {
        guard let pdfData = resume.pdfData else {
            onToast("Failed to generate PDF data. Please try again.")
            return
        }
        let jobPosition = resume.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: exportBaseName("Resume", jobPosition: jobPosition),
            extension: "pdf",
            in: downloadsURL
        )
        do {
            try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true, attributes: nil)
            try pdfData.write(to: fileURL)
            onToast("Resume PDF has been exported to \"\(filename)\"")
        } catch {
            onToast("Failed to export PDF: \(error.localizedDescription)")
        }
    }

    private func exportResumeText(onToast: @escaping (String) -> Void) {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes
        else {
            onToast("No resume selected. Please select a resume first.")
            return
        }
        onToast("Generating fresh text resume...")
        resumeExportCoordinator.debounceExport(
            resume: resume,
            onStart: {},
            onFinish: { [self] in
                let jobPosition = resume.jobApp?.jobPosition ?? "unknown"
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
                let (fileURL, filename) = self.createUniqueFileURL(
                    baseFileName: self.exportBaseName("Resume", jobPosition: jobPosition),
                    extension: "txt",
                    in: downloadsURL
                )
                do {
                    try resume.textResume.write(to: fileURL, atomically: true, encoding: .utf8)
                    onToast("Resume text has been exported to \"\(filename)\"")
                } catch {
                    onToast("Failed to export text: \(error.localizedDescription)")
                }
            },
            onFailure: { error in
                onToast("Couldn't export resume text — the render failed: \(error.localizedDescription)")
            }
        )
    }

    private func exportResumeJSON(onToast: @escaping (String) -> Void) {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes
        else {
            onToast("No resume selected. Please select a resume first.")
            return
        }
        let jobPosition = resume.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: exportBaseName("Resume", jobPosition: jobPosition),
            extension: "json",
            in: downloadsURL
        )
        let jsonString: String
        do {
            jsonString = try resume.buildJSON()
        } catch {
            Logger.error("Failed to build resume JSON for export: \(error)")
            onToast("Couldn't export resume JSON — \(error.localizedDescription)")
            return
        }
        do {
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
            onToast("Resume JSON has been exported to \"\(filename)\"")
        } catch {
            onToast("Failed to export JSON: \(error.localizedDescription)")
        }
    }

    private func exportCoverLetterText(onToast: @escaping (String) -> Void) {
        guard let jobApp = jobAppStore.selectedApp,
              let coverLetter = jobApp.selectedCover
        else {
            onToast("No cover letter selected. Please select a cover letter first.")
            return
        }
        let jobPosition = coverLetter.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: exportBaseName("Cover Letter", jobPosition: jobPosition),
            extension: "txt",
            in: downloadsURL
        )
        do {
            try coverLetter.content.write(to: fileURL, atomically: true, encoding: .utf8)
            onToast("Cover letter has been exported to \"\(filename)\"")
        } catch {
            onToast("Failed to export: \(error.localizedDescription)")
        }
    }

    private func exportCoverLetterPDF(onToast: @escaping (String) -> Void) {
        guard let jobApp = jobAppStore.selectedApp,
              let coverLetter = jobApp.selectedCover
        else {
            onToast("No cover letter selected. Please select a cover letter first.")
            return
        }
        let jobPosition = coverLetter.jobApp?.jobPosition ?? "unknown"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (fileURL, filename) = createUniqueFileURL(
            baseFileName: exportBaseName("Cover Letter", jobPosition: jobPosition),
            extension: "pdf",
            in: downloadsURL
        )
        let pdfData = coverLetterStore.exportPDF(from: coverLetter)
        do {
            try pdfData.write(to: fileURL)
            onToast("Cover letter PDF has been exported to \"\(filename)\"")
        } catch {
            onToast("Failed to export PDF: \(error.localizedDescription)")
        }
    }

    func exportApplicationPacket(onToast: @escaping (String) -> Void) {
        guard let jobApp = jobAppStore.selectedApp,
              jobApp.selectedRes != nil
        else {
            onToast("No resume selected. Please select a resume first.")
            return
        }
        guard let coverLetter = jobApp.selectedCover else {
            onToast("No cover letter selected. Please select a cover letter first.")
            return
        }
        onToast("Generating fresh application packet...")
        Task { @MainActor in
            // Fresh render + freeze the submitted packet from the freshly
            // rendered bytes (never the possibly-stale resume.pdfData).
            let packet: SubmittedPacket
            do {
                packet = try await self.renderAndRecordPacket()
            } catch {
                onToast("Couldn't export the application packet — the render failed: \(error.localizedDescription)")
                return
            }
            let jobPosition = coverLetter.jobApp?.jobPosition ?? "unknown"
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let (fileURL, filename) = self.createUniqueFileURL(
                baseFileName: self.exportBaseName("Application", jobPosition: jobPosition),
                extension: "pdf",
                in: downloadsURL
            )
            let coverLetterPdfData = self.coverLetterStore.exportPDF(from: coverLetter)
            if let combinedPdfData = self.combinePDFs(pdfDataArray: [coverLetterPdfData, packet.resumePdfData]) {
                do {
                    try combinedPdfData.write(to: fileURL)
                    onToast("Application packet has been exported to \"\(filename)\"")
                } catch {
                    onToast("Failed to export application packet: \(error.localizedDescription)")
                }
            } else {
                onToast("Failed to combine PDFs for application packet.")
            }
        }
    }

    private func exportAllCoverLetters(onToast: @escaping (String) -> Void) {
        guard let jobApp = jobAppStore.selectedApp else {
            onToast("No job application selected. Please select a job application first.")
            return
        }
        let allCoverLetters = jobApp.coverLetters.filter { $0.generated }.sorted(by: { $0.moddedDate > $1.moddedDate })
        if allCoverLetters.isEmpty {
            onToast("No cover letters available to export for this job application.")
            return
        }
        let jobPosition = jobApp.jobPosition
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let (textFileURL, textFilename) = createUniqueFileURL(
            baseFileName: exportBaseName("All Cover Letters", jobPosition: jobPosition),
            extension: "txt",
            in: downloadsURL
        )
        let combinedText = createCombinedCoverLettersText(jobApp: jobApp, coverLetters: allCoverLetters)
        do {
            try combinedText.write(to: textFileURL, atomically: true, encoding: .utf8)
            onToast("All cover letter options have been exported to \"\(textFilename)\"")
        } catch {
            onToast("Failed to export: \(error.localizedDescription)")
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
}
