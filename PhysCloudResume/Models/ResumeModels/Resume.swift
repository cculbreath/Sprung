import Foundation
import PDFKit
import SwiftData
import SwiftUI

@Model class Resume: Identifiable, Hashable {
    var id: String
    var rootNode: TreeNode

    var dateCreated: Date
    weak var jobApp: JobApp?
    var enabledSources: [ResRef]
    var createdDateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm a 'on' MM/dd/yy"
        return dateFormatter.string(from: dateCreated)
    }
    var bgDocs: [ResRef] {
        return  self.enabledSources.filter { $0.type == SourceType.background }
    }

    var pdfData: Data?
    var attentionGrab: Int =  2
    var hasValidRefsEnabled: Bool {

            let resumeSourceCount = enabledSources.filter { $0.type == .resumeSource }.count
            let jsonSourceCount = enabledSources.filter { $0.type == .jsonSource }.count
            return resumeSourceCount == 1 && jsonSourceCount == 1

    }



    // Default initializer
    init?(
        jobApp: JobApp,
        templateFileUrl: URL,
        enabledSources: [ResRef]
    ) {
        self.id = UUID().uuidString
        self.jobApp = jobApp
        self.dateCreated = Date()

            if let jsonData = try? Data(contentsOf: templateFileUrl) {
                self.rootNode = Resume.buildTree(from: jsonData)
            } else {
                print("cannot read json at url")
                return nil
            }
        self.enabledSources = enabledSources

    }
    func generateQuery(attentionGrab: Int) -> ResumeApiQuery {
        self.attentionGrab = attentionGrab
        return ResumeApiQuery(resume: self)
    }
    // Method to load PDF data from a file
    func loadPDF(from fileURL: URL) {
        do {
            print("Loading from URL")
            self.pdfData = try Data(contentsOf: fileURL)
        } catch {
            print("Failed to load PDF file: \(error.localizedDescription)")
        }
    }

    // Method to display the PDF (if needed for your logic)
    func displayPDF() -> PDFView? {
        guard let pdfData = pdfData else { return nil }
        let pdfView = PDFView()
        if let document = PDFDocument(data: pdfData) {
            pdfView.document = document
            pdfView.autoScales = true
        }
        return pdfView
    }
}
