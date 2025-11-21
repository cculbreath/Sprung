//
//  ResumePDFView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//
//  ResumePDFView.swift
//  Sprung
import Observation
import PDFKit
import SwiftUI
/// Displays the generated PDF for a given resume along with a small progress
/// indicator while an export job is running.
struct ResumePDFView: View {
    @Bindable var resume: Resume
    var body: some View {
        VStack {
            if let pdfData = resume.pdfData {
                PDFKitWrapper(pdfData: pdfData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if resume.isExporting {
                            ProgressView().scaleEffect(0.5)
                                .padding([.top, .trailing], 2)
                        }
                    }
            } else {
                if resume.isExporting {
                    ProgressView()
                } else {
                    Text("No PDF available")
                }
            }
        }
        .id(resume.id) // Force view recreation when resume changes
    }
}
// MARK: - PDF helpers -------------------------------------------------------
private struct PDFKitWrapper: NSViewRepresentable {
    let pdfData: Data
    func makeNSView(context _: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        return pdfView
    }
    func updateNSView(_ nsView: PDFView, context _: Context) {
        // Update the PDF document when the data changes
        nsView.document = PDFDocument(data: pdfData)
    }
    typealias NSViewType = PDFView
}
