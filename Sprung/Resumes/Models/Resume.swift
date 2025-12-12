// Sprung/Resumes/Models/Resume.swift
import Foundation
import SwiftData
@Model
class Resume: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID = UUID()
    var needToTree: Bool = true
    var needToFont: Bool = true
    @Relationship(deleteRule: .cascade)
    var rootNode: TreeNode? // The top-level node
    @Relationship(deleteRule: .cascade, inverse: \FontSizeNode.resume)
    var fontSizeNodes: [FontSizeNode] = []
    var includeFonts: Bool = false
    @Relationship(deleteRule: .nullify, inverse: \Template.resumes)
    var template: Template?
    // Labels for keys previously imported; persisted as keyLabels map
    @Attribute(.externalStorage)
    private var keyLabelsData: Data?
    var keyLabels: [String: String] {
        get {
            guard let keyLabelsData,
                  let decoded = try? JSONDecoder().decode([String: String].self, from: keyLabelsData) else {
                return [:]
            }
            return decoded
        }
        set {
            keyLabelsData = try? JSONEncoder().encode(newValue)
        }
    }
    // Stored raw JSON data for imported editor keys; persisted as Data
    var importedEditorKeysData: Data?
    /// Transient array of editor keys, backed by JSON in importedEditorKeysData
    var importedEditorKeys: [String] {
        get {
            guard let data = importedEditorKeysData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            importedEditorKeysData = try? JSONEncoder().encode(newValue)
        }
    }
    @Attribute(.externalStorage)
    private var sectionVisibilityData: Data?
    var sectionVisibilityOverrides: [String: Bool] {
        get {
            guard let sectionVisibilityData,
                  let decoded = try? JSONDecoder().decode([String: Bool].self, from: sectionVisibilityData) else {
                return [:]
            }
            return decoded
        }
        set {
            sectionVisibilityData = try? JSONEncoder().encode(newValue)
        }
    }
    /// User-configured phase assignments for AI review (maps "Section-attribute" to phase number)
    @Attribute(.externalStorage)
    private var phaseAssignmentsData: Data?
    var phaseAssignments: [String: Int] {
        get {
            guard let phaseAssignmentsData,
                  let decoded = try? JSONDecoder().decode([String: Int].self, from: phaseAssignmentsData) else {
                return [:]
            }
            return decoded
        }
        set {
            phaseAssignmentsData = try? JSONEncoder().encode(newValue)
        }
    }
    func label(_ key: String) -> String {
        if let myLabel = keyLabels[key] {
            return myLabel
        } else {
            return key
        }
    }
    /// Computed list of all `TreeNode`s that belong to this resume.
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
    var createdDateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm a 'on' MM/dd/yy"
        return dateFormatter.string(from: dateCreated)
    }
    @Attribute(originalName: "textRes")
    var textResume: String = ""
    var pdfData: Data?
    @Transient
    var isExporting: Bool = false
    var jsonTxt: String {
        do {
            let context = try ResumeTemplateDataBuilder.buildContext(from: self)
            let data = try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted])
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            Logger.error("Failed to build resume JSON: \(error)")
            return ""
        }
    }
    func getUpdatableNodes() -> [[String: Any]] {
        if let node = rootNode {
            return TreeNode.traverseAndExportNodes(node: node)
        } else {
            return [[:]]
        }
    }
    /// Returns true if there are any nodes marked for AI replacement (aiToReplace status)
    var hasUpdatableNodes: Bool {
        guard let rootNode = rootNode else { return false }
        return rootNode.aiStatusChildren > 0
    }
    var meta: String = "\"format\": \"FRESH@0.6.0\", \"version\": \"0.1.0\""
    init(
        jobApp: JobApp,
        enabledSources: [ResRef],
        template: Template? = nil
    ) {
        self.template = template
        self.jobApp = jobApp
        dateCreated = Date()
        self.enabledSources = enabledSources
    }
    // MARK: - Hashable
    static func == (lhs: Resume, rhs: Resume) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
