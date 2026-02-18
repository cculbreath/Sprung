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

// MARK: - Export File Service

@MainActor
final class ExportFileService {
    private let jobAppStore: JobAppStore
    private let coverLetterStore: CoverLetterStore
    private let resumeExportCoordinator: ResumeExportCoordinator

    init(jobAppStore: JobAppStore,
         coverLetterStore: CoverLetterStore,
         resumeExportCoordinator: ResumeExportCoordinator) {
        self.jobAppStore = jobAppStore
        self.coverLetterStore = coverLetterStore
        self.resumeExportCoordinator = resumeExportCoordinator
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
            baseFileName: "\(jobPosition) Resume",
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
                    baseFileName: "\(jobPosition) Resume",
                    extension: "txt",
                    in: downloadsURL
                )
                do {
                    try resume.textResume.write(to: fileURL, atomically: true, encoding: .utf8)
                    onToast("Resume text has been exported to \"\(filename)\"")
                } catch {
                    onToast("Failed to export text: \(error.localizedDescription)")
                }
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
            baseFileName: "\(jobPosition) Resume",
            extension: "json",
            in: downloadsURL
        )
        let jsonString = resume.jsonTxt
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
            baseFileName: "\(jobPosition) Cover Letter",
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
            baseFileName: "\(jobPosition) Cover Letter",
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
              let resume = jobApp.selectedRes,
              let resumePdfData = resume.pdfData
        else {
            onToast("No resume selected. Please select a resume first.")
            return
        }
        guard let coverLetter = jobApp.selectedCover else {
            onToast("No cover letter selected. Please select a cover letter first.")
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
                onToast("Application packet has been exported to \"\(filename)\"")
            } catch {
                onToast("Failed to export application packet: \(error.localizedDescription)")
            }
        } else {
            onToast("Failed to combine PDFs for application packet.")
        }
    }

    private func exportAllCoverLetters(onToast: @escaping (String) -> Void) {
        guard let jobApp = jobAppStore.selectedApp else {
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
            baseFileName: "\(jobPosition) All Cover Letters",
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
