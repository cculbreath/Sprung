// Sprung/Resumes/Models/Resume.swift
import Foundation
import SwiftData

/// Where a resume version came from, so the version picker can stop being a
/// guessing game (app-audit 2026-07-06, resume-editor #3). Stamped at each of
/// the three real creation sites: fresh-from-defaults, duplicated, AI-revised.
enum ResumeProvenance: String, Codable, CaseIterable {
    case createdFromDefaults
    case duplicated
    case aiRevised
}

@Model
class Resume: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID = UUID()
    var needToFont: Bool = true

    /// Human label for this version, shown in the banner picker. Defaulted
    /// meaningfully at each creation site (template name plus a provenance
    /// suffix); B2 renders it and sorts the picker.
    var label: String = ""

    /// Raw storage for `provenance`. Defaulted so existing records decode to
    /// `.createdFromDefaults` without a migration.
    private var provenanceRaw: String = ResumeProvenance.createdFromDefaults.rawValue

    /// Where this resume version originated.
    var provenance: ResumeProvenance {
        get { ResumeProvenance(rawValue: provenanceRaw) ?? .createdFromDefaults }
        set { provenanceRaw = newValue.rawValue }
    }
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
    var createdDateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm a 'on' MM/dd/yy"
        return dateFormatter.string(from: dateCreated)
    }
    @Attribute(originalName: "textRes")
    var textResume: String = ""
    var pdfData: Data?
    // MARK: - Last AI Review (Optimize sheet)
    /// Persisted output of the most recent advisory AI review (assess quality /
    /// assess fit / suggest changes / custom). Reopening the Optimize sheet shows
    /// this last analysis with its timestamp instead of losing the markdown — and
    /// the tokens spent — on dismiss. Optional: absent until a review completes.
    var lastReviewMarkdown: String?
    var lastReviewDate: Date?
    var lastReviewType: String?
    /// Serializes the resume tree to a pretty-printed JSON string.
    /// Throws if the context cannot be built or serialized.
    func buildJSON() throws -> String {
        let context = try ResumeTemplateDataBuilder.buildContext(from: self)
        let data = try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Returns true if there are any nodes marked for AI replacement (aiToReplace status)
    var hasUpdatableNodes: Bool {
        guard let rootNode = rootNode else { return false }
        return rootNode.aiStatusChildren > 0
    }

    var meta: String = "\"format\": \"FRESH@0.6.0\", \"version\": \"0.1.0\""
    init(
        jobApp: JobApp,
        template: Template? = nil
    ) {
        self.template = template
        self.jobApp = jobApp
        dateCreated = Date()
    }
    // MARK: - Hashable
    static func == (lhs: Resume, rhs: Resume) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
