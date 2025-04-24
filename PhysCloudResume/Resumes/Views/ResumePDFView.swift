//
//  ResumePDFView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

//  ResumePDFView.swift
//  PhysicsCloudResume

import Observation
import PDFKit
import SwiftUI

/// Displays the generated PDF for a given resume along with a small progress
/// indicator while an export job is running.
struct ResumePDFView: View {
    @State private var vm: ResumePDFViewModel

    init(resume: Resume) {
        _vm = State(wrappedValue: ResumePDFViewModel(resume: resume))
    }

    var body: some View {
        @Bindable var vm = vm // enables change tracking for Observation

        VStack {
            if let pdfData = vm.resume.pdfData {
                PDFKitWrapper(pdfView: pdfViewer(pdfData: pdfData))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if vm.resume.isExporting || vm.isUpdating {
                            ProgressView().scaleEffect(0.5)
                                .padding([.top, .trailing], 2)
                        }
                    }
            } else {
                if vm.resume.isExporting || vm.isUpdating {
                    ProgressView()
                } else {
                    Text("No PDF available")
                }
            }
        }
        .onAppear {
            // Lazy‑load a cached PDF if present on disk.
            if vm.resume.pdfData == nil,
               let fileURL = FileHandler.readPdfUrl()
            {
                vm.resume.loadPDF(from: fileURL)
            }
        }
    }
}

// MARK: - PDF helpers -------------------------------------------------------

private func pdfViewer(pdfData: Data?) -> PDFView {
    let pdfView = PDFView()
    if let pdfData {
        pdfView.document = PDFDocument(data: pdfData)
    }
    pdfView.autoScales = true
    return pdfView
}

private struct PDFKitWrapper: NSViewRepresentable {
    let pdfView: PDFView

    func makeNSView(context _: Context) -> PDFView { pdfView }
    func updateNSView(_ nsView: PDFView, context _: Context) { nsView.document = pdfView.document }
    typealias NSViewType = PDFView
}
