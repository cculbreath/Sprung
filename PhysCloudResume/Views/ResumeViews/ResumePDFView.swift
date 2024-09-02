//
//  ResumePDFView.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/20/24.
//

import PDFKit
import SwiftUI

struct ResumePDFView: View {
    var resume: Resume

    var body: some View {
        VStack {
            if let pdfView = resume.displayPDF() {
                PDFKitWrapper(pdfView: pdfView)
                    .frame(
                        maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
            } else {
                Text("No PDF available.")
            }
        }
        .onAppear {
            if resume.pdfData == nil {
                if let fileURL = Bundle.main.url(
                    forResource: "resume", withExtension: "pdf")
                {
                    resume.loadPDF(from: fileURL)
                }
            }
        }
    }
}

struct PDFKitWrapper: NSViewRepresentable {
    let pdfView: PDFView

    func makeNSView(context: Context) -> PDFView {
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Update the NSView if needed
    }

    // Define the associated type explicitly
    typealias NSViewType = PDFView
}
