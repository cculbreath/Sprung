import Foundation
import PDFKit
import SwiftData
import SwiftUI

@Model
class Resume: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID = UUID()

    var needToTree: Bool = true
    var needToFont: Bool = true

    @Relationship(deleteRule: .cascade)
    var rootNode: TreeNode? // The top-level node
    var fontSizeNodes: [FontSizeNode] = []
    var includeFonts: Bool = false
    var keyLabels: [String: String] = [:]
    var importedEditorKeys: [String] = []
    func label(_ key: String) -> String {
        if let myLabel = keyLabels[key] {
            return myLabel
        } else {
            return key
        }
    }

    var nodes: [TreeNode] = []

    var dateCreated: Date = Date()
    weak var jobApp: JobApp?

    @Relationship(deleteRule: .nullify, inverse: \ResRef.enabledResumes)
    var enabledSources: [ResRef]

    var model: ResModel? = nil // Now properly annotated
    var createdDateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm a 'on' MM/dd/yy"
        return dateFormatter.string(from: dateCreated)
    }

    var textRes: String = ""

    var isUpdating: Bool = false
    var pdfData: Data?
    var jsonTxt: String {
        if let myRoot = rootNode, let json = TreeToJson(rootNode: myRoot)?.buildJsonString() {
            return json
        } else { return "" }
    }

    // Example function
    func getUpdatableNodes() -> [[String: Any]] {
        if let node = rootNode {
            return TreeNode.traverseAndExportNodes(node: node)
        } else {
            return [[:]]
        }
    }

    var meta: String = "\"format\": \"FRESH@0.6.0\", \"version\": \"0.1.0\""

    // Updated initializer to require `resumeModel`
    init(
        jobApp: JobApp,
        enabledSources: [ResRef],
        model: ResModel // Added parameter
    ) {
        self.model = model // Set the required property
        self.jobApp = jobApp
        dateCreated = Date()
        self.enabledSources = enabledSources
    }

    func generateQuery() -> ResumeApiQuery {
        return ResumeApiQuery(resume: self)
    }

    func loadPDF(from fileURL: URL = FileHandler.pdfUrl()) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            do {
                let data = try Data(contentsOf: fileURL)
                DispatchQueue.main.async {
                    self?.pdfData = data
                    self?.isUpdating = false
                }
            } catch {
                DispatchQueue.main.async {
                    print("Failed to load PDF file: \(error.localizedDescription)")
                    self?.isUpdating = false
                }
            }
        }
    }

    func displayPDF() -> PDFView? {
        guard let pdfData else { return nil }
        let pdfView = PDFView()
        DispatchQueue.main.async {
            if let document = PDFDocument(data: pdfData) {
                pdfView.document = document
                pdfView.autoScales = true
            }
        }
        return pdfView
    }

    @Transient private var exportWorkItem: DispatchWorkItem?

    func debounceExport() {
        print("pdf refresh")
        isUpdating = true
        exportWorkItem?.cancel()

        exportWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let jsonFile = FileHandler.saveJSONToFile(jsonString: jsonTxt) {
                apiGenerateResFromJson(jsonPath: jsonFile, resume: self) { success in
                    DispatchQueue.main.async {
                        self.isUpdating = !success
                    }
                }
            }
        }

        // Delay half a second before exporting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: exportWorkItem!)
    }

    // MARK: - Hashable

    static func == (lhs: Resume, rhs: Resume) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
