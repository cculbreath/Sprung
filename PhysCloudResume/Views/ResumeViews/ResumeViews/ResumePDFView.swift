//
//  ResumePDFView.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/20/24.
//

import PDFKit
import SwiftUI

struct ResumePDFView: View {
    @Bindable var resume: Resume
    @State private var needsUpdate: Bool = false

    var body: some View {
        @State var isUpdating = resume.isUpdating

        VStack {
            if let pdfData = resume.pdfData {
                PDFKitWrapper(pdfView: pdfViewer(pdfData: pdfData))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).overlay(alignment: .topTrailing) {
                        if isUpdating {
                            ProgressView().scaleEffect(0.5, anchor: .center).padding(.top, 2).padding(.trailing, 2)
                        }
                    }
            } else {
                Text("No PDF available")
            }
        }
        .onAppear {
            if resume.pdfData == nil {
                if let fileURL = FileHandler.readPdfUrl() {
                    resume.loadPDF(from: fileURL)
                }
            }
        }
//    .onChange(of: resume.pdfData) {
//      needsUpdate.toggle()  // Update the view when pdfData changes
//    }
    }
}

func pdfViewer(pdfData: Data) -> PDFView {
    let pdfDoc = PDFDocument(data: pdfData)
    let pdfView = PDFView()
    pdfView.document = pdfDoc
    pdfView.autoScales = true
    return pdfView
}

struct PDFKitWrapper: NSViewRepresentable {
    let pdfView: PDFView

    func makeNSView(context _: Context) -> PDFView {
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context _: Context) {
        // Update the NSView if needed
        nsView.document = pdfView.document
    }

    typealias NSViewType = PDFView
}
