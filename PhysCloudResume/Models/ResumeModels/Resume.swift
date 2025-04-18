import Foundation
import SwiftData

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

    /// Computed list of all `TreeNode`s that belong to this resume.  This
    /// replaces the previous stored `nodes` array to eliminate strong
    /// reference cycles and manual bookkeeping.
    var nodes: [TreeNode] {
        guard let rootNode else { return [] }
        return Resume.collectNodes(from: rootNode)
    }

    private static func collectNodes(from node: TreeNode) -> [TreeNode] {
        var all: [TreeNode] = [node]
        for child in node.children ?? [] {
            all.append(contentsOf: collectNodes(from: child))
        }
        return all
    }

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

    var pdfData: Data?

    /// Indicates that a PDF export is currently running. This is **transient**
    /// UI‑state only and is therefore excluded from persistence so it does
    /// not pollute the database model.
    @Transient
    var isExporting: Bool = false
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

    /// Loads PDF data from disk into `pdfData` on a background queue.
    /// - Parameter fileURL: The location of the PDF on disk. Defaults to the
    ///   standard `FileHandler.pdfUrl()` path.
    /// - Parameter completion: Optional callback executed on the main queue
    ///   when loading finishes (success or failure).
    func loadPDF(from fileURL: URL = FileHandler.pdfUrl(),
                 completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            defer { DispatchQueue.main.async { completion?() } }
            do {
                let data = try Data(contentsOf: fileURL)
                DispatchQueue.main.async { self?.pdfData = data }
            } catch {
                DispatchQueue.main.async {
                    print("Failed to load PDF file: \(error.localizedDescription)")
                }
            }
        }
    }



    @Transient private var exportWorkItem: DispatchWorkItem?

    /// Debounces repeated export requests so that the network operation is
    /// not triggered excessively while the user is typing.
    /// - Parameters:
    ///   - onStart:   Callback executed immediately when the debounce window
    ///                begins – typically used to toggle a loading indicator.
    ///   - onFinish:  Callback executed after the export attempt (success or
    ///                failure) completes.
    func debounceExport(onStart: (() -> Void)? = nil,
                        onFinish: (() -> Void)? = nil) {
        print("pdf refresh")

        exportWorkItem?.cancel()

        // Toggle the per‑resume loading flag and forward to any external
        // callback so view‑models can react.
        isExporting = true
        onStart?()

        exportWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let jsonFile = FileHandler.saveJSONToFile(jsonString: jsonTxt) {
                Task {
                    do {
                        try await ApiResumeExportService().export(jsonURL: jsonFile, for: self)
                    } catch {
                        print("Resume export failed: \(error)")
                    }

                    // Regardless of success toggle the exporting flag off and
                    // notify any external observers on the main thread.
                    DispatchQueue.main.async {
                        self.isExporting = false
                        onFinish?()
                    }
                }
            } else {
                // No export – reset flag immediately.
                DispatchQueue.main.async {
                    self.isExporting = false
                    onFinish?()
                }
            }
        }

        // Delay half a second before exporting
        if let workItem = exportWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }

    // MARK: - Hashable

    static func == (lhs: Resume, rhs: Resume) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
