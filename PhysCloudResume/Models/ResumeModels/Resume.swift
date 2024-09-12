import Foundation
import PDFKit
import SwiftData
import SwiftUI

@Model class Resume: Identifiable, Hashable {
  var id: String = ""
  var rootNode: TreeNode?
  var nodes: [TreeNode] = []
  var dateCreated: Date
  weak var jobApp: JobApp?
  @Relationship(inverse: \ResRef.enabledResumes) var enabledSources: [ResRef]
  var createdDateString: String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "hh:mm a 'on' MM/dd/yy"
    return dateFormatter.string(from: dateCreated)
  }
  var textRes: String = ""
  var bgDocs: [ResRef] {
    return self.enabledSources.filter { $0.type == SourceType.background }
  }
  var isUpdating: Bool = false
  var pdfData: Data?
  var attentionGrab: Int = 2
  var hasValidRefsEnabled: Bool {

    let resumeSourceCount = enabledSources.filter { $0.type == .resumeSource }.count
    let jsonSourceCount = enabledSources.filter { $0.type == .jsonSource }.count
    return resumeSourceCount == 1 && jsonSourceCount == 1

  }

  func getUpdatableNodes() -> [[String: String]] {
    if let node = self.rootNode {
      return TreeNode.traverseAndExportNodes(node: node)
    }
    else {return [[:]]}
  }
  var meta: String = "\"format\": \"FRESH@0.6.0\", \"version\": \"0.1.0\""

  // Default initializer
  init?(
    jobApp: JobApp,
    enabledSources: [ResRef]
  ) {
    // Initialize stored properties
    self.id = UUID().uuidString
    self.jobApp = jobApp
    self.dateCreated = Date()
    self.enabledSources = enabledSources

    // Create a temporary variable for rootNode
  }
//  func initialize(jsonText: String) {
//    // Use the temporary variable to store the result of buildTree
//    if let jsonData = jsonText.data(using: .utf8) {  // Convert the string to Data using UTF-8 encoding
//      self.rootNode = self.buildTree(from: jsonData, res: self)
//    } else {
//      print("Cannot convert jsonText to Data")
//    }
//  }




  func generateQuery(attentionGrab: Int) -> ResumeApiQuery {
    self.attentionGrab = attentionGrab
    return ResumeApiQuery(resume: self)
  }
  func loadPDF(from fileURL: URL = FileHandler.pdfUrl()) {
    do {
      print("Loading from URL \(fileURL.path)")
      self.pdfData = try Data(contentsOf: fileURL)
      isUpdating = false
    } catch {
      print("Failed to load PDF file: \(error.localizedDescription)")
    }
  }

  func displayPDF() -> PDFView? {
    guard let pdfData = pdfData else { return nil }
    let pdfView = PDFView()
    if let document = PDFDocument(data: pdfData) {
      pdfView.document = document
      pdfView.autoScales = true
    }
    return pdfView
  }
  @Transient private var exportWorkItem: DispatchWorkItem?

  func debounceExport() {
    print("pdf refresh")
    isUpdating = true
    // Cancel the previous work item if it exists
    exportWorkItem?.cancel()

    // Create a new work item to perform the export
    exportWorkItem = DispatchWorkItem { [weak self] in
      if let jsonString = self?.rebuildJSON() {
        if let jsonFile = FileHandler.saveJSONToFile(jsonString: jsonString) {
          apiGenerateResFromJson(jsonPath: jsonFile) { pdfWebUrl, resumeText in
            if let resumeText = resumeText {
              self?.textRes = resumeText
            }
            if let pdfWebUrl = pdfWebUrl {
              downloadResPDF(from: pdfWebUrl) { pdfFileUrl in
                if let pdfFileUrl = pdfFileUrl {
                  self?.loadPDF(from: pdfFileUrl)
                }
              }
            }
          }
        }
      }
      else {
        print("jsonString problem")
      }
    }


    // Execute the export after a delay of 0.5 seconds (or any delay you want)
    DispatchQueue.main.asyncAfter(
      deadline: .now() + 0.5, execute: self.exportWorkItem!)
  }
}
