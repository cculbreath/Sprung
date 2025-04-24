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
                        print("PDF view appearing with data size: \(pdfData.count)")
                        if let doc = PDFDocument(data: pdfData) {
                            print("PDF has \(doc.pageCount) pages")
                        } else {
                            print("Could not create PDF document from data")
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
        print("Generating PDF view for cover letter...")
        isLoading = true

        // Use a background thread for PDF generation
        DispatchQueue.global(qos: .userInitiated).async {
            let generatedData = CoverLetterPDFGenerator.generatePDF(
                from: coverLetter,
                applicant: applicant
            )

            DispatchQueue.main.async {
                if !generatedData.isEmpty {
                    print("Successfully created PDF data with size: \(generatedData.count)")
                    self.pdfData = generatedData
                    self.errorMessage = nil
                } else {
                    print("Failed to create PDF data")
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
            print("Loaded applicant profile - signature available: \(applicant.profile.signatureData != nil)")
        } catch {
            print("Error loading applicant profile: \(error)")
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
            print("Creating PDFView with document containing \(document.pageCount) pages")
            pdfView.document = document
        } else {
            print("Failed to create PDFDocument in makeNSView")
        }

        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context _: Context) {
        if let document = PDFDocument(data: data) {
            print("Updating PDFView with document containing \(document.pageCount) pages")
            nsView.document = document
        } else {
            print("Failed to create PDFDocument in updateNSView")
        }
    }
}
