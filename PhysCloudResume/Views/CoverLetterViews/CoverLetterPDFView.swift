import SwiftUI
import PDFKit

struct CoverLetterPDFView: View {
    let coverLetter: CoverLetter
    let applicant: Applicant
    @State private var pdfData: Data = Data()
    
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
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if let document = PDFDocument(data: data) {
            nsView.document = document
        }
    }
}