import PDFKit
import SwiftUI

struct CoverLetterPDFView: View {
    let coverLetter: CoverLetter
    @State private var applicant: Applicant
    @State private var pdfData: Data = .init()
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    init(coverLetter: CoverLetter, applicant: Applicant? = nil) {
        self.coverLetter = coverLetter
        // Use provided applicant or create a default one
        // The real applicant will be loaded in onAppear
        _applicant = State(initialValue: applicant ?? Applicant(
            name: "Christopher Culbreath",
            address: "7317 Shadywood Drive",
            city: "Austin",
            state: "Texas",
            zip: "78745",
            websites: "culbreath.net",
            email: "cc@physicscloud.net",
            phone: "(805) 234-0847"
        ))
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
                    .onAppear {
                        if let doc = PDFDocument(data: pdfData) {
                        } else {
                        }
                    }
            }
        }
        .task {
            // Get the latest applicant profile with signature from the manager
            await loadApplicantProfile()
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
                    self.errorMessage = "Could not generate PDF"
                }
                self.isLoading = false
            }
        }
    }

    @MainActor
    private func loadApplicantProfile() async {
        do {
            // Get the latest profile from the manager to ensure we have the signature
            applicant = Applicant() // This will use the profile from ApplicantProfileManager
        } catch {
        }
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
        }

        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context _: Context) {
        if let document = PDFDocument(data: data) {
            nsView.document = document
        } else {
        }
    }
}
