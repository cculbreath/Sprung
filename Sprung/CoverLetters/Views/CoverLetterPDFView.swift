//
//  CoverLetterPDFView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/20/25.
//
import PDFKit
import SwiftUI
struct CoverLetterPDFView: View {
    let coverLetter: CoverLetter
    @Environment(ApplicantProfileStore.self) private var profileStore: ApplicantProfileStore
    @State private var applicant: Applicant
    @State private var pdfData: Data = .init()
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    init(coverLetter: CoverLetter, applicant: Applicant? = nil) {
        self.coverLetter = coverLetter
        // Use provided applicant or create a default one
        // The real applicant will be loaded in onAppear
        _applicant = State(initialValue: applicant ?? .placeholder)
    }
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Generating PDF...")
                    .frame(maxHeight: .infinity)
            } else if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .frame(maxHeight: .infinity)
            } else {
                PDFKitView(data: pdfData)
            }
        }
        .task {
            loadApplicantProfile()
            generatePDF()
        }
    }
    private func generatePDF() {
        isLoading = true
        // Use a background thread for PDF generation
        DispatchQueue.global(qos: .userInitiated).async {
            let generatedData = CoverLetterPDFGenerator.generatePDF(
                from: coverLetter,
                applicant: applicant
            )
            DispatchQueue.main.async {
                if !generatedData.isEmpty {
                    self.pdfData = generatedData
                    self.errorMessage = nil
                } else {
                    Logger.error(
                        "CoverLetterPDFView: Generated PDF data was empty",
                        category: .export
                    )
                    self.errorMessage = "Could not generate PDF"
                }
                self.isLoading = false
            }
        }
    }
    @MainActor
    private func loadApplicantProfile() {
        applicant = Applicant(profile: profileStore.currentProfile())
    }
}
struct PDFKitView: NSViewRepresentable {
    let data: Data
    func makeNSView(context _: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .white
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        } else {
            Logger.warning(
                "PDFKitView: Failed to initialize PDFDocument during make phase",
                category: .export
            )
        }
        return pdfView
    }
    func updateNSView(_ nsView: PDFView, context _: Context) {
        if let document = PDFDocument(data: data) {
            nsView.document = document
        } else {
            Logger.warning(
                "PDFKitView: Failed to update PDFDocument with new data",
                category: .export
            )
        }
    }
}
