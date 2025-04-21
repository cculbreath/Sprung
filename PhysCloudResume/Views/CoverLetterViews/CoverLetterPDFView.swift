import PDFKit
import SwiftUI

struct CoverLetterPDFView: View {
    let coverLetter: CoverLetter
    let applicant: Applicant
    @State private var pdfData: Data = .init()

    var body: some View {
        PDFKitView(data: pdfData)
            .onAppear {
                pdfData = CoverLetterPDFGenerator.generatePDF(
                    from: coverLetter,
                    applicant: applicant
                )
            }
    }
}

struct PDFKitView: NSViewRepresentable {
    let data: Data

    func makeNSView(context _: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context _: Context) {
        if let document = PDFDocument(data: data) {
            nsView.document = document
        }
    }
}
